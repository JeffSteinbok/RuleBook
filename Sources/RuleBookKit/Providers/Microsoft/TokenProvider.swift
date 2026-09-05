import Foundation

/// Supplies a bearer token for Microsoft Graph.
///
/// The library deliberately does not depend on MSAL. On iOS you conform an
/// MSAL-backed type to this protocol; the CLI uses ``DeviceCodeTokenProvider``.
public protocol TokenProvider: Sendable {
    /// A valid access token, refreshing it if needed.
    func accessToken() async throws -> String
}

/// A fixed token — useful for Graph Explorer tokens and for tests.
public struct StaticTokenProvider: TokenProvider {
    private let token: String
    public init(_ token: String) { self.token = token }
    public func accessToken() async throws -> String { token }
}

/// Scopes required by the message rules API.
public enum GraphScopes {
    /// Read and write mailbox settings, which is what `messageRules` lives under.
    public static let mailboxSettingsReadWrite = "MailboxSettings.ReadWrite"
    /// Read-only variant, enough for `rulebook list` / `export`.
    public static let mailboxSettingsRead = "MailboxSettings.Read"
    /// Reads the mail folder tree, so a rule that references a folder by
    /// opaque id can be shown with its name. `messageRules` lives under mailbox
    /// settings; folders are a separate resource with their own permission.
    ///
    /// The only scope that reads `/me/mailFolders` on *every* account type —
    /// and it also grants the sender, recipients and subject of every message
    /// in the mailbox. Far too much to pay for folder names, so it is not in
    /// ``default``: see ``withFolderNames``.
    public static let mailReadBasic = "Mail.ReadBasic"

    /// Reads the folder tree without any access to messages. **Work/school
    /// accounts only**: requesting it via `/common` or `/consumers` fails with
    /// AADSTS70011, and `/common` must satisfy both audiences, so an app that
    /// accepts personal Microsoft accounts cannot use it.
    public static let mailboxFolderRead = "MailboxFolder.Read"

    /// Creates and renames folders with no access to messages — the cheap way
    /// to let someone file mail into a new folder, where `Mail.ReadWrite`
    /// would grant the contents of every message. Same work/school-only limit
    /// as ``mailboxFolderRead``.
    public static let mailboxFolderReadWrite = "MailboxFolder.ReadWrite"
    /// Needed to get a refresh token from the device code flow.
    public static let offlineAccess = "offline_access"

    /// The default set the CLI and the app request: rules, and nothing else.
    /// No access to messages or folders of any kind.
    public static let `default` = [mailboxSettingsReadWrite, offlineAccess]

    /// Opt-in: adds folder-name resolution at the cost of `Mail.ReadBasic`.
    /// Requesting this triggers a fresh consent prompt naming mail access, so
    /// ask for it only when someone has chosen readable folder names over the
    /// narrower permission.
    public static let withFolderNames = [mailboxSettingsReadWrite, mailReadBasic, offlineAccess]

    /// The read-only set: enough to list rules, without naming their folders.
    public static let readOnly = [mailboxSettingsRead, offlineAccess]

    /// The tightest set that still names folders, for a work/school-only build.
    /// Swaps `Mail.ReadBasic` — which grants message metadata — for the
    /// folder-scoped permission personal accounts cannot request.
    public static let workAccountsOnly = [mailboxSettingsReadWrite, mailboxFolderRead, offlineAccess]
}
