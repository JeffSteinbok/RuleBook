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
    /// Needed to get a refresh token from the device code flow.
    public static let offlineAccess = "offline_access"

    /// The default set the CLI and the app request.
    public static let `default` = [mailboxSettingsReadWrite, offlineAccess]
}
