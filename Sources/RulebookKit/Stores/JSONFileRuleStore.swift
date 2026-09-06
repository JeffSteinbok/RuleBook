import Foundation

/// A ``RuleStore`` backed by a JSON file of neutral ``MailRule`` values.
///
/// Same semantics as ``InMemoryRuleStore`` — it composes one — but every
/// mutation is written back, so the CLI behaves across invocations the way it
/// would against a real mailbox. This is what `rulebook --offline` uses.
///
/// Pass `capabilities` to make the file behave like one provider: a store
/// created with Gmail's capabilities refuses what Gmail refuses, without a
/// Google account.
public actor JSONFileRuleStore: RuleStore {
    public nonisolated let capabilities: RuleCapabilities

    private let url: URL
    private let inner: InMemoryRuleStore

    public init(url: URL, capabilities: RuleCapabilities = .unrestricted) throws {
        self.url = url
        self.capabilities = capabilities

        let seed: [MailRule]
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            seed = data.isEmpty ? [] : try JSONDecoder().decode([MailRule].self, from: data)
        } else {
            seed = []
        }
        self.inner = InMemoryRuleStore(seed: seed, capabilities: capabilities)
    }

    public func listRules() async throws -> [MailRule] {
        try await inner.listRules()
    }

    public func rule(id: String) async throws -> MailRule {
        try await inner.rule(id: id)
    }

    public func createRule(_ rule: MailRule) async throws -> MailRule {
        let created = try await inner.createRule(rule)
        try await persist()
        return created
    }

    public func updateRule(id: String, with rule: MailRule) async throws -> MailRule {
        let updated = try await inner.updateRule(id: id, with: rule)
        try await persist()
        return updated
    }

    public func deleteRule(id: String) async throws {
        try await inner.deleteRule(id: id)
        try await persist()
    }

    private func persist() async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(try await inner.listRules()).write(to: url, options: .atomic)
    }
}
