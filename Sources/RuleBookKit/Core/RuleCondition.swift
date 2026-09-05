import Foundation

/// The kinds of condition the neutral model can express.
///
/// A provider declares which of these it supports in its ``RuleCapabilities``,
/// so an unsupported condition is reported rather than silently dropped.
public enum ConditionKind: String, Codable, Hashable, Sendable, CaseIterable {
    case from
    case recipient
    case subject
    case body
    case subjectOrBody
    case header
    case hasAttachment
    case size
    case importance
    case sensitivity
    case hasLabels
    case addressed
    case messageKind
    case actionFlag
    case rawQuery
}

/// One test against an incoming message.
public enum RuleCondition: Hashable, Sendable {
    case from(StringMatch)
    /// Any recipient — To or Cc.
    case recipient(StringMatch)
    case subject(StringMatch)
    case body(StringMatch)
    case subjectOrBody(StringMatch)
    /// `name` is nil when the provider only supports a raw header substring test.
    case header(name: String?, match: StringMatch)
    case hasAttachment(Bool)
    case size(SizeConstraint)
    case importance(Importance)
    case sensitivity(Sensitivity)
    /// Message already carries these labels/categories.
    case hasLabels([String])
    case addressed(AddressedScope)
    case messageKind(MessageKind, Bool)
    case actionFlag(ActionFlag)
    /// Provider-native search syntax, passed through untouched. The escape
    /// hatch for anything the neutral vocabulary cannot say — inherently
    /// non-portable, so mappers refuse it unless it targets their own provider.
    case rawQuery(provider: ProviderID, query: String)

    public var kind: ConditionKind {
        switch self {
        case .from: .from
        case .recipient: .recipient
        case .subject: .subject
        case .body: .body
        case .subjectOrBody: .subjectOrBody
        case .header: .header
        case .hasAttachment: .hasAttachment
        case .size: .size
        case .importance: .importance
        case .sensitivity: .sensitivity
        case .hasLabels: .hasLabels
        case .addressed: .addressed
        case .messageKind: .messageKind
        case .actionFlag: .actionFlag
        case .rawQuery: .rawQuery
        }
    }
}

// MARK: - Codable

// Hand-written so the on-disk format is a stable, readable discriminated
// union — `{"kind":"subject","match":{...}}` — instead of the nested `_0`
// shape Swift synthesises for enums with associated values.
extension RuleCondition: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, match, value, size, name, labels, scope, query, provider, negated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(ConditionKind.self, forKey: .kind)

        func match() throws -> StringMatch {
            try container.decode(StringMatch.self, forKey: .match)
        }

        switch kind {
        case .from: self = .from(try match())
        case .recipient: self = .recipient(try match())
        case .subject: self = .subject(try match())
        case .body: self = .body(try match())
        case .subjectOrBody: self = .subjectOrBody(try match())
        case .header:
            self = .header(
                name: try container.decodeIfPresent(String.self, forKey: .name),
                match: try match()
            )
        case .hasAttachment:
            self = .hasAttachment(try container.decodeIfPresent(Bool.self, forKey: .value) ?? true)
        case .size:
            self = .size(try container.decode(SizeConstraint.self, forKey: .size))
        case .importance:
            self = .importance(try container.decode(Importance.self, forKey: .value))
        case .sensitivity:
            self = .sensitivity(try container.decode(Sensitivity.self, forKey: .value))
        case .hasLabels:
            self = .hasLabels(try container.decode([String].self, forKey: .labels))
        case .addressed:
            self = .addressed(try container.decode(AddressedScope.self, forKey: .scope))
        case .messageKind:
            self = .messageKind(
                try container.decode(MessageKind.self, forKey: .value),
                try container.decodeIfPresent(Bool.self, forKey: .negated).map { !$0 } ?? true
            )
        case .actionFlag:
            self = .actionFlag(try container.decode(ActionFlag.self, forKey: .value))
        case .rawQuery:
            self = .rawQuery(
                provider: try container.decode(ProviderID.self, forKey: .provider),
                query: try container.decode(String.self, forKey: .query)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)

        switch self {
        case .from(let match), .recipient(let match), .subject(let match),
             .body(let match), .subjectOrBody(let match):
            try container.encode(match, forKey: .match)
        case .header(let name, let match):
            try container.encodeIfPresent(name, forKey: .name)
            try container.encode(match, forKey: .match)
        case .hasAttachment(let value):
            try container.encode(value, forKey: .value)
        case .size(let constraint):
            try container.encode(constraint, forKey: .size)
        case .importance(let value):
            try container.encode(value, forKey: .value)
        case .sensitivity(let value):
            try container.encode(value, forKey: .value)
        case .hasLabels(let values):
            try container.encode(values, forKey: .labels)
        case .addressed(let scope):
            try container.encode(scope, forKey: .scope)
        case .messageKind(let value, let expected):
            try container.encode(value, forKey: .value)
            if !expected { try container.encode(true, forKey: .negated) }
        case .actionFlag(let value):
            try container.encode(value, forKey: .value)
        case .rawQuery(let provider, let query):
            try container.encode(provider, forKey: .provider)
            try container.encode(query, forKey: .query)
        }
    }
}

// MARK: - Description

extension RuleCondition: CustomStringConvertible {
    public var description: String {
        func phrase(_ field: String, _ match: StringMatch) -> String {
            "\(field) \(match.mode.rawValue) \(match.anyOf.map { "\"\($0)\"" }.joined(separator: " or "))"
        }

        switch self {
        case .from(let m): return phrase("from", m)
        case .recipient(let m): return phrase("recipient", m)
        case .subject(let m): return phrase("subject", m)
        case .body(let m): return phrase("body", m)
        case .subjectOrBody(let m): return phrase("subject or body", m)
        case .header(let name, let m): return phrase("header \(name ?? "*")", m)
        case .hasAttachment(let value): return value ? "has an attachment" : "has no attachment"
        case .size(let size):
            let low = size.minimumBytes.map { "\($0)B" } ?? "any"
            let high = size.maximumBytes.map { "\($0)B" } ?? "any"
            return "size between \(low) and \(high)"
        case .importance(let value): return "importance is \(value.rawValue)"
        case .sensitivity(let value): return "sensitivity is \(value.rawValue)"
        case .hasLabels(let values): return "labelled \(values.joined(separator: ", "))"
        case .addressed(let scope): return "addressed \(scope.rawValue)"
        case .messageKind(let value, let expected):
            return expected ? "is a \(value.rawValue)" : "is not a \(value.rawValue)"
        case .actionFlag(let value): return "flagged \(value.rawValue)"
        case .rawQuery(let provider, let query): return "\(provider.rawValue) query: \(query)"
        }
    }
}
