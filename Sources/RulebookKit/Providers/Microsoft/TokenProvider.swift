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
    /// Reads `/me/mailFolders`, which the app needs to let anyone choose a
    /// destination folder — so any rule that moves mail depends on it.
    ///
    /// It also grants the sender, recipients and subject of every message in
    /// the mailbox, which is more than this app wants. ``mailboxFolderRead``
    /// would be the precise scope, but personal Microsoft accounts do not have
    /// it, and they are the expected audience.
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

    /// The default set the CLI and the app request. Asked for once, at sign-in:
    /// choosing a destination folder needs `Mail.ReadBasic`, and a rules app
    /// that cannot file mail is not much of one — so deferring it only moves
    /// the same prompt into the middle of someone's first real task.
    public static let `default` = [mailboxSettingsReadWrite, mailReadBasic, offlineAccess]

    /// The read-only set: list and inspect rules, change nothing.
    public static let readOnly = [mailboxSettingsRead, mailReadBasic, offlineAccess]

    /// The tightest set that still names folders, for a work/school-only build.
    /// Swaps `Mail.ReadBasic` — which grants message metadata — for the
    /// folder-scoped permission personal accounts cannot request.
    public static let workAccountsOnly = [mailboxSettingsReadWrite, mailboxFolderRead, offlineAccess]
}
