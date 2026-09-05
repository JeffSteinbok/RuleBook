import Foundation

/// A mail address, provider-independent.
public struct MailAddress: Codable, Hashable, Sendable {
    public var address: String
    public var name: String?

    public init(_ address: String, name: String? = nil) {
        self.address = address
        self.name = name
    }
}

/// A destination for a message: an Outlook folder, a Gmail label.
///
/// Providers identify these differently — Graph uses opaque folder ids, Gmail
/// uses label ids with well-known constants like `INBOX`. Either an `id` or a
/// `name` is enough; a mapper resolves whichever it needs.
public struct MailboxFolder: Codable, Hashable, Sendable {
    public var id: String?
    public var name: String?

    public init(id: String? = nil, name: String? = nil) {
        self.id = id
        self.name = name
    }

    public static func id(_ id: String) -> MailboxFolder { MailboxFolder(id: id) }
    public static func named(_ name: String) -> MailboxFolder { MailboxFolder(name: name) }

    /// For diagnostics and CLI output.
    public var label: String { name ?? id ?? "(unnamed folder)" }
}

/// How a set of candidate strings is compared against a message field.
public enum MatchMode: String, Codable, Hashable, Sendable, CaseIterable {
    case contains
    case equals
    case startsWith
    case endsWith
}

/// A text test: does the field match *any* of `anyOf`, under `mode`?
public struct StringMatch: Codable, Hashable, Sendable {
    public var anyOf: [String]
    public var mode: MatchMode

    public init(_ anyOf: [String], mode: MatchMode = .contains) {
        self.anyOf = anyOf
        self.mode = mode
    }

    public init(_ single: String, mode: MatchMode = .contains) {
        self.init([single], mode: mode)
    }
}

/// Message size bounds, in **bytes**.
///
/// Providers disagree on units — Graph's `withinSizeRange` is kilobytes,
/// Gmail's filter size is bytes. Bytes is the neutral unit; mappers convert.
public struct SizeConstraint: Codable, Hashable, Sendable {
    public var minimumBytes: Int?
    public var maximumBytes: Int?

    public init(minimumBytes: Int? = nil, maximumBytes: Int? = nil) {
        self.minimumBytes = minimumBytes
        self.maximumBytes = maximumBytes
    }
}

public enum Importance: String, Codable, Hashable, Sendable, CaseIterable {
    case low, normal, high
}

public enum Sensitivity: String, Codable, Hashable, Sendable, CaseIterable {
    case normal, personal, `private`, confidential
}

/// Where the mailbox owner appears in the message's recipients.
public enum AddressedScope: String, Codable, Hashable, Sendable, CaseIterable {
    case toMe
    case ccMe
    case toOrCcMe
    case onlyToMe
    case notToMe
}

/// Structural classes of message that providers can test for directly.
public enum MessageKind: String, Codable, Hashable, Sendable, CaseIterable {
    case meetingRequest
    case meetingResponse
    case readReceipt
    case nonDeliveryReport
    case automaticReply
    case automaticForward
    case voicemail
    case approvalRequest
    case encrypted
    case signed
    case permissionControlled
    case chat
}

/// Outlook's "flag for action" marker.
public enum ActionFlag: String, Codable, Hashable, Sendable, CaseIterable {
    case any
    case call
    case doNotForward
    case followUp
    case fyi
    case forward
    case noResponseNecessary
    case read
    case reply
    case replyToAll
    case review
}
