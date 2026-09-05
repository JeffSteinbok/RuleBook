import Foundation

/// Translates between ``MailRule`` and Gmail's `Filter`.
///
/// Gmail's shape is very different from Outlook's: four typed criteria fields
/// plus a free-text `query`, and actions that are almost all label changes.
/// This mapper leans on both — conditions Gmail has no field for are rendered
/// into search syntax, and effects like archive or star become system labels.
public struct GmailRuleMapper: RuleMapper {
    public typealias Native = GmailFilter

    public init() {}

    public static let capabilities = RuleCapabilities(
        provider: .google,
        conditions: [
            .from, .recipient, .subject, .body, .subjectOrBody,
            .hasAttachment, .size, .hasLabels, .importance, .addressed,
            .messageKind, .rawQuery,
        ],
        actions: [
            .moveTo, .addLabel, .removeLabel, .markAsRead, .markAsStarred,
            .markImportance, .forward, .delete, .archive, .markAsSpam,
        ],
        // `.equals` holds for addresses — Gmail's from:/to: match an address
        // directly. `encode` rejects it on subject and body, which have no
        // exact-match form in Gmail search.
        matchModes: [.contains, .equals],
        matchStrategies: [.all],
        // Gmail has no exception list, but `negatedQuery` does the same job.
        supportsExceptions: true,
        supportsOrdering: false,
        supportsDisabling: false,
        supportsNamedHeaders: false
    )

    // MARK: - Neutral -> Gmail

    public func encode(_ rule: MailRule) throws -> GmailFilter {
        var issues: [ValidationIssue] = []

        func reject(_ what: String, remedy: String? = nil) {
            issues.append(ValidationIssue(
                severity: .error, rule: rule.name,
                message: "Gmail cannot express \(what).",
                remedy: remedy
            ))
        }

        if rule.match == .any {
            reject("matching any of several conditions; a Gmail filter ANDs its criteria")
        }
        if !rule.isEnabled {
            issues.append(ValidationIssue(
                severity: .warning, rule: rule.name,
                message: "Gmail filters cannot be disabled; this one would be active."
            ))
        }

        var criteria = GmailFilterCriteria()
        var queryTerms: [String] = []

        for condition in rule.conditions {
            switch condition {
            case .from(let match):
                // An address is an address: contains and equals both land on
                // Gmail's `from:` field.
                guard match.mode == .contains || match.mode == .equals else {
                    reject("a \(match.mode.rawValue) match on the sender")
                    continue
                }
                criteria.from = Self.orJoined(match.anyOf)
            case .recipient(let match):
                guard match.mode == .contains || match.mode == .equals else {
                    reject("a \(match.mode.rawValue) match on recipients")
                    continue
                }
                criteria.to = Self.orJoined(match.anyOf)
            case .subject(let match):
                guard match.mode == .contains else {
                    reject("a \(match.mode.rawValue) match on the subject; Gmail search has no exact-match form")
                    continue
                }
                criteria.subject = Self.orJoined(match.anyOf)
            case .hasAttachment(let value):
                criteria.hasAttachment = value

            case .size(let size):
                // Gmail takes a single bound. Two-sided ranges have to go
                // through the query, which does support both.
                switch (size.minimumBytes, size.maximumBytes) {
                case (let low?, nil):
                    criteria.size = low
                    criteria.sizeComparison = .larger
                case (nil, let high?):
                    criteria.size = high
                    criteria.sizeComparison = .smaller
                case (let low?, let high?):
                    queryTerms.append("larger:\(low) smaller:\(high)")
                case (nil, nil):
                    reject("a size test with no bounds")
                }

            case .messageKind(let kind, let expected):
                guard kind == .chat else {
                    reject("a test for \(kind.rawValue) messages")
                    continue
                }
                criteria.excludeChats = !expected

            case .rawQuery(let provider, let query):
                guard provider == .google else {
                    reject("a raw \(provider.rawValue) query")
                    continue
                }
                queryTerms.append(query)

            // Everything below has no typed field, but Gmail search says it.
            case .body, .subjectOrBody, .hasLabels, .importance, .addressed:
                if let term = Self.queryTerm(for: condition) {
                    queryTerms.append(term)
                } else {
                    reject("the condition \"\(condition.description)\"")
                }

            case .header(_, _):
                reject("searching message headers")
            case .sensitivity:
                reject("a sensitivity test")
            case .actionFlag:
                reject("an Outlook action flag")
            }
        }

        if !queryTerms.isEmpty { criteria.query = queryTerms.joined(separator: " ") }

        // Exceptions become negatedQuery — Gmail's "doesn't have" box.
        let negated = rule.exceptions.compactMap { condition -> String? in
            guard let term = Self.queryTerm(for: condition) else {
                reject("the exception \"\(condition.description)\"")
                return nil
            }
            return term
        }
        if !negated.isEmpty { criteria.negatedQuery = negated.joined(separator: " ") }

        let action = encodeActions(rule.actions, reject: reject)

        guard !issues.hasErrors else { throw MappingError.unsupported(issues) }
        return GmailFilter(id: rule.id, criteria: criteria, action: action)
    }

