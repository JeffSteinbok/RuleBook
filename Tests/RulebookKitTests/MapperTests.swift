import Foundation
import Testing
@testable import RulebookKit

@Suite("Outlook / Graph mapper")
struct GraphMapperTests {
    let mapper = GraphRuleMapper()

    @Test("A neutral rule becomes the Graph shape")
    func encodesToGraph() throws {
        let rules = try Fixtures.decode([MailRule].self, from: "neutral-rules")
        let native = try mapper.encode(rules[0])

        #expect(native.displayName == "Newsletters to Reading")
        #expect(native.sequence == 1)
        #expect(native.conditions?.senderContains == ["newsletter", "digest"])
        #expect(native.conditions?.subjectContains == ["weekly"])
        // `.equals` on an address maps to fromAddresses, not senderContains.
        #expect(native.exceptions?.fromAddresses?.first?.emailAddress.address == "owner@example.com")
        #expect(native.actions?.moveToFolder == "Reading")
        #expect(native.actions?.markAsRead == true)
        #expect(native.actions?.stopProcessingRules == true)
    }

    @Test("addLabel becomes an Outlook category")
    func labelsBecomeCategories() throws {
        let rules = try Fixtures.decode([MailRule].self, from: "neutral-rules")
        let native = try mapper.encode(rules[1])
        #expect(native.actions?.assignCategories == ["Bulky"])
        #expect(native.actions?.markImportance == .low)
    }

    @Test("Sizes convert from bytes to Graph's kilobytes, rounding outward")
    func sizeUnitsConvert() throws {
        let rule = MailRule.stub(conditions: [.size(SizeConstraint(minimumBytes: 5000, maximumBytes: 5000))])
        let range = try #require(try mapper.encode(rule).conditions?.withinSizeRange)

        // 5000 B is 4.88 KB: the floor for the minimum, the ceiling for the
        // maximum, so the converted range never excludes a matching message.
        #expect(range.minimumSize == 4)
        #expect(range.maximumSize == 5)
    }

    @Test("Graph rules decode back into the neutral model")
    func decodesFromGraph() throws {
        let native = try Fixtures.decode(MessageRule.self, from: "newsletter-rule")
        let rule = try mapper.decode(native)

        #expect(rule.name == "Newsletters to Reading")
        #expect(rule.order == 1)
        #expect(rule.conditions.contains(.from(StringMatch(["newsletter", "digest"]))))
        #expect(rule.conditions.contains(.importance(.low)))
        #expect(rule.actions.contains(.markAsRead(true)))
        #expect(rule.actions.contains(.addLabel(.named("Reading"))))
        #expect(rule.status.isClean)
    }

    @Test("Neutral -> Graph -> neutral preserves what Outlook can hold")
    func roundTrips() throws {
        let original = MailRule(
            name: "Round trip",
            order: 4,
            conditions: [
                .from(StringMatch(["a@b.com"], mode: .equals)),
                .subject(StringMatch(["hello", "there"])),
                .hasAttachment(true),
                .importance(.high),
                .addressed(.toOrCcMe),
                .messageKind(.meetingRequest, true),
            ],
            actions: [.moveTo(.id("folder-1")), .markAsRead(true), .stopProcessing]
        )

        let back = try mapper.decode(try mapper.encode(original))

        #expect(back.name == original.name)
        #expect(back.order == original.order)
        #expect(Set(back.conditions) == Set(original.conditions))
        #expect(Set(back.actions) == Set(original.actions))
    }

    @Test("What Outlook cannot do is reported, not dropped")
    func reportsUnsupported() throws {
        let rule = MailRule.stub(actions: [.archive, .markAsStarred(true), .markAsSpam(true)])

        do {
            _ = try mapper.encode(rule)
            Issue.record("Expected the mapper to refuse.")
        } catch let MappingError.unsupported(issues) {
            let text = issues.map(\.message).joined(separator: "\n")
            #expect(issues.count == 3)
            #expect(text.contains("archiving"))
            #expect(text.contains("starring"))
            #expect(text.contains("junk"))
        }
    }

