import Foundation

/// Translates between ``MailRule`` and Graph's `messageRule`.
///
/// ``RuleCapabilities`` is the cheap pre-flight check; this mapper is the
/// authority. Where a capability is true only for some conditions — Graph can
/// match an exact address but not an exact subject — the check passes and
/// ``encode(_:)`` reports the specific case.
public struct GraphRuleMapper: RuleMapper {
    public typealias Native = MessageRule

    public init() {}

    public static let capabilities = RuleCapabilities(
        provider: .microsoft,
        conditions: [
            .from, .recipient, .subject, .body, .subjectOrBody, .header,
            .hasAttachment, .size, .importance, .sensitivity, .hasLabels,
            .addressed, .messageKind, .actionFlag,
        ],
        actions: [
            .moveTo, .copyTo, .addLabel, .markAsRead, .markImportance,
            .forward, .forwardAsAttachment, .redirect, .delete, .stopProcessing,
        ],
        // `.equals` holds for addresses only; `encode` rejects it elsewhere.
        matchModes: [.contains, .equals],
        matchStrategies: [.all],
        supportsExceptions: true,
        supportsOrdering: true,
        supportsDisabling: true,
        supportsNamedHeaders: false
    )

    // MARK: - Neutral -> Graph

    public func encode(_ rule: MailRule) throws -> MessageRule {
        var issues: [ValidationIssue] = []

        func reject(_ what: String) {
            issues.append(ValidationIssue(
                severity: .error, rule: rule.name,
                message: "Microsoft 365 cannot express \(what)."
            ))
        }

        if rule.match == .any {
            reject("matching any of several conditions; Graph ANDs every predicate")
        }
        // Outlook numbers rules from 1. Sending 0 is rejected at request time
        // with: MessageRuleValidationError ... Field: 'Sequence', Value: '0'.
        if let order = rule.order, order < 1 {
            reject("an evaluation order of \(order); Outlook numbers rules from 1")
        }

        let conditions = encodePredicates(rule.conditions, reject: reject)
        let exceptions = encodePredicates(rule.exceptions, reject: reject)
        let actions = encodeActions(rule.actions, reject: reject)

        guard issues.isEmpty else { throw MappingError.unsupported(issues) }

        return MessageRule(
            id: rule.id,
            displayName: rule.name,
            // A rule with no order stated goes first; 0 is not a legal sequence.
            sequence: rule.order ?? 1,
            isEnabled: rule.isEnabled,
            conditions: conditions,
            exceptions: exceptions,
            actions: actions
        )
    }

