import Foundation

/// Mirrors Microsoft Graph `messageRulePredicates`.
///
/// Used for both `conditions` and `exceptions` on a ``MessageRule``. Every
/// property is optional; Graph treats an absent property as "not part of the
/// predicate", so `nil` and "empty" mean the same thing on the wire.
public struct MessageRulePredicates: Codable, Hashable, Sendable {
    public var bodyContains: [String]?
    public var bodyOrSubjectContains: [String]?
    public var categories: [String]?
    public var fromAddresses: [Recipient]?
    public var hasAttachments: Bool?
    public var headerContains: [String]?
    public var importance: Importance?
    public var isApprovalRequest: Bool?
    public var isAutomaticForward: Bool?
    public var isAutomaticReply: Bool?
    public var isEncrypted: Bool?
    public var isMeetingRequest: Bool?
    public var isMeetingResponse: Bool?
    public var isNonDeliveryReport: Bool?
    public var isPermissionControlled: Bool?
    public var isReadReceipt: Bool?
    public var isSigned: Bool?
    public var isVoicemail: Bool?
    public var messageActionFlag: ActionFlag?
    public var notSentToMe: Bool?
    public var recipientContains: [String]?
    public var senderContains: [String]?
    public var sensitivity: Sensitivity?
    public var sentCcMe: Bool?
    public var sentOnlyToMe: Bool?
    public var sentToAddresses: [Recipient]?
    public var sentToMe: Bool?
    public var sentToOrCcMe: Bool?
    public var subjectContains: [String]?
    public var withinSizeRange: SizeRange?

    public init(
        bodyContains: [String]? = nil,
        bodyOrSubjectContains: [String]? = nil,
        categories: [String]? = nil,
        fromAddresses: [Recipient]? = nil,
        hasAttachments: Bool? = nil,
        headerContains: [String]? = nil,
        importance: Importance? = nil,
        isApprovalRequest: Bool? = nil,
        isAutomaticForward: Bool? = nil,
        isAutomaticReply: Bool? = nil,
        isEncrypted: Bool? = nil,
        isMeetingRequest: Bool? = nil,
        isMeetingResponse: Bool? = nil,
        isNonDeliveryReport: Bool? = nil,
        isPermissionControlled: Bool? = nil,
        isReadReceipt: Bool? = nil,
        isSigned: Bool? = nil,
        isVoicemail: Bool? = nil,
        messageActionFlag: ActionFlag? = nil,
        notSentToMe: Bool? = nil,
        recipientContains: [String]? = nil,
        senderContains: [String]? = nil,
        sensitivity: Sensitivity? = nil,
        sentCcMe: Bool? = nil,
        sentOnlyToMe: Bool? = nil,
        sentToAddresses: [Recipient]? = nil,
        sentToMe: Bool? = nil,
        sentToOrCcMe: Bool? = nil,
        subjectContains: [String]? = nil,
        withinSizeRange: SizeRange? = nil
    ) {
        self.bodyContains = bodyContains
        self.bodyOrSubjectContains = bodyOrSubjectContains
        self.categories = categories
        self.fromAddresses = fromAddresses
        self.hasAttachments = hasAttachments
        self.headerContains = headerContains
        self.importance = importance
        self.isApprovalRequest = isApprovalRequest
        self.isAutomaticForward = isAutomaticForward
        self.isAutomaticReply = isAutomaticReply
        self.isEncrypted = isEncrypted
        self.isMeetingRequest = isMeetingRequest
        self.isMeetingResponse = isMeetingResponse
        self.isNonDeliveryReport = isNonDeliveryReport
        self.isPermissionControlled = isPermissionControlled
        self.isReadReceipt = isReadReceipt
        self.isSigned = isSigned
        self.isVoicemail = isVoicemail
        self.messageActionFlag = messageActionFlag
        self.notSentToMe = notSentToMe
        self.recipientContains = recipientContains
        self.senderContains = senderContains
        self.sensitivity = sensitivity
        self.sentCcMe = sentCcMe
        self.sentOnlyToMe = sentOnlyToMe
        self.sentToAddresses = sentToAddresses
        self.sentToMe = sentToMe
        self.sentToOrCcMe = sentToOrCcMe
        self.subjectContains = subjectContains
        self.withinSizeRange = withinSizeRange
    }

    /// `true` when no predicate is set — i.e. this would match nothing meaningful.
    public var isEmpty: Bool {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return true }
        return object.isEmpty
    }
}
