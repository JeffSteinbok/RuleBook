# RuleBook

An iOS app for managing mail rules — the filters that file, forward, flag, and
delete your mail before you ever see it. Microsoft 365 today, Gmail next.

The app is not built yet. What exists is the engine it will run on: a
provider-neutral rules model, a Microsoft 365 implementation that works
end to end, and a command-line harness for driving all of it without an app.

## Repository layout

```
Package.swift              Swift package: the library and the CLI
Sources/
  RulebookKit/             The library the iOS app links
    Core/                    Neutral model — MailRule, conditions, actions
    Providers/Microsoft/     Graph wire types, mapper, store, auth
    Providers/Google/        Gmail wire types and mapper
    Stores/                  In-memory and JSON-file stores
  rulebook/                CLI harness
Tests/
  RulebookKitTests/        Hermetic: no network, no account
  RulebookLiveTests/       Talks to a real mailbox; opt-in
Scripts/register-app.sh    Creates the Entra ID app registration
App/                       The iOS app (not yet created)
```

`Package.swift` stays at the repository root on purpose. SwiftPM only
recognises a manifest at the root, so keeping it there is what lets the library
be consumed as `.package(url: "https://github.com/JeffSteinbok/Rulebook")`.
The Xcode project in `App/` will reference the package locally, at `../`, so
edits to `RulebookKit` show up in the app immediately with no versioning step.

`RulebookKit` imports nothing but Foundation — no UIKit, no SwiftUI, no MSAL —
which is what lets one target build for iOS, the Simulator, and the CLI. Keep
it that way: UI belongs in `App/`, and MSAL arrives through a protocol.

## How the library is put together

**Neutral model.** `MailRule` is what the app authors, stores, and displays: a
flat list of conditions with a `match` strategy, a list of exceptions, and a
list of actions. Flat rather than a nested boolean tree, deliberately — no mail
provider supports one, so a tree would be a model that could never be mapped.

**Capabilities.** Each provider publishes a `RuleCapabilities` saying what it
can express, and `RuleCompatibility.check(_:against:)` runs that locally. So
"Gmail can't do that" is an explainable answer before any network call. The
check is a pre-flight; **the mapper is the authority** — where a capability
holds only in some cases (Outlook matches an exact address but not an exact
subject) `encode` reports the specific case.

Lossy mappings are refused, never silently dropped. A rule that stops
processing is usually shielding a message from a later, destructive rule; Gmail
runs every matching filter, so quietly dropping the action would lose mail. The
refusal names the portable alternative instead.

**Vocabulary.** The model is what the app stores; a `ProviderVocabulary` is
what it *says*. One `MailRule`, two products:

```
Outlook                              Gmail
Rule: Newsletters to Reading         Filter: Newsletters to Reading
  - Subject includes ‘weekly’          - Subject: weekly
  - Move to ‘Reading’                  - Apply the label ‘Reading’, and skip the Inbox
  - Message size at least 5120 KB      - Size greater than 5 MB
```

`ProviderProfile` bundles the two — `capabilities` to constrain a form,
`vocabulary` to label it, `availableConditions` / `availableActions` to fill a
picker with only what that provider can do. **The app's screens should bind to
`ProviderProfile` and `RuleStore`, never to a concrete provider.**

## Building the app on this

```swift
let profile = ProviderCatalog.outlook
let store: any RuleStore = GraphRuleStore(tokenProvider: MSALTokenProvider(app))

let kinds = profile.availableConditions              // only what Outlook can do
let label = profile.vocabulary.name(for: .subject)   // "Subject includes"
let issues = RuleValidator.validate(rule, for: profile.capabilities)
```

MSAL stays out of the library: conform your own type to `TokenProvider`. For
previews and tests, use `InMemoryRuleStore(seed:capabilities:)` — no network,
no auth.

## The CLI harness

Everything below runs with no account at all:

```sh
swift run rulebook providers                           # capability matrix
swift run rulebook describe -f rules.json -p gmail     # in Gmail's wording
swift run rulebook translate -f rules.json -p outlook  # the native payload
swift run rulebook validate  -f rules.json -p gmail    # what won't port
```

`--offline <file.json>` points every subcommand at `JSONFileRuleStore` instead
of a live account — same protocol, same validation, writes persisted back.
Naming a provider alongside it makes the file behave like that provider, so a
Gmail-capability file refuses what Gmail refuses with no Google account.

