import Foundation
import MSAL
import RuleBookKit

/// The only MSAL-aware type in the app.
///
/// `RuleBookKit` imports nothing but Foundation and takes its bearer token
/// through `TokenProvider` — so MSAL stops here and never reaches the library
/// or the view models.
///
/// Authority is `common`, not the registration's tenant GUID:
/// `Scripts/register-app.sh` prints the sign-in authority for this reason, and
/// pinning a tenant locks out personal Microsoft accounts.
actor MSALTokenProvider: TokenProvider {

    enum AuthError: LocalizedError {
        case noAccount
        case cancelled
        case interactionRequired

        var errorDescription: String? {
            switch self {
            case .noAccount: "No mailbox is connected."
            case .cancelled: "Sign-in was cancelled."
            case .interactionRequired: "Please sign in again."
            }
        }
    }

    private let application: MSALPublicClientApplication
    private let scopes: [String]
    private var account: MSALAccount?

    init(clientID: String, scopes: [String] = GraphScopes.default) throws {
        let authority = try MSALAuthority(
            url: URL(string: "https://login.microsoftonline.com/common")!
        )
        let config = MSALPublicClientApplicationConfig(
            clientId: clientID,
            redirectUri: nil,          // msauth.<bundle-id>://auth, from Info.plist
            authority: authority
        )

        // MSAL defaults its token cache to the shared `com.microsoft.adalcache`
        // keychain group, which needs a keychain-sharing entitlement — and that
        // entitlement cannot resolve under the simulator's ad-hoc signature,
        // where $(AppIdentifierPrefix) expands to nothing. Every call then fails
        // as MSALErrorInternal (-50000), with the real reason only in the device
        // log. Keeping the cache in the app's own group avoids the entitlement
        // entirely; the shared group only exists to enable SSO with other
        // Microsoft apps, which this app does not do.
        config.cacheConfig.keychainSharingGroup = Bundle.main.bundleIdentifier ?? clientID

        self.application = try MSALPublicClientApplication(configuration: config)
        self.scopes = scopes
        self.account = try? application.allAccounts().first
    }

    var isSignedIn: Bool { account != nil }

    var signedInAddress: String? { account?.username }

    /// MSAL's stable per-account key, used as the `Account.id`.
    var accountIdentifier: String? { account?.identifier }

    // MARK: - TokenProvider

    /// Silent first, interactive only when the refresh token is gone. The app
    /// should never see a login screen on a warm launch.
    func accessToken() async throws -> String {
        guard let account else { throw AuthError.noAccount }

        do {
            let params = MSALSilentTokenParameters(scopes: scopes, account: account)
            return try await withCheckedThrowingContinuation { continuation in
                application.acquireTokenSilent(with: params) { result, error in
                    if let result { continuation.resume(returning: result.accessToken) }
                    else { continuation.resume(throwing: error ?? AuthError.interactionRequired) }
                }
            }
        } catch let error as NSError where error.code == MSALError.interactionRequired.rawValue {
            return try await signIn()
        }
    }

    // MARK: - Interactive

    /// Presents `ASWebAuthenticationSession` via MSAL's webview parameters, so
    /// Microsoft's own page handles the password, MFA, conditional access and
    /// consent. The app never renders a credential field.
    @MainActor
    private func presentationAnchor() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow?.rootViewController
    }

    @discardableResult
    func signIn(loginHint: String? = nil) async throws -> String {
        guard let anchor = await presentationAnchor() else { throw AuthError.cancelled }

        let webParams = MSALWebviewParameters(authPresentationViewController: anchor)
        // .default routes to ASWebAuthenticationSession, which shares the
        // system cookie jar — so an existing Outlook session signs in silently.
        webParams.webviewType = .default

        let params = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webParams)
        params.promptType = .selectAccount
        params.loginHint = loginHint

        let result: MSALResult = try await withCheckedThrowingContinuation { continuation in
            application.acquireToken(with: params) { result, error in
                if let result { continuation.resume(returning: result) }
                else if let error = error as NSError?,
                        error.code == MSALError.userCanceled.rawValue {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? AuthError.interactionRequired)
                }
            }
        }

        account = result.account
        return result.accessToken
    }

    func signOut() throws {
        guard let account else { return }
        let params = MSALSignoutParameters()
        // Clears the token cache; the rules stay on the server and keep running.
        try application.remove(account)
        _ = params
        self.account = nil
    }
}