    private func encodePredicates(
        _ conditions: [RuleCondition], reject: (String) -> Void
    ) -> MessageRulePredicates? {
        guard !conditions.isEmpty else { return nil }
        var predicates = MessageRulePredicates()

        for condition in conditions {
            switch condition {
            case .from(let match):
                switch match.mode {
                case .contains: predicates.senderContains = match.anyOf
                case .equals: predicates.fromAddresses = match.anyOf.map { Recipient(address: $0) }
                default: reject("a \(match.mode.rawValue) match on the sender")
                }

            case .recipient(let match):
                switch match.mode {
                case .contains: predicates.recipientContains = match.anyOf
                case .equals: predicates.sentToAddresses = match.anyOf.map { Recipient(address: $0) }
                default: reject("a \(match.mode.rawValue) match on recipients")
                }

            case .subject(let match):
                guard match.mode == .contains else { reject("a \(match.mode.rawValue) match on the subject"); continue }
                predicates.subjectContains = match.anyOf

            case .body(let match):
                guard match.mode == .contains else { reject("a \(match.mode.rawValue) match on the body"); continue }
                predicates.bodyContains = match.anyOf

            case .subjectOrBody(let match):
                guard match.mode == .contains else { reject("a \(match.mode.rawValue) match on subject or body"); continue }
                predicates.bodyOrSubjectContains = match.anyOf

            case .header(let name, let match):
                if name != nil { reject("a test on the named header \"\(name!)\"; Graph searches all headers") }
                guard match.mode == .contains else { reject("a \(match.mode.rawValue) match on headers"); continue }
                predicates.headerContains = match.anyOf

            case .hasAttachment(let value):
                predicates.hasAttachments = value

            case .size(let size):
                // Graph is in kilobytes. Round outward so the converted range
                // never excludes a message the neutral range included.
                predicates.withinSizeRange = SizeRange(
                    minimumSize: size.minimumBytes.map { $0 / 1024 },
                    maximumSize: size.maximumBytes.map { ($0 + 1023) / 1024 }
                )

            case .importance(let value): predicates.importance = value
            case .sensitivity(let value): predicates.sensitivity = value
            case .hasLabels(let values): predicates.categories = values
            case .actionFlag(let value): predicates.messageActionFlag = value

            case .addressed(let scope):
                switch scope {
                case .toMe: predicates.sentToMe = true
                case .ccMe: predicates.sentCcMe = true
                case .toOrCcMe: predicates.sentToOrCcMe = true
                case .onlyToMe: predicates.sentOnlyToMe = true
                case .notToMe: predicates.notSentToMe = true
                }

            case .messageKind(let kind, let expected):
                switch kind {
                case .meetingRequest: predicates.isMeetingRequest = expected
                case .meetingResponse: predicates.isMeetingResponse = expected
                case .readReceipt: predicates.isReadReceipt = expected
                case .nonDeliveryReport: predicates.isNonDeliveryReport = expected
                case .automaticReply: predicates.isAutomaticReply = expected
                case .automaticForward: predicates.isAutomaticForward = expected
                case .voicemail: predicates.isVoicemail = expected
                case .approvalRequest: predicates.isApprovalRequest = expected
                case .encrypted: predicates.isEncrypted = expected
                case .signed: predicates.isSigned = expected
                case .permissionControlled: predicates.isPermissionControlled = expected
                case .chat: reject("a test for chat messages")
                }

            case .rawQuery(let provider, _):
                reject("a raw \(provider.rawValue) query; Graph rules have no query syntax")
            }
        }

        return predicates
    }

    private func encodeActions(
        _ actions: [RuleAction], reject: (String) -> Void
    ) -> MessageRuleActions? {
        guard !actions.isEmpty else { return nil }
        var encoded = MessageRuleActions()
        var categories: [String] = []

        for action in actions {
            switch action {
            case .moveTo(let folder): encoded.moveToFolder = folder.id ?? folder.name
            case .copyTo(let folder): encoded.copyToFolder = folder.id ?? folder.name
            // Outlook categories are the closest thing it has to labels.
            case .addLabel(let folder): categories.append(folder.name ?? folder.id ?? "")
            case .markAsRead(let value): encoded.markAsRead = value
            case .markImportance(let value): encoded.markImportance = value
            case .forward(let to): encoded.forwardTo = to.map(Recipient.init(mail:))
            case .forwardAsAttachment(let to): encoded.forwardAsAttachmentTo = to.map(Recipient.init(mail:))
            case .redirect(let to): encoded.redirectTo = to.map(Recipient.init(mail:))
            case .delete(let permanent):
                if permanent { encoded.permanentDelete = true } else { encoded.delete = true }
            case .stopProcessing: encoded.stopProcessingRules = true
            case .removeLabel: reject("removing a category")
            case .markAsStarred: reject("starring a message")
            case .archive: reject("archiving; move the message to a folder instead")
            case .markAsSpam: reject("a junk-mail action in a rule")
            }
        }

        if !categories.isEmpty { encoded.assignCategories = categories }
        return encoded
    }

    // MARK: - Graph -> Neutral

    public func decode(_ native: MessageRule) throws -> MailRule {
        MailRule(
            id: native.id,
            name: native.displayName,
            order: native.sequence,
            isEnabled: native.isEnabled ?? true,
            match: .all,
            conditions: decodePredicates(native.conditions),
            exceptions: decodePredicates(native.exceptions),
            actions: decodeActions(native.actions),
            status: RuleStatus(
                hasError: native.hasError ?? false,
                isReadOnly: native.isReadOnly ?? false
            )
        )
    }

