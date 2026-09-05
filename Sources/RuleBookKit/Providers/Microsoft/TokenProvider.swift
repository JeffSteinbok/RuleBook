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
    /// `MailboxFolder.Read` looks like the tighter fit and is listed on the
    /// Graph service principal, but requesting it fails with AADSTS70011
    /// ("the scope does not exist"), so it is not usable in a delegated token
    /// request. `Mail.ReadBasic` is the real minimum for `/me/mailFolders`.
    public static let mailReadBasic = "Mail.ReadBasic"
    /// Needed to get a refresh token from the device code flow.
    public static let offlineAccess = "offline_access"

    /// The default set the CLI and the app request.
    public static let `default` = [mailboxSettingsReadWrite, mailReadBasic, offlineAccess]

    /// The read-only set: enough to list rules and name their folders.
    public static let readOnly = [mailboxSettingsRead, mailReadBasic, offlineAccess]
}
