import Foundation
import Observation
import RulebookKit

/// Draft state for one rule, shared by the create flow and the editor.
///
/// Holds a `MailRule` under construction plus the provider profile that
/// constrains it. Every picker is filled from `profile.availableConditions` /
/// `availableActions` — never a hard-coded list, which is what lets the Gmail
/// store drop in later.
@MainActor
@Observable
final class RuleEditorModel {

    enum Step: Int, CaseIterable { case name = 1, conditions, actions

        var title: String {
            switch self {
            case .name: "Name the rule"
            case .conditions: "Set the conditions"
            case .actions: "Pick the actions"
            }
        }

        var nextLabel: String {
            switch self {
            case .name: "Conditions"
            case .conditions: "Actions"
            case .actions: "Save rule"
            }
        }
    }

    // MARK: - State

    var draft: MailRule
    var step: Step = .name
    private(set) var issues: [ValidationIssue] = []
    private(set) var isSaving = false
    var errorMessage: String?

    let profile: ProviderProfile
    let isEditing: Bool
    /// What the server holds, for the clear-collection problem below.
    private let original: MailRule?
    private let store: any RuleStore
    private let folders: any FolderDirectory

    private(set) var availableFolders: [MailboxFolder] = []

    /// - Parameter nextOrder: where a newly created rule lands in evaluation
    ///   order. It must be a real position: Outlook numbers rules from 1 and
    ///   rejects a sequence of 0 outright, and a new rule belongs after the
    ///   ones already there, not in front of them.
    init(
        editing rule: MailRule? = nil,
        store: any RuleStore,
        folders: any FolderDirectory,
        profile: ProviderProfile = ProviderCatalog.outlook,
        nextOrder: Int = 1
    ) {
        self.original = rule
        self.isEditing = rule != nil
        self.draft = rule ?? MailRule(
            name: "",
            order: nextOrder,
            isEnabled: true,
            match: .all,
            conditions: [.from(.init("", mode: .contains))],
            actions: []
        )
        self.store = store
        self.folders = folders
        self.profile = profile
        if rule != nil { self.step = .conditions }
    }

    func loadFolders() async {
        availableFolders = (try? await folders.folders()) ?? []
    }

    // MARK: - Pickers, from the provider's capabilities

    var conditionKinds: [ConditionKind] { profile.availableConditions }
    var actionKinds: [ActionKind] { profile.availableActions }

    /// Only the match modes this provider can honour. Outlook has all four;
    /// a provider with only `.contains` shows one.
    var matchModes: [MatchMode] {
        MatchMode.allCases.filter { profile.capabilities.matchModes.contains($0) }
    }

    var supportsMatchAny: Bool { profile.capabilities.matchStrategies.contains(.any) }
    var supportsExceptions: Bool { profile.capabilities.supportsExceptions }

    func label(for kind: ConditionKind) -> String { profile.vocabulary.name(for: kind) }
    func label(for kind: ActionKind) -> String { profile.vocabulary.name(for: kind) }

    // MARK: - Conditions

    func addCondition() {
        draft.conditions.append(.subject(.init("", mode: .contains)))
    }

    func removeCondition(at index: Int) {
        guard draft.conditions.indices.contains(index) else { return }
        draft.conditions.remove(at: index)
    }

    func addException() {
        draft.exceptions.append(.from(.init("", mode: .contains)))
    }

    func removeException(at index: Int) {
        guard draft.exceptions.indices.contains(index) else { return }
        draft.exceptions.remove(at: index)
    }

    /// The joiner shown before each condition — reads as a sentence down the list.
    func joiner(at index: Int, isException: Bool) -> String {
        if isException { return index == 0 ? "SKIP IF" : "OR IF" }
        if index == 0 { return "IF" }
        return draft.match == .all ? "AND ALSO" : "OR"
    }

    // MARK: - Actions

    func isPicked(_ kind: ActionKind) -> Bool {
        draft.actions.contains { $0.kind == kind }
    }

    func toggle(_ kind: ActionKind) {
        if let index = draft.actions.firstIndex(where: { $0.kind == kind }) {
            draft.actions.remove(at: index)
        } else {
            draft.actions.append(Self.defaultAction(for: kind, folder: availableFolders.first))
        }
    }

    /// A newly-picked action needs a value; these are the neutral defaults.
    private static func defaultAction(for kind: ActionKind, folder: MailboxFolder?) -> RuleAction {
        switch kind {
        case .moveTo: .moveTo(folder ?? .named(""))
        case .copyTo: .copyTo(folder ?? .named(""))
        case .addLabel: .addLabel(.named(""))
        case .removeLabel: .removeLabel(.named(""))
        case .markAsRead: .markAsRead(true)
        case .markAsStarred: .markAsStarred(true)
        case .markImportance: .markImportance(.high)
        case .forward: .forward([])
        case .forwardAsAttachment: .forwardAsAttachment([])
        case .redirect: .redirect([])
        case .delete: .delete(permanent: false)
        case .archive: .archive
        case .markAsSpam: .markAsSpam(true)
        case .stopProcessing: .stopProcessing
        }
    }

    // MARK: - Plain words

