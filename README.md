# RuleBook

A Swift library and command-line harness for **mail rules**, provider-neutral by
design. Microsoft 365 (Outlook) is implemented end to end; Gmail's mapper and
capabilities are in place, its network client is not yet.

`RuleBookKit` holds one neutral model — ``MailRule`` — plus a *mapper* per
provider that translates to that provider's own format and declares what it can
actually express. The app and the CLI only ever see `MailRule`.

## Layout

```
Sources/RuleBookKit/
  Core/                     The neutral model, shared by every provider
    MailRule.swift            A rule: conditions, exceptions, actions
    RuleCondition.swift       What selects a message
    RuleAction.swift          What happens to it
    Primitives.swift          Addresses, folders/labels, sizes, enums
    RuleCapabilities.swift    What one provider can express + the check
    ProviderProfile.swift     Capabilities + vocabulary + the catalog
    Vocabularies.swift        Outlook's and Gmail's own wording
    RuleStore.swift           The CRUD protocol + the mapper protocol
    RuleValidation.swift      Provider-independent structural checks
  Stores/                   InMemoryRuleStore, JSONFileRuleStore
  Providers/
    Microsoft/                Graph wire types, mapper, store, auth
    Google/                   Gmail wire types and mapper
Sources/rulebook/           CLI
Tests/RuleBookKitTests/     Swift Testing suites + JSON fixtures
Scripts/register-app.sh     Creates the Entra ID app registration
```

`RuleBookKit` imports nothing but Foundation — no UIKit, no SwiftUI, no MSAL —
so the same target compiles for the CLI, for iOS, and for the Simulator. Keep
it that way.

## The three layers

**Neutral model.** `MailRule` is what you author, store, diff, and show. It is
a flat list of conditions with a `match` strategy, a list of exceptions, and a
list of actions — deliberately not a nested boolean tree, because no provider
supports one.

**Capabilities.** Every mapper publishes a `RuleCapabilities`: which condition
and action kinds it supports, which match modes, whether it has ordering,
exceptions, or disabling. `RuleCompatibility.check(_:against:)` runs that
locally, so "Gmail can't do that" is an explainable answer before any network
call. The capability check is a fast pre-flight; **the mapper is the
authority** — where a capability holds only in some cases (Outlook matches an
exact address but not an exact subject) `encode` reports the specific case.

**Vocabulary.** The neutral model is what the app *stores*; a
`ProviderVocabulary` is what it *says*. The same `MailRule` reads:

```
Outlook                             Gmail
Rule: Newsletters to Reading        Filter: Newsletters to Reading
  - Subject includes ‘weekly’         - Subject: weekly
  - Move to ‘Reading’                 - Apply the label ‘Reading’, and skip the Inbox
  - Categorize as ‘Bulky’             - Apply the label ‘Bulky’
```

`ProviderProfile` bundles the two: `capabilities` to constrain a form,
`vocabulary` to label it, `availableConditions`/`availableActions` to populate
a picker with only what that provider can do.

## Running it

### With no account at all

```sh
swift test
swift run rulebook providers                              # capability matrix
swift run rulebook describe -f rules.json -p gmail        # Gmail's wording
swift run rulebook translate -f rules.json -p outlook     # the native payload
swift run rulebook validate  -f rules.json -p gmail       # what won't port
```

`--offline <file.json>` points every subcommand at `JSONFileRuleStore` instead
of a live account — same protocol, same validation, writes persisted back:

```sh
cp Tests/RuleBookKitTests/Fixtures/neutral-rules.json /tmp/mailbox.json
swift run rulebook list   --offline /tmp/mailbox.json
swift run rulebook create --offline /tmp/mailbox.json -f new-rule.json
swift run rulebook apply  --offline /tmp/mailbox.json -f rules.json --dry-run
```

Naming a provider alongside `--offline` makes the file behave like that
provider — a Gmail-capability file refuses what Gmail refuses, with no Google
account involved.

### Against a real Microsoft 365 mailbox