    /// The portable way to say what `stopProcessing` says.
    static let stopProcessingRemedy =
        "Add an exception to the later rules instead — Gmail supports those as negatedQuery, "
        + "and the result means the same thing on both providers."

    private func encodeActions(
        _ actions: [RuleAction], reject: (String, String?) -> Void
    ) -> GmailFilterAction {
        var add: [String] = []
        var remove: [String] = []
        var forward: String?

        for action in actions {
            switch action {
            case .addLabel(let folder):
                add.append(folder.id ?? folder.name ?? "")
            case .removeLabel(let folder):
                remove.append(folder.id ?? folder.name ?? "")
            case .moveTo(let folder):
                // "Apply the label and skip the Inbox" — Gmail's move.
                add.append(folder.id ?? folder.name ?? "")
                remove.append(GmailSystemLabel.inbox)
            case .archive:
                remove.append(GmailSystemLabel.inbox)
            case .markAsRead(let value):
                value ? remove.append(GmailSystemLabel.unread) : add.append(GmailSystemLabel.unread)
            case .markAsStarred(let value):
                value ? add.append(GmailSystemLabel.starred) : remove.append(GmailSystemLabel.starred)
            case .markAsSpam(let value):
                value ? add.append(GmailSystemLabel.spam) : remove.append(GmailSystemLabel.spam)
            case .markImportance(let value):
                switch value {
                case .high: add.append(GmailSystemLabel.important)
                case .low: remove.append(GmailSystemLabel.important)
                case .normal: reject("setting importance to normal; Gmail only marks important or not", nil)
                }
            case .delete(let permanent):
                if permanent {
                    reject("permanent deletion from a filter; Gmail can only move to Trash", nil)
                } else {
                    add.append(GmailSystemLabel.trash)
                }
            case .forward(let to):
                guard to.count == 1 else {
                    reject("forwarding to \(to.count) addresses; a filter takes one", nil)
                    continue
                }
                forward = to[0].address
            case .copyTo:
                reject("copying a message; Gmail labels the one copy it keeps", nil)
            case .forwardAsAttachment:
                reject("forwarding as an attachment", nil)
            case .redirect:
                reject("redirecting", nil)
            case .stopProcessing:
                // Blocking rather than dropping is deliberate: a rule that
                // stops processing is usually shielding the message from a
                // later, destructive rule. Silently letting that later rule
                // run is a data-loss bug nobody notices on the day it ships.
                reject(
                    "stopping rule processing; every matching Gmail filter runs",
                    Self.stopProcessingRemedy
                )
            }
        }

        return GmailFilterAction(
            addLabelIds: add.isEmpty ? nil : add,
            removeLabelIds: remove.isEmpty ? nil : remove,
            forward: forward
        )
    }

    // MARK: - Gmail -> Neutral

    public func decode(_ native: GmailFilter) throws -> MailRule {
        var conditions: [RuleCondition] = []

        if let c = native.criteria {
            if let v = c.from { conditions.append(.from(StringMatch(Self.orSplit(v)))) }
            if let v = c.to { conditions.append(.recipient(StringMatch(Self.orSplit(v)))) }
            if let v = c.subject { conditions.append(.subject(StringMatch(Self.orSplit(v)))) }
            if let v = c.hasAttachment { conditions.append(.hasAttachment(v)) }
            if let v = c.excludeChats { conditions.append(.messageKind(.chat, !v)) }
            if let size = c.size {
                switch c.sizeComparison {
                case .larger: conditions.append(.size(SizeConstraint(minimumBytes: size)))
                case .smaller: conditions.append(.size(SizeConstraint(maximumBytes: size)))
                default: break
                }
            }
            // The query is not decomposed back into typed conditions — round
            // -tripping Gmail search syntax is lossy, so it is preserved whole.
            if let v = c.query { conditions.append(.rawQuery(provider: .google, query: v)) }
        }

        var exceptions: [RuleCondition] = []
        if let v = native.criteria?.negatedQuery {
            exceptions.append(.rawQuery(provider: .google, query: v))
        }

        return MailRule(
            id: native.id,
            name: Self.inferredName(for: native),
            order: nil,
            isEnabled: true,
            match: .all,
            conditions: conditions,
            exceptions: exceptions,
            actions: decodeActions(native.action)
        )
    }