    /// The rule as a sentence, in the provider's own vocabulary. Shown on the
    /// last step so someone can check their work without reading the form back.
    var plainWords: String {
        let conditions = draft.conditions.filter(\.hasValue)
        let head: String
        if conditions.isEmpty {
            head = "Every message"
        } else {
            let joiner = draft.match == .all ? " and " : " or "
            let phrases = conditions.map { profile.phrase(for: $0) }.joined(separator: joiner)
            head = "When a message matches \(draft.match == .all ? "all of" : "any of") — \(phrases)"
        }

        let exceptions = draft.exceptions.filter(\.hasValue)
        let unless = exceptions.isEmpty
            ? ""
            : " — unless \(exceptions.map { profile.phrase(for: $0) }.joined(separator: " or "))"

        let actions = draft.actions.isEmpty
            ? "nothing yet"
            : draft.actions.map { profile.phrase(for: $0) }.joined(separator: ", ")

        return "\(head)\(unless) — then \(actions)."
    }

    // MARK: - Validation and save

    /// Structural checks plus this provider's limits, run locally before any
    /// network call — so "Outlook can't do that" is explainable, not a 400.
    func revalidate() {
        var found = RuleValidator.validate(cleaned, for: profile.capabilities)

        // The library's `updateRule` merges: empty collections leave the stored
        // values alone, so "remove every condition" cannot currently be
        // expressed. Report it rather than silently keeping the old ones.
        if let original, isEditing {
            if cleaned.conditions.isEmpty && !original.conditions.isEmpty {
                found.append(.init(
                    severity: .error, rule: draft.name,
                    message: "Removing every condition can't be saved yet.",
                    remedy: "Keep at least one condition, or delete the rule instead."
                ))
            }
            if cleaned.actions.isEmpty && !original.actions.isEmpty {
                found.append(.init(
                    severity: .error, rule: draft.name,
                    message: "Removing every action can't be saved yet.",
                    remedy: "Keep at least one action, or delete the rule instead."
                ))
            }
        }

        issues = found
    }

    var blockingIssues: [ValidationIssue] { issues.filter { $0.severity == .error } }
    var advisoryIssues: [ValidationIssue] { issues.filter { $0.severity == .warning } }
    var canSave: Bool { blockingIssues.isEmpty }

    /// Half-typed rows are dropped rather than saved empty.
    private var cleaned: MailRule {
        var rule = draft
        rule.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.conditions = draft.conditions.filter(\.hasValue)
        rule.exceptions = draft.exceptions.filter(\.hasValue)
        return rule
    }

    func advance() -> Bool {
        guard let next = Step(rawValue: step.rawValue + 1) else { return true }
        step = next
        if step == .actions { revalidate() }
        return false
    }

    func back() -> Bool {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return true }
        step = previous
        return false
    }

    @discardableResult
    func save() async -> MailRule? {
        revalidate()
        guard canSave else { return nil }

        isSaving = true
        defer { isSaving = false }

        do {
            if let id = draft.id {
                return try await store.updateRule(id: id, with: cleaned)
            }
            return try await store.createRule(cleaned)
        } catch let error as MappingError {
            // The mapper is the authority — it refuses cases capability checks
            // can't see, and names each one.
            if case .unsupported(let mapperIssues) = error {
                issues = mapperIssues
            } else {
                errorMessage = error.localizedDescription
            }
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

// MARK: - Condition helpers

extension RuleCondition {
    /// Whether this condition carries enough to be worth saving.
    var hasValue: Bool {
        switch self {
        case .from(let m), .recipient(let m), .subject(let m),
             .body(let m), .subjectOrBody(let m), .header(_, let m):
            return m.anyOf.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        case .hasLabels(let values):
            return !values.isEmpty
        case .rawQuery(_, let query):
            return !query.isEmpty
        case .size(let size):
            return size.minimumBytes != nil || size.maximumBytes != nil
        default:
            return true
        }
    }

    /// The text match inside, for the kinds that have one.
    var stringMatch: StringMatch? {
        switch self {
        case .from(let m), .recipient(let m), .subject(let m),
             .body(let m), .subjectOrBody(let m), .header(_, let m):
            return m
        default:
            return nil
        }
    }

    /// Rebuilt with a new match, preserving kind. Used by the editor's pickers.
    func replacing(match: StringMatch) -> RuleCondition {
        switch self {
        case .from: .from(match)
        case .recipient: .recipient(match)
        case .subject: .subject(match)
        case .body: .body(match)
        case .subjectOrBody: .subjectOrBody(match)
        case .header(let name, _): .header(name: name, match: match)
        default: self
        }
    }

    /// A blank condition of the given kind, for when the field picker changes.
    static func blank(_ kind: ConditionKind) -> RuleCondition {
        switch kind {
        case .from: .from(.init("", mode: .contains))
        case .recipient: .recipient(.init("", mode: .contains))
        case .subject: .subject(.init("", mode: .contains))
        case .body: .body(.init("", mode: .contains))
        case .subjectOrBody: .subjectOrBody(.init("", mode: .contains))
        case .header: .header(name: "", match: .init("", mode: .contains))
        case .hasAttachment: .hasAttachment(true)
        case .size: .size(.init(minimumBytes: nil, maximumBytes: 5_242_880))
        case .importance: .importance(.high)
        case .sensitivity: .sensitivity(.normal)
        case .hasLabels: .hasLabels([])
        case .addressed: .addressed(.toMe)
        case .messageKind: .messageKind(.meetingRequest, true)
        case .actionFlag: .actionFlag(.any)
        case .rawQuery: .rawQuery(provider: .microsoft, query: "")
        }
    }
}