    @Test("An exact-match subject is refused; Graph only does contains")
    func exactSubjectIsRefused() throws {
        let rule = MailRule.stub(conditions: [.subject(StringMatch("exact", mode: .equals))])

        do {
            _ = try mapper.encode(rule)
            Issue.record("Expected the mapper to refuse.")
        } catch let MappingError.unsupported(issues) {
            #expect(issues.first?.message.contains("equals match on the subject") == true)
        }
    }
}

@Suite("Gmail mapper")
struct GmailMapperTests {
    let mapper = GmailRuleMapper()

    @Test("A move becomes apply-label plus skip-the-Inbox")
    func moveIsLabelPlusArchive() throws {
        let rule = MailRule.stub(actions: [.moveTo(.id("Label_42"))])
        let action = try #require(try mapper.encode(rule).action)

        #expect(action.addLabelIds == ["Label_42"])
        #expect(action.removeLabelIds == [GmailSystemLabel.inbox])
    }

    @Test("Effects Gmail models as system labels", arguments: [
        (RuleAction.archive, [String](), ["INBOX"]),
        (.markAsRead(true), [], ["UNREAD"]),
        (.markAsStarred(true), ["STARRED"], []),
        (.delete(permanent: false), ["TRASH"], []),
        (.markAsSpam(false), [], ["SPAM"]),
        (.markImportance(.high), ["IMPORTANT"], []),
    ])
    func systemLabelActions(action: RuleAction, added: [String], removed: [String]) throws {
        let encoded = try #require(try mapper.encode(MailRule.stub(actions: [action])).action)
        #expect(encoded.addLabelIds ?? [] == added)
        #expect(encoded.removeLabelIds ?? [] == removed)
    }

    @Test("Conditions with no typed field are rendered into the query")
    func conditionsBecomeQuery() throws {
        let rule = MailRule.stub(conditions: [
            .from(StringMatch(["a@b.com", "c@d.com"])),
            .hasLabels(["Reading"]),
            .importance(.high),
            .addressed(.toMe),
        ])
        let criteria = try #require(try mapper.encode(rule).criteria)

        #expect(criteria.from == "(a@b.com OR c@d.com)")
        #expect(criteria.query == "label:Reading is:important to:me")
    }

    @Test("Exceptions become Gmail's negatedQuery")
    func exceptionsBecomeNegatedQuery() throws {
        var rule = MailRule.stub()
        rule.exceptions = [.from(StringMatch("boss@contoso.com"))]

        let criteria = try #require(try mapper.encode(rule).criteria)
        #expect(criteria.negatedQuery == "from:boss@contoso.com")
    }

    @Test("A one-sided size bound uses the typed field; a range goes to the query")
    func sizeBounds() throws {
        let lower = try mapper.encode(MailRule.stub(conditions: [.size(SizeConstraint(minimumBytes: 5000))]))
        #expect(lower.criteria?.size == 5000)
        #expect(lower.criteria?.sizeComparison == .larger)

        let range = try mapper.encode(
            MailRule.stub(conditions: [.size(SizeConstraint(minimumBytes: 5000, maximumBytes: 9000))])
        )
        #expect(range.criteria?.size == nil)
        #expect(range.criteria?.query == "larger:5000 smaller:9000")
    }

    @Test("What Gmail cannot do is reported")
    func reportsUnsupported() throws {
        let rule = MailRule.stub(
            conditions: [.sensitivity(.confidential)],
            actions: [.stopProcessing, .redirect([MailAddress("a@b.com")]), .delete(permanent: true)]
        )

        do {
            _ = try mapper.encode(rule)
            Issue.record("Expected the mapper to refuse.")
        } catch let MappingError.unsupported(issues) {
            let text = issues.map(\.message).joined(separator: "\n")
            #expect(text.contains("sensitivity"))
            #expect(text.contains("every matching Gmail filter runs"))
            #expect(text.contains("redirecting"))
            #expect(text.contains("Trash"))
        }
    }