    private func decodeActions(_ action: GmailFilterAction?) -> [RuleAction] {
        guard let action else { return [] }
        var decoded: [RuleAction] = []

        let added = action.addLabelIds ?? []
        let removed = action.removeLabelIds ?? []

        // A user label added alongside removing INBOX is a move, not two actions.
        let userAdded = added.filter { !GmailSystemLabel.all.contains($0) }
        let archives = removed.contains(GmailSystemLabel.inbox)

        if archives, let destination = userAdded.first {
            decoded.append(.moveTo(.id(destination)))
            decoded.append(contentsOf: userAdded.dropFirst().map { .addLabel(.id($0)) })
        } else {
            decoded.append(contentsOf: userAdded.map { .addLabel(.id($0)) })
            if archives { decoded.append(.archive) }
        }

        if added.contains(GmailSystemLabel.starred) { decoded.append(.markAsStarred(true)) }
        if removed.contains(GmailSystemLabel.starred) { decoded.append(.markAsStarred(false)) }
        if removed.contains(GmailSystemLabel.unread) { decoded.append(.markAsRead(true)) }
        if added.contains(GmailSystemLabel.unread) { decoded.append(.markAsRead(false)) }
        if added.contains(GmailSystemLabel.important) { decoded.append(.markImportance(.high)) }
        if removed.contains(GmailSystemLabel.important) { decoded.append(.markImportance(.low)) }
        if added.contains(GmailSystemLabel.trash) { decoded.append(.delete(permanent: false)) }
        if added.contains(GmailSystemLabel.spam) { decoded.append(.markAsSpam(true)) }
        if removed.contains(GmailSystemLabel.spam) { decoded.append(.markAsSpam(false)) }

        decoded.append(contentsOf: removed
            .filter { !GmailSystemLabel.all.contains($0) }
            .map { .removeLabel(.id($0)) })

        if let forward = action.forward { decoded.append(.forward([MailAddress(forward)])) }

        return decoded
    }

    // MARK: - Gmail search syntax

    /// Renders a condition as a Gmail search term, or nil when it cannot be.
    static func queryTerm(for condition: RuleCondition) -> String? {
        switch condition {
        case .from(let m): "from:\(orJoined(m.anyOf) ?? "")"
        case .recipient(let m): "to:\(orJoined(m.anyOf) ?? "")"
        case .subject(let m): "subject:\(orJoined(m.anyOf) ?? "")"
        case .body(let m), .subjectOrBody(let m): orJoined(m.anyOf)
        case .hasAttachment(let value): value ? "has:attachment" : "-has:attachment"
        case .hasLabels(let values): values.map { "label:\(quoted($0))" }.joined(separator: " ")
        case .importance(let value):
            switch value {
            case .high: "is:important"
            case .low: "-is:important"
            case .normal: nil
            }
        case .addressed(let scope):
            switch scope {
            case .toMe: "to:me"
            case .ccMe: "cc:me"
            case .toOrCcMe: "(to:me OR cc:me)"
            case .onlyToMe, .notToMe: nil
            }
        case .size(let size):
            [size.minimumBytes.map { "larger:\($0)" }, size.maximumBytes.map { "smaller:\($0)" }]
                .compactMap { $0 }.joined(separator: " ")
        case .rawQuery(let provider, let query): provider == .google ? query : nil
        case .header, .sensitivity, .actionFlag, .messageKind: nil
        }
    }

    /// Gmail's typed criteria fields take one string; several alternatives are
    /// written `(a OR b)`.
    static func orJoined(_ values: [String]) -> String? {
        guard !values.isEmpty else { return nil }
        if values.count == 1 { return values[0] }
        return "(" + values.map(quoted).joined(separator: " OR ") + ")"
    }

    static func orSplit(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        guard trimmed.contains(" OR ") else { return [value] }
        return trimmed.components(separatedBy: " OR ").map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        }
    }

    static func quoted(_ value: String) -> String {
        value.contains(" ") ? "\"\(value)\"" : value
    }

    /// Gmail filters have no name. Build a readable one from what it does, so
    /// the neutral model always has something to show and to match on.
    static func inferredName(for filter: GmailFilter) -> String {
        if let label = filter.action?.addLabelIds?.first(where: { !GmailSystemLabel.all.contains($0) }) {
            return "Filter → \(label)"
        }
        if let from = filter.criteria?.from { return "Filter from \(from)" }
        if let subject = filter.criteria?.subject { return "Filter subject \(subject)" }
        return filter.id.map { "Filter \($0)" } ?? "Untitled filter"
    }
}