Message rules need the **`MailboxSettings.ReadWrite`** delegated Graph scope
(`MailboxSettings.Read` for read-only). The registration must be a **public
client** — no secret — for both the device code flow and MSAL on iOS.

```sh
az login
./Scripts/register-app.sh
export RULEBOOK_CLIENT_ID=<printed>  RULEBOOK_TENANT_ID=<printed>
swift run rulebook login
swift run rulebook list
```

The script prints the **sign-in authority**, which is not always the tenant the
app was registered in: an app that accepts personal Microsoft accounts must
authenticate against `common`, and pinning the registration's tenant GUID would
lock those accounts out.

This repo's registration (a public-client id is not a secret — it ships inside
the app binary; the cached refresh token is what matters, and `.gitignore`
keeps that out):

```sh
export RULEBOOK_CLIENT_ID=72997602-da76-49bd-a1cd-90f67d51bcc6
export RULEBOOK_TENANT_ID=common
```

To try it before registering anything, paste a token from
[Graph Explorer](https://developer.microsoft.com/graph/graph-explorer):

```sh
export RULEBOOK_ACCESS_TOKEN=<token>
```

## Using it from the iOS app

Bind the UI to `RuleStore` and `ProviderProfile`, never to a concrete provider:

```swift
let profile = ProviderCatalog.outlook
let store: any RuleStore = GraphRuleStore(tokenProvider: MSALTokenProvider(app))

// Build a picker from what this provider actually supports
let kinds = profile.availableConditions
let label = profile.vocabulary.name(for: .subject)   // "Subject includes"

// Check before writing
let issues = RuleValidator.validate(rule, for: profile.capabilities)
```

MSAL stays out of the library: conform your own type to `TokenProvider`.
For previews and tests, use `InMemoryRuleStore(seed:capabilities:)`.

## Provider notes

**Outlook / Microsoft 365.** Rules live on the Inbox only
(`/me/mailFolders/inbox/messageRules`). `hasError` and `isReadOnly` are
server-owned and stripped before any write. PATCH is a merge. `sequence` is the
evaluation order and must be unique. `withinSizeRange` is in kilobytes — the
neutral model is in bytes, and the mapper rounds outward so a converted range
never excludes a message the original included.

**Gmail.** Filters have no name, no order, and cannot be disabled; a readable
name is inferred from what the filter does. Almost every effect is a label
change — archive is *remove INBOX*, star is *add STARRED*, delete is *add
TRASH* — and `moveTo` is apply-a-label-and-remove-INBOX, which the decoder
recognises and folds back into a single `moveTo`. Conditions with no typed
criteria field are rendered into Gmail search syntax; exceptions become
`negatedQuery`. There is no PATCH: an update is a delete plus a create.

**Not yet built.** The Gmail HTTP client and its OAuth flow. `GmailRuleMapper`
and its capabilities are complete and tested, so adding the client is a
`RuleStore` conformance over `users.settings.filters`, in the shape of
`GraphRuleStore`.

## Tests

```sh
swift test
```

63 tests, none of which touch a network or an account. The Graph path is
covered against a stubbed `URLProtocol`: the bearer header, `@odata.nextLink`
paging, the mapped request body, Graph error envelopes, and that a rule Outlook
cannot express never reaches the network.

### Against a real mailbox

Two suites talk to a live account, and both are skipped unless you opt in.
They check what a stub structurally cannot: that Graph accepts what the mapper
produces, and that *real* rules — the ones a person actually made — survive the
round trip through the neutral model.

```sh
RULEBOOK_LIVE=1 swift test --filter LiveOutlook                        # read-only
RULEBOOK_LIVE=1 RULEBOOK_LIVE_WRITE=1 swift test --filter LiveOutlook  # + one scratch rule
```

Writes need the second variable, create a single disabled rule named
"RuleBook scratch — safe to delete …", and remove it again. Point them at a
[Microsoft 365 Developer Program](https://developer.microsoft.com/microsoft-365/dev-program)
tenant rather than a mailbox you care about.
