import Foundation

/// CRUD over one mailbox's rules, in the neutral model.
///
/// Every backend conforms: Microsoft 365, Gmail (once its client lands), and
/// the local JSON/in-memory stores. Call sites — the iOS app, the CLI — only
/// ever see ``MailRule``.
public protocol RuleStore: Sendable {
    /// What this backend can express. Check a rule against it before writing.
    var capabilities: RuleCapabilities { get }

    func listRules() async throws -> [MailRule]
    func rule(id: String) async throws -> MailRule
    func createRule(_ rule: MailRule) async throws -> MailRule
    func updateRule(id: String, with rule: MailRule) async throws -> MailRule
    func deleteRule(id: String) async throws
}

/// Translates between the neutral model and one provider's wire format.
public protocol RuleMapper: Sendable {
    associatedtype Native

    static var capabilities: RuleCapabilities { get }

    /// - Throws: ``MappingError/unsupported(_:)`` listing every feature the
    ///   provider cannot represent, rather than dropping them quietly.
    func encode(_ rule: MailRule) throws -> Native
    func decode(_ native: Native) throws -> MailRule
}

public extension RuleMapper {
    var capabilities: RuleCapabilities { Self.capabilities }
}

public enum MappingError: Error, LocalizedError {
    case unsupported([ValidationIssue])
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let issues):
            return issues.map(\.description).joined(separator: "\n")
        case .malformed(let detail):
            return "Could not interpret the provider's rule: \(detail)"
        }
    }
}

public enum RuleStoreError: Error, LocalizedError, Sendable {
    case notFound(id: String)
    case notAuthenticated
    /// A non-2xx response, with the provider's own error code and message.
    case provider(ProviderID, status: Int, code: String?, message: String?)
    case transport(any Error)
    case decoding(any Error)

    public var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "No rule with id \(id)."
        case .notAuthenticated:
            return "Not signed in. Run `rulebook login` first."
        case .provider(let provider, let status, let code, let message):
            let detail = [code, message].compactMap { $0 }.joined(separator: ": ")
            return detail.isEmpty
                ? "\(provider.rawValue) returned HTTP \(status)."
                : "\(provider.rawValue) returned HTTP \(status) — \(detail)"
        case .transport(let error):
            return "Network error: \(error.localizedDescription)"
        case .decoding(let error):
            return "Could not decode the provider response: \(error)"
        }
    }
}
