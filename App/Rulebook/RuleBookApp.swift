import SwiftUI
import RulebookKit

@main
struct RulebookApp: App {
    @State private var accounts = AccountStore()
    @State private var tokens: MSALTokenProvider?
    @State private var bootError: String?

    /// Set in the build settings or an xcconfig; `register-app.sh` prints it.
    private var clientID: String {
        Bundle.main.object(forInfoDictionaryKey: "RulebookClientID") as? String ?? ""
    }

    /// Runs the whole app on `InMemoryRuleStore` with the preview seed: no
    /// MSAL, no network, no Azure. The brief asks for gestures to be judged on
    /// a real touch loop before auth exists, and the seed carries all four
    /// diagnostic states, so this is also how the screenshots get taken.
    private var isDemo: Bool {
        ProcessInfo.processInfo.arguments.contains("-demo")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isDemo {
                    RulesListView(model: RulesListViewModel(
                        store: PreviewSeed.store(),
                        folders: PreviewSeed.folders,
                        profile: ProviderCatalog.outlook
                    ))
                } else if let tokens {
                    // A connected mailbox means onboarding has nothing to do —
                    // launch straight into the rules.
                    if accounts.isEmpty {
                        GateView(tokens: tokens, accounts: accounts)
                    } else {
                        RootView(tokens: tokens, accounts: accounts)
                    }
                } else if let bootError {
                    BootFailureView(message: bootError)
                } else {
                    ProgressView().task { start() }
                }
            }
            .tint(DS.Palette.accent)
        }
    }

    private func start() {
        do {
            tokens = try MSALTokenProvider(clientID: clientID)
        } catch {
            bootError = error.localizedDescription
        }
    }
}

/// Owns the one view model the whole signed-in app shares, so switching
/// mailboxes rebuilds it rather than leaving stale rules on screen.
struct RootView: View {
    let tokens: MSALTokenProvider
    let accounts: AccountStore

    @State private var model: RulesListViewModel?

    var body: some View {
        Group {
            if let model {
                RulesListView(model: model, accounts: accounts, tokens: tokens)
            } else {
                ProgressView()
            }
        }
        .task(id: accounts.activeID) { rebuild() }
    }

    private func rebuild() {
        // Both stores are `any RuleStore`, so this is the only line that knows
        // the app talks to Graph at all.
        model = RulesListViewModel(
            store: GraphRuleStore(tokenProvider: tokens),
            folders: GraphMailFolderDirectory(tokenProvider: tokens),
            profile: ProviderCatalog.outlook
        )
    }
}

private struct BootFailureView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rulebook couldn't start")
                .font(DS.Font.sectionTitle)
            Text(message)
                .font(DS.Font.body)
                .foregroundStyle(DS.Palette.ink60)
            Text("Check that RulebookClientID is set in Info.plist and the redirect URI matches the app registration.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Palette.ink60)
        }
        .padding(DS.Metric.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Palette.ground)
    }
}