```sh
cp Tests/RulebookKitTests/Fixtures/neutral-rules.json /tmp/mailbox.json
swift run rulebook list   --offline /tmp/mailbox.json
swift run rulebook apply  --offline /tmp/mailbox.json -f rules.json --dry-run
```

### Against a real Microsoft 365 mailbox

```sh
az login
./Scripts/register-app.sh
export RULEBOOK_CLIENT_ID=<printed>  RULEBOOK_TENANT_ID=<printed>
swift run rulebook login       # device code; prints a code to enter in a browser
swift run rulebook list
swift run rulebook folders
```

The script prints the **sign-in authority**, which is not always the tenant the
app was registered in: an app accepting personal Microsoft accounts must
authenticate against `common`, and pinning the registration's tenant GUID
would lock those accounts out.

To poke around before registering anything, paste a token from
[Graph Explorer](https://developer.microsoft.com/graph/graph-explorer) into
`RULEBOOK_ACCESS_TOKEN`.

## Permissions

Requested at sign-in, all delegated:

| Scope | Why |
| --- | --- |
| `MailboxSettings.ReadWrite` | Read and write inbox rules. The core of the app. |
| `Mail.ReadBasic` | List `/me/mailFolders`, so someone can choose where a rule files mail. |
| `offline_access` | Refresh token, so sign-in is not constant. |

`Mail.ReadBasic` is broader than this app wants — it also grants the sender,
recipients, and subject of every message. `MailboxFolder.Read` would be exact
(folders, no messages) but it is **work/school accounts only**: requesting it
via `/consumers` or `/common` fails with AADSTS70011, and `/common` must
satisfy both audiences. Since personal accounts are the expected audience,
`Mail.ReadBasic` is the only option. `GraphScopes.workAccountsOnly` is ready
for a build that drops personal accounts, where folder access costs nothing
extra — and where `MailboxFolder.ReadWrite` would allow creating folders
without any access to mail.

Check a scope against an authority before trusting it:

```sh
curl -s -X POST https://login.microsoftonline.com/common/oauth2/v2.0/devicecode \
  -d client_id=$RULEBOOK_CLIENT_ID --data-urlencode "scope=MailboxFolder.Read offline_access"
```

Being listed on the Graph service principal does not mean a scope is
requestable. Worse, combining an invalid scope with a valid one still issues a
device code and only fails at consent — which surfaces to the user as "the code
has expired."

## Provider notes

**Outlook.** Rules live on the Inbox only
(`/me/mailFolders/inbox/messageRules`). `hasError` and `isReadOnly` are
server-owned and stripped before any write. PATCH is a merge. `sequence` is the
evaluation order and must be unique. `withinSizeRange` is in kilobytes while
the neutral model is in bytes; the mapper rounds outward so a converted range
never excludes a message the original included.

`hasError` is not a reliable signal — a rule can point at a deleted folder and
still be reported healthy, silently dropping mail. Validating folder references
independently catches what Outlook misses.

**Gmail.** Filters have no name, no order, and cannot be disabled; a readable
name is inferred from what the filter does. Nearly every effect is a label
change — archive is *remove INBOX*, star is *add STARRED*, delete is *add
TRASH* — and `moveTo` is apply-a-label-and-remove-INBOX, which the decoder
folds back into a single `moveTo`. Conditions with no typed criteria field are
rendered into search syntax; exceptions become `negatedQuery`. There is no
PATCH: an update is a delete plus a create.

**Not built yet.** The Gmail HTTP client and its OAuth flow. The mapper and
capabilities are complete and tested, so adding the client is a `RuleStore`
conformance over `users.settings.filters`, shaped like `GraphRuleStore`.

## Tests

```sh
swift test
```

Hermetic — no network, no account. The Graph path is covered against a stubbed
`URLProtocol`: the bearer header, `@odata.nextLink` paging, the mapped request
body, error envelopes, and that a rule Outlook cannot express never reaches the
network.

### Against a real mailbox

A separate target, skipped unless you opt in. It checks what a stub
structurally cannot: that Graph accepts what the mapper produces, and that
*real* rules survive the round trip through the neutral model.

```sh
RULEBOOK_LIVE=1 swift test --filter LiveOutlook                        # read-only
RULEBOOK_LIVE=1 RULEBOOK_LIVE_WRITE=1 swift test --filter LiveOutlook  # + one scratch rule
```

Writes need the second variable, create a single disabled rule named
"RuleBook scratch — safe to delete …", and remove it again. Point them at a
[Microsoft 365 Developer Program](https://developer.microsoft.com/microsoft-365/dev-program)
tenant rather than a mailbox you care about.
