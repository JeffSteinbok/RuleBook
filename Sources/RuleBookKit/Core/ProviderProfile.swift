import Foundation

/// Renders neutral conditions and actions in one provider's own words.
///
/// The neutral model is what the app stores and reasons about; a vocabulary is
/// what it *says*. Outlook calls it a rule that moves mail to a folder and
/// assigns a category; Gmail calls it a filter that applies a label and skips
/// the Inbox. Same `MailRule`, different sentences.
public protocol ProviderVocabulary: Sendable {
    /// Field name only — for a form label or a table header.
    func name(for kind: ConditionKind) -> String
    func name(for kind: ActionKind) -> String

    /// A complete phrase, as the provider's own UI would word it.
    func phrase(for condition: RuleCondition) -> String
    func phrase(for action: RuleAction) -> String
}

/// Everything the app needs to present and constrain rules for one provider:
/// what it can do (``capabilities``) and what it calls things (``vocabulary``).
public struct ProviderProfile: Sendable {
    public let id: ProviderID
    /// The product name a person would recognise: "Outlook", "Gmail".
    public let displayName: String
    /// What this provider calls a rule — Outlook "rule", Gmail "filter".
    public let ruleNoun: String
    public let ruleNounPlural: String
    /// Where mail gets filed: Outlook "folder", Gmail "label".
    public let folderNoun: String
    /// What a tag is called: Outlook "category", Gmail "label".
    public let tagNoun: String
    public let capabilities: RuleCapabilities
    public let vocabulary: any ProviderVocabulary

    public init(
        id: ProviderID,
        displayName: String,
        ruleNoun: String,
        ruleNounPlural: String,
        folderNoun: String,
        tagNoun: String,
        capabilities: RuleCapabilities,
        vocabulary: any ProviderVocabulary
    ) {
        self.id = id
        self.displayName = displayName
        self.ruleNoun = ruleNoun
        self.ruleNounPlural = ruleNounPlural
        self.folderNoun = folderNoun
        self.tagNoun = tagNoun
        self.capabilities = capabilities
        self.vocabulary = vocabulary
    }

    public func supports(_ kind: ConditionKind) -> Bool { capabilities.conditions.contains(kind) }
    public func supports(_ kind: ActionKind) -> Bool { capabilities.actions.contains(kind) }

    /// Condition kinds this provider offers, for building a picker.
    public var availableConditions: [ConditionKind] {
        ConditionKind.allCases.filter(supports)
    }

    public var availableActions: [ActionKind] {
        ActionKind.allCases.filter(supports)
    }

    public func phrase(for condition: RuleCondition) -> String {
        vocabulary.phrase(for: condition)
    }

    public func phrase(for action: RuleAction) -> String {
        vocabulary.phrase(for: action)
    }

    /// A rule written out the way this provider would word it.
    public func describe(_ rule: MailRule) -> String {
        var lines = ["\(ruleNoun.capitalized): \(rule.name)"]

        if !rule.isEnabled { lines.append("  (turned off)") }

        if rule.conditions.isEmpty {
            lines.append("  Applies to: every message")
        } else {
            let joiner = rule.match == .all ? "all" : "any"
            lines.append("  Applies when \(joiner) of these are true:")
            lines.append(contentsOf: rule.conditions.map { "    - \(phrase(for: $0))" })
        }

        if !rule.exceptions.isEmpty {
            lines.append("  Except when:")
            lines.append(contentsOf: rule.exceptions.map { "    - \(phrase(for: $0))" })
        }

        lines.append("  Then:")
        lines.append(contentsOf: rule.actions.map { "    - \(phrase(for: $0))" })

        return lines.joined(separator: "\n")
    }
}

/// The providers the library knows about.
public enum ProviderCatalog {
    public static let outlook = ProviderProfile(
        id: .microsoft,
        displayName: "Outlook",
        ruleNoun: "rule",
        ruleNounPlural: "rules",
        folderNoun: "folder",
        tagNoun: "category",
        capabilities: GraphRuleMapper.capabilities,
        vocabulary: OutlookVocabulary()
    )

    public static let gmail = ProviderProfile(
        id: .google,
        displayName: "Gmail",
        ruleNoun: "filter",
        ruleNounPlural: "filters",
        folderNoun: "label",
        tagNoun: "label",
        capabilities: GmailRuleMapper.capabilities,
        vocabulary: GmailVocabulary()
    )

    /// The local stores: no provider limits, neutral wording.
    public static let local = ProviderProfile(
        id: .local,
        displayName: "Local",
        ruleNoun: "rule",
        ruleNounPlural: "rules",
        folderNoun: "folder",
        tagNoun: "label",
        capabilities: .unrestricted,
        vocabulary: NeutralVocabulary()
    )

    public static let all: [ProviderProfile] = [outlook, gmail, local]

    public static func profile(for id: ProviderID) -> ProviderProfile {
        switch id {
        case .microsoft: outlook
        case .google: gmail
        case .local: local
        }
    }

    /// Accepts the names people actually type.
    public static func profile(named name: String) -> ProviderProfile? {
        switch name.lowercased() {
        case "outlook", "microsoft", "m365", "office365", "graph", "exchange": outlook
        case "gmail", "google": gmail
        case "local", "offline", "none": local
        default: nil
        }
    }
}