    @Test("Forwarding takes exactly one address")
    func singleForwardAddress() throws {
        let one = try mapper.encode(MailRule.stub(actions: [.forward([MailAddress("a@b.com")])]))
        #expect(one.action?.forward == "a@b.com")

        #expect(throws: MappingError.self) {
            try mapper.encode(MailRule.stub(actions: [
                .forward([MailAddress("a@b.com"), MailAddress("c@d.com")])
            ]))
        }
    }

    @Test("An exact address match uses Gmail's from:/to: field")
    func addressEqualityIsSupported() throws {
        // Outlook stores exact addresses as fromAddresses/sentToAddresses,
        // which decode to `.equals`. Gmail matches an address directly, so
        // refusing `.equals` outright would block most real Outlook rules
        // from ever porting.
        let rule = MailRule.stub(conditions: [
            .from(StringMatch(["a@b.com"], mode: .equals)),
            .recipient(StringMatch(["c@d.com"], mode: .equals)),
        ])

        #expect(!RuleCompatibility.check(rule, against: GmailRuleMapper.capabilities).hasErrors)

        let criteria = try #require(try mapper.encode(rule).criteria)
        #expect(criteria.from == "a@b.com")
        #expect(criteria.to == "c@d.com")
    }

    @Test("Exact matching is still refused where Gmail has no form for it")
    func exactSubjectIsRefused() throws {
        let rule = MailRule.stub(conditions: [.subject(StringMatch("exact", mode: .equals))])
        do {
            _ = try mapper.encode(rule)
            Issue.record("Expected the mapper to refuse.")
        } catch let MappingError.unsupported(issues) {
            #expect(issues.first?.message.contains("no exact-match form") == true)
        }
    }

    @Test("A Gmail filter decodes into the neutral model")
    func decodesFilter() throws {
        let filter = try Fixtures.decode(GmailFilter.self, from: "gmail-filter")
        let rule = try mapper.decode(filter)

        #expect(rule.id == "ANe1BmiP0")
        // Filters have no name; one is inferred from what it does.
        #expect(rule.name == "Filter → Label_42")
        #expect(rule.order == nil)
        #expect(rule.conditions.contains(.from(StringMatch(["newsletter", "digest"]))))
        #expect(rule.conditions.contains(.hasAttachment(true)))

        // add Label_42 alongside removing INBOX reads back as a move.
        #expect(rule.actions.contains(.moveTo(.id("Label_42"))))
        #expect(rule.actions.contains(.markAsStarred(true)))
        #expect(rule.actions.contains(.markAsRead(true)))
        #expect(rule.exceptions.contains(.rawQuery(provider: .google, query: "from:owner@example.com")))
    }
}

@Suite("Cross-provider portability")
struct PortabilityTests {

    @Test("The same rule maps to both providers")
    func portableRuleWorksEverywhere() throws {
        let rule = MailRule(
            name: "Newsletters",
            order: 1,
            conditions: [.from(StringMatch(["newsletter"])), .hasAttachment(false)],
            actions: [.moveTo(.named("Reading")), .markAsRead(true)]
        )

        #expect(RuleCompatibility.check(rule, against: GraphRuleMapper.capabilities).isEmpty)
        // Gmail warns that it will ignore `order`, but nothing here blocks it.
        #expect(!RuleCompatibility.check(rule, against: GmailRuleMapper.capabilities).hasErrors)
        #expect(throws: Never.self) { try GraphRuleMapper().encode(rule) }
        #expect(throws: Never.self) { try GmailRuleMapper().encode(rule) }
    }

