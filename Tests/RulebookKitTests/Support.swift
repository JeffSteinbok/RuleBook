import Foundation
import Testing
@testable import RulebookKit

enum Fixtures {
    static func data(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "Missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try JSONDecoder().decode(type, from: try data(name))
    }
}

extension MailRule {
    /// A minimal valid rule, for tests that only care about one facet.
    static func stub(
        name: String = "Stub",
        order: Int? = 1,
        conditions: [RuleCondition] = [.subject(StringMatch("x"))],
        actions: [RuleAction] = [.markAsRead(true)]
    ) -> MailRule {
        MailRule(name: name, order: order, conditions: conditions, actions: actions)
    }
}

/// Round-trips a value through JSON, to prove the hand-written Codable
/// conformances agree with each other.
func jsonRoundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    try JSONDecoder().decode(T.self, from: try JSONEncoder().encode(value))
}
