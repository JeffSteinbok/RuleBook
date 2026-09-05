import Foundation
import Testing
@testable import RuleBookKit

@Suite("Validation")
struct ValidationTests {

    @Test("A well-formed set passes clean")
    func validSetHasNoIssues() throws {
        let rules = try Fixtures.decode([MailRule].self, from: "neutral-rules")
        let issues = RuleValidator.validate(set: rules)
        #expect(issues.isEmpty, "Unexpected issues: \(issues)")
    }

    @Test("Every seeded defect is reported")
    func catchesKnownDefects() throws {
        let rules = try Fixtures.decode([MailRule].self, from: "invalid-rules")
        let text = RuleValidator.validate(set: rules).map(\.description).joined(separator: "\n")

        #expect(RuleValidator.validate(set: rules).hasErrors)
        #expect(text.contains("at least one action"))
        #expect(text.contains("order 1 is used by more than one rule"))
        #expect(text.contains("minimum (500000B) greater than maximum (1000B)"))
        #expect(text.contains("forward has a recipient with no address"))
    }

    @Test("A rule with no conditions warns but does not fail")
    func unconditionalRuleWarns() {
        let issues = RuleValidator.validate(MailRule(name: "Catch-all", actions: [.markAsRead(true)]))
        #expect(!issues.hasErrors)
        #expect(issues.contains { $0.message.contains("every incoming message") })
    }

    @Test("Blank names and negative order are errors")
    func structuralErrors() {
        let issues = RuleValidator.validate(.stub(name: "   ", order: -1))
        #expect(issues.hasErrors)
        #expect(issues.contains { $0.message.contains("name must not be empty") })
        #expect(issues.contains { $0.message.contains("order must be zero or greater") })
    }

    @Test("Two actions that both move the message warn")
    func contradictoryDispositionsWarn() {
        let issues = RuleValidator.validate(
            .stub(actions: [.moveTo(.named("A")), .delete(permanent: false)])
        )
        #expect(!issues.hasErrors)
        #expect(issues.contains { $0.message.contains("each move the message") })
    }

    @Test("Empty match values and folderless destinations are errors")
    func emptyValuesAreErrors() {
        let issues = RuleValidator.validate(
            .stub(conditions: [.subject(StringMatch([]))], actions: [.moveTo(MailboxFolder())])
        )
        #expect(issues.hasErrors)
        #expect(issues.contains { $0.message.contains("no values to match") })
        #expect(issues.contains { $0.message.contains("neither a folder id nor a name") })
    }

    @Test("Structure and provider limits combine in one pass")
    func combinedValidation() {
        let issues = RuleValidator.validate(
            .stub(name: "", actions: [.archive]),
            for: GraphRuleMapper.capabilities
        )
        #expect(issues.contains { $0.message.contains("name must not be empty") })
        #expect(issues.contains { $0.message.contains("microsoft does not support") })
    }
}
