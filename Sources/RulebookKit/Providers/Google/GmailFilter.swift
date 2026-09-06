import Foundation

/// Mirrors the Gmail API `Filter` resource
/// (`users.settings.filters`). Gmail calls these *filters*, not rules.
public struct GmailFilter: Codable, Hashable, Sendable, Identifiable {
    public var id: String?
    public var criteria: GmailFilterCriteria?
    public var action: GmailFilterAction?

    public init(
        id: String? = nil,
        criteria: GmailFilterCriteria? = nil,
        action: GmailFilterAction? = nil
    ) {
        self.id = id
        self.criteria = criteria
        self.action = action
    }
}

public struct GmailFilterCriteria: Codable, Hashable, Sendable {
    public var from: String?
    public var to: String?
    public var subject: String?
    /// Gmail search syntax. Everything the four typed fields cannot say.
    public var query: String?
    /// Gmail search syntax that must *not* match — Gmail's form of exceptions.
    public var negatedQuery: String?
    public var hasAttachment: Bool?
    public var excludeChats: Bool?
    /// In bytes, paired with ``sizeComparison``. Gmail supports one bound only.
    public var size: Int?
    public var sizeComparison: GmailSizeComparison?

    public init(
        from: String? = nil,
        to: String? = nil,
        subject: String? = nil,
        query: String? = nil,
        negatedQuery: String? = nil,
        hasAttachment: Bool? = nil,
        excludeChats: Bool? = nil,
        size: Int? = nil,
        sizeComparison: GmailSizeComparison? = nil
    ) {
        self.from = from
        self.to = to
        self.subject = subject
        self.query = query
        self.negatedQuery = negatedQuery
        self.hasAttachment = hasAttachment
        self.excludeChats = excludeChats
        self.size = size
        self.sizeComparison = sizeComparison
    }
}

public enum GmailSizeComparison: String, Codable, Hashable, Sendable {
    case unspecified, smaller, larger
}

/// Gmail expresses almost every effect as a label change.
public struct GmailFilterAction: Codable, Hashable, Sendable {
    public var addLabelIds: [String]?
    public var removeLabelIds: [String]?
    /// A single verified forwarding address.
    public var forward: String?

    public init(
        addLabelIds: [String]? = nil,
        removeLabelIds: [String]? = nil,
        forward: String? = nil
    ) {
        self.addLabelIds = addLabelIds
        self.removeLabelIds = removeLabelIds
        self.forward = forward
    }
}

/// Gmail's reserved label ids. Effects that other providers model as distinct
/// actions — archive, star, trash — are adding or removing one of these.
public enum GmailSystemLabel {
    public static let inbox = "INBOX"
    public static let unread = "UNREAD"
    public static let starred = "STARRED"
    public static let trash = "TRASH"
    public static let spam = "SPAM"
    public static let important = "IMPORTANT"

    public static let all: Set<String> = [inbox, unread, starred, trash, spam, important]
}
