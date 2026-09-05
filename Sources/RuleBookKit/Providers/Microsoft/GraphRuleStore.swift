import Foundation

/// The Microsoft 365 ``RuleStore``: ``GraphMessageRuleClient`` for the wire,
/// ``GraphRuleMapper`` for the translation.
///
/// Everything above this speaks ``MailRule``; nothing above it needs to know
/// Graph exists.
///
/// Given a ``FolderDirectory``, the store also resolves folder references in
/// both directions — opaque Graph ids become readable paths on the way out,
/// and a folder named by a person becomes an id on the way in. Resolution is
/// best-effort: if `Mail.ReadBasic` has not been consented, rules still load
/// and show their raw ids.
public struct GraphRuleStore: RuleStore {
    public let capabilities = GraphRuleMapper.capabilities

    private let client: GraphMessageRuleClient
    private let mapper = GraphRuleMapper()
    private let directory: (any FolderDirectory)?

    public init(client: GraphMessageRuleClient, folders directory: (any FolderDirectory)? = nil) {
        self.client = client
        self.directory = directory
    }

    /// - Parameter resolveFolderNames: when true (the default), the store
    ///   builds a ``GraphMailFolderDirectory`` from the same credentials.
    public init(
        tokenProvider: any TokenProvider,
        baseURL: URL = GraphMessageRuleClient.defaultBaseURL,
        session: URLSession = .shared,
        resolveFolderNames: Bool = true
    ) {
        self.client = GraphMessageRuleClient(
            tokenProvider: tokenProvider, baseURL: baseURL, session: session
        )
        self.directory = resolveFolderNames
            ? GraphMailFolderDirectory(tokenProvider: tokenProvider, baseURL: baseURL, session: session)
            : nil
    }

    public func listRules() async throws -> [MailRule] {
        var resolved: [MailRule] = []
        for native in try await client.listRules() {
            resolved.append(await resolvingFolders(in: try mapper.decode(native)))
        }
        return resolved
    }

    public func rule(id: String) async throws -> MailRule {
        await resolvingFolders(in: try mapper.decode(try await client.rule(id: id)))
    }

    public func createRule(_ rule: MailRule) async throws -> MailRule {
        let addressed = await resolvingFolders(in: rule)
        return await resolvingFolders(in: try mapper.decode(try await client.createRule(try mapper.encode(addressed))))
    }

    public func updateRule(id: String, with rule: MailRule) async throws -> MailRule {
        let addressed = await resolvingFolders(in: rule)
        return await resolvingFolders(
            in: try mapper.decode(try await client.updateRule(id: id, with: try mapper.encode(addressed)))
        )
    }

    public func deleteRule(id: String) async throws {
        try await client.deleteRule(id: id)
    }

    // MARK: - Folder resolution

    /// One pass serves both directions: ``FolderDirectory/resolve(_:)`` fills
    /// in whichever half of the reference is missing — the name when reading,
    /// the id when writing.
    private func resolvingFolders(in rule: MailRule) async -> MailRule {
        guard let directory else { return rule }

        var resolved: [RuleAction] = []
        for action in rule.actions {
            switch action {
            case .moveTo(let folder): resolved.append(.moveTo(await directory.resolve(folder)))
            case .copyTo(let folder): resolved.append(.copyTo(await directory.resolve(folder)))
            case .addLabel(let folder): resolved.append(.addLabel(await directory.resolve(folder)))
            case .removeLabel(let folder): resolved.append(.removeLabel(await directory.resolve(folder)))
            default: resolved.append(action)
            }
        }

        var updated = rule
        updated.actions = resolved
        return updated
    }
}
