import Foundation

/// The Microsoft 365 ``RuleStore``: ``GraphMessageRuleClient`` for the wire,
/// ``GraphRuleMapper`` for the translation.
///
/// Everything above this speaks ``MailRule``; nothing above it needs to know
/// Graph exists.
public struct GraphRuleStore: RuleStore {
    public let capabilities = GraphRuleMapper.capabilities

    private let client: GraphMessageRuleClient
    private let mapper = GraphRuleMapper()

    public init(client: GraphMessageRuleClient) {
        self.client = client
    }

    public init(
        tokenProvider: any TokenProvider,
        baseURL: URL = GraphMessageRuleClient.defaultBaseURL,
        session: URLSession = .shared
    ) {
        self.client = GraphMessageRuleClient(
            tokenProvider: tokenProvider, baseURL: baseURL, session: session
        )
    }

    public func listRules() async throws -> [MailRule] {
        try await client.listRules().map(mapper.decode)
    }

    public func rule(id: String) async throws -> MailRule {
        try mapper.decode(try await client.rule(id: id))
    }

    public func createRule(_ rule: MailRule) async throws -> MailRule {
        try mapper.decode(try await client.createRule(try mapper.encode(rule)))
    }

    public func updateRule(id: String, with rule: MailRule) async throws -> MailRule {
        try mapper.decode(try await client.updateRule(id: id, with: try mapper.encode(rule)))
    }

    public func deleteRule(id: String) async throws {
        try await client.deleteRule(id: id)
    }
}