    private func decodePredicates(_ predicates: MessageRulePredicates?) -> [RuleCondition] {
        guard let p = predicates else { return [] }
        var conditions: [RuleCondition] = []

        if let v = p.senderContains { conditions.append(.from(StringMatch(v))) }
        if let v = p.fromAddresses {
            conditions.append(.from(StringMatch(v.compactMap(\.emailAddress.address), mode: .equals)))
        }
        if let v = p.recipientContains { conditions.append(.recipient(StringMatch(v))) }
        if let v = p.sentToAddresses {
            conditions.append(.recipient(StringMatch(v.compactMap(\.emailAddress.address), mode: .equals)))
        }
        if let v = p.subjectContains { conditions.append(.subject(StringMatch(v))) }
        if let v = p.bodyContains { conditions.append(.body(StringMatch(v))) }
        if let v = p.bodyOrSubjectContains { conditions.append(.subjectOrBody(StringMatch(v))) }
        if let v = p.headerContains { conditions.append(.header(name: nil, match: StringMatch(v))) }
        if let v = p.hasAttachments { conditions.append(.hasAttachment(v)) }
        if let v = p.withinSizeRange {
            conditions.append(.size(SizeConstraint(
                minimumBytes: v.minimumSize.map { $0 * 1024 },
                maximumBytes: v.maximumSize.map { $0 * 1024 }
            )))
        }
        if let v = p.importance { conditions.append(.importance(v)) }
        if let v = p.sensitivity { conditions.append(.sensitivity(v)) }
        if let v = p.categories { conditions.append(.hasLabels(v)) }
        if let v = p.messageActionFlag { conditions.append(.actionFlag(v)) }

        // Only the `true` side is meaningful: Graph writes `false` for "not part
        // of this rule" as readily as for "must not hold".
        if p.sentToMe == true { conditions.append(.addressed(.toMe)) }
        if p.sentCcMe == true { conditions.append(.addressed(.ccMe)) }
        if p.sentToOrCcMe == true { conditions.append(.addressed(.toOrCcMe)) }
        if p.sentOnlyToMe == true { conditions.append(.addressed(.onlyToMe)) }
        if p.notSentToMe == true { conditions.append(.addressed(.notToMe)) }

        let kinds: [(Bool?, MessageKind)] = [
            (p.isMeetingRequest, .meetingRequest),
            (p.isMeetingResponse, .meetingResponse),
            (p.isReadReceipt, .readReceipt),
            (p.isNonDeliveryReport, .nonDeliveryReport),
            (p.isAutomaticReply, .automaticReply),
            (p.isAutomaticForward, .automaticForward),
            (p.isVoicemail, .voicemail),
            (p.isApprovalRequest, .approvalRequest),
            (p.isEncrypted, .encrypted),
            (p.isSigned, .signed),
            (p.isPermissionControlled, .permissionControlled),
        ]
        for (value, kind) in kinds where value == true {
            conditions.append(.messageKind(kind, true))
        }

        return conditions
    }

    private func decodeActions(_ actions: MessageRuleActions?) -> [RuleAction] {
        guard let a = actions else { return [] }
        var decoded: [RuleAction] = []

        if let v = a.moveToFolder { decoded.append(.moveTo(.id(v))) }
        if let v = a.copyToFolder { decoded.append(.copyTo(.id(v))) }
        if let v = a.assignCategories { decoded.append(contentsOf: v.map { .addLabel(.named($0)) }) }
        if let v = a.markAsRead { decoded.append(.markAsRead(v)) }
        if let v = a.markImportance { decoded.append(.markImportance(v)) }
        if let v = a.forwardTo { decoded.append(.forward(v.map(\.mail))) }
        if let v = a.forwardAsAttachmentTo { decoded.append(.forwardAsAttachment(v.map(\.mail))) }
        if let v = a.redirectTo { decoded.append(.redirect(v.map(\.mail))) }
        if a.permanentDelete == true { decoded.append(.delete(permanent: true)) }
        else if a.delete == true { decoded.append(.delete(permanent: false)) }
        if a.stopProcessingRules == true { decoded.append(.stopProcessing) }

        return decoded
    }
}

// MARK: - Address bridging

extension Recipient {
    init(mail: MailAddress) {
        self.init(emailAddress: EmailAddress(name: mail.name, address: mail.address))
    }

    var mail: MailAddress {
        MailAddress(emailAddress.address ?? "", name: emailAddress.name)
    }
}
