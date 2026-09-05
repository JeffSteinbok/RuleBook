import Foundation

/// An in-process ``RuleStore`` for tests, previews, and offline CLI runs.
///
/// Reproduces the behaviour call sites depend on: provider-assigned ids,
/// merge-on-update, and rules coming back in evaluation order.
public actor InMemoryRuleStore: RuleStore {
    public nonisolated let capabilities: RuleCapabilities

    private var storage: [String: MailRule] = [:]
    private var nextID: Int = 1

    public init(seed: [MailRule] = [], capabilities: RuleCapabilities = .unrestricted) {
        self.capabilities = capabilities
        for rule in seed {
            var stored = rule
            if stored.id == nil {
                stored.id = "rule-\(nextID)"
                nextID += 1
            }
            storage[stored.id!] = stored
        }
    }

    private func makeID() -> String {
        defer { nextID += 1 }
        return "rule-\(nextID)"
    }

    public func listRules() async throws -> [MailRule] {
        storage.values.sorted { ($0.order ?? .max, $0.name) < ($1.order ?? .max, $1.name) }
    }

    public func rule(id: String) async throws -> MailRule {
        guard let rule = storage[id] else { throw RuleStoreError.notFound(id: id) }
        return rule
    }

    public func createRule(_ rule: MailRule) async throws -> MailRule {
        var created = rule.writablePayload()
        created.id = makeID()
        storage[created.id!] = created
        return created
    }

    /// Merge semantics: `nil` order and empty collections leave what is stored alone.
    public func updateRule(id: String, with rule: MailRule) async throws -> MailRule {
        guard var existing = storage[id] else { throw RuleStoreError.notFound(id: id) }
        let patch = rule.writablePayload()

        existing.name = patch.name
        existing.isEnabled = patch.isEnabled
        existing.match = patch.match
        if let order = patch.order { existing.order = order }
        if !patch.conditions.isEmpty { existing.conditions = patch.conditions }
        if !patch.exceptions.isEmpty { existing.exceptions = patch.exceptions }
        if !patch.actions.isEmpty { existing.actions = patch.actions }

        storage[id] = existing
        return existing
    }

    public func deleteRule(id: String) async throws {
        guard storage.removeValue(forKey: id) != nil else {
            throw RuleStoreError.notFound(id: id)
        }
    }
}