    @Test("Capability checks name the provider that cannot do it")
    func capabilityCheckExplains() {
        let outlookOnly = MailRule.stub(actions: [.redirect([MailAddress("a@b.com")])])
        let gmailOnly = MailRule.stub(actions: [.markAsStarred(true)])

        #expect(RuleCompatibility.check(outlookOnly, against: GraphRuleMapper.capabilities).isEmpty)
        let forGmail = RuleCompatibility.check(outlookOnly, against: GmailRuleMapper.capabilities)
        #expect(forGmail.hasErrors)
        #expect(forGmail.first?.message.contains("google does not support") == true)

        #expect(!RuleCompatibility.check(gmailOnly, against: GmailRuleMapper.capabilities).hasErrors)
        #expect(RuleCompatibility.check(gmailOnly, against: GraphRuleMapper.capabilities).hasErrors)
    }

    @Test("Gmail warns rather than fails on ordering and disabling")
    func gmailDegradesGracefully() {
        var rule = MailRule.stub(order: 3)
        rule.isEnabled = false

        let issues = RuleCompatibility.check(rule, against: GmailRuleMapper.capabilities)
        #expect(!issues.hasErrors)
        #expect(issues.contains { $0.message.contains("no rule ordering") })
        #expect(issues.contains { $0.message.contains("cannot store a disabled rule") })
    }
}

@Suite("Lossy mappings are refused, not silently dropped")
struct LossyMappingTests {

    @Test("stopProcessing blocks on Gmail rather than degrading")
    func stopProcessingBlocks() throws {
        // A rule that stops processing is usually shielding the message from a
        // later, destructive rule. Gmail runs every matching filter, so
        // dropping the action would change what the rule set does — quietly,
        // and in the direction of losing mail.
        let rule = MailRule.stub(actions: [.moveTo(.named("Reading")), .stopProcessing])

        #expect(RuleCompatibility.check(rule, against: GmailRuleMapper.capabilities).hasErrors)

        do {
            _ = try GmailRuleMapper().encode(rule)
            Issue.record("Expected Gmail to refuse a rule that stops processing.")
        } catch let MappingError.unsupported(issues) {
            let issue = try #require(issues.first { $0.message.contains("stopping rule processing") })
            #expect(issue.severity == .error)
            // The refusal names the portable alternative.
            #expect(issue.remedy?.contains("exception") == true)
        }
    }

    @Test("The same rule without stopProcessing maps cleanly")
    func portableEquivalentIsAccepted() throws {
        let rule = MailRule.stub(actions: [.moveTo(.named("Reading"))])
        #expect(throws: Never.self) { try GmailRuleMapper().encode(rule) }
    }

    @Test("Ordering and disabling degrade with a warning; they cannot lose mail")
    func harmlessDifferencesOnlyWarn() {
        var rule = MailRule.stub(order: 3)
        rule.isEnabled = false

        let issues = RuleCompatibility.check(rule, against: GmailRuleMapper.capabilities)
        #expect(!issues.hasErrors)
        #expect(issues.allSatisfy { $0.severity == .warning })
    }
}

@Suite("Outlook evaluation order")
struct GraphOrderTests {
    let mapper = GraphRuleMapper()

    @Test("A rule with no stated order gets sequence 1, never 0")
    func defaultsToOne() throws {
        // Graph rejects a sequence of 0 at request time:
        //   MessageRuleValidationError ... Field: 'Sequence', Value: '0'
        #expect(try mapper.encode(MailRule.stub(order: nil)).sequence == 1)
    }

    @Test("An explicit order of 0 is refused, with the reason")
    func refusesZero() throws {
        do {
            _ = try mapper.encode(MailRule.stub(order: 0))
            Issue.record("Expected the mapper to refuse sequence 0.")
        } catch let MappingError.unsupported(issues) {
            #expect(issues.contains { $0.message.contains("numbers rules from 1") })
        }
    }

    @Test("A real order passes through untouched")
    func keepsRealOrder() throws {
        #expect(try mapper.encode(MailRule.stub(order: 7)).sequence == 7)
    }
}
