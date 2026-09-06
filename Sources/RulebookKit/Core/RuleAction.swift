import Foundation

public enum ActionKind: String, Codable, Hashable, Sendable, CaseIterable {
    case moveTo
    case copyTo
    case addLabel
    case removeLabel
    case markAsRead
    case markAsStarred
    case markImportance
    case forward
    case forwardAsAttachment
    case redirect
    case delete
    case archive
    case markAsSpam
    case stopProcessing
}

/// What a rule does to a message that matches it.
public enum RuleAction: Hashable, Sendable {
    /// Move out of the inbox into `folder`.
    case moveTo(MailboxFolder)
    /// Leave in place and put a copy in `folder`.
    case copyTo(MailboxFolder)
    /// Tag the message without moving it. A Gmail label; an Outlook category.
    case addLabel(MailboxFolder)
    case removeLabel(MailboxFolder)
    case markAsRead(Bool)
    case markAsStarred(Bool)
    case markImportance(Importance)
    case forward([MailAddress])
    case forwardAsAttachment([MailAddress])
    /// Resend to another address preserving the original sender.
    case redirect([MailAddress])
    case delete(permanent: Bool)
    /// Remove from the inbox without filing anywhere in particular.
    case archive
    /// `true` marks as spam, `false` guarantees it never will be.
    case markAsSpam(Bool)
    /// Stop evaluating any later rule.
    case stopProcessing

    public var kind: ActionKind {
        switch self {
        case .moveTo: .moveTo
        case .copyTo: .copyTo
        case .addLabel: .addLabel
        case .removeLabel: .removeLabel
        case .markAsRead: .markAsRead
        case .markAsStarred: .markAsStarred
        case .markImportance: .markImportance
        case .forward: .forward
        case .forwardAsAttachment: .forwardAsAttachment
        case .redirect: .redirect
        case .delete: .delete
        case .archive: .archive
        case .markAsSpam: .markAsSpam
        case .stopProcessing: .stopProcessing
        }
    }

    /// Actions that remove the message from where it was. Two of these in one
    /// rule is a contradiction worth reporting.
    public var isTerminalDisposition: Bool {
        switch self {
        case .moveTo, .delete, .archive: true
        default: false
        }
    }
}

// MARK: - Codable

extension RuleAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, folder, value, to, permanent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(ActionKind.self, forKey: .kind)

        func folder() throws -> MailboxFolder {
            try container.decode(MailboxFolder.self, forKey: .folder)
        }
        func recipients() throws -> [MailAddress] {
            try container.decode([MailAddress].self, forKey: .to)
        }
        /// Toggle actions default to `true` so `{"kind":"markAsRead"}` reads naturally.
        func flag() throws -> Bool {
            try container.decodeIfPresent(Bool.self, forKey: .value) ?? true
        }

        switch kind {
        case .moveTo: self = .moveTo(try folder())
        case .copyTo: self = .copyTo(try folder())
        case .addLabel: self = .addLabel(try folder())
        case .removeLabel: self = .removeLabel(try folder())
        case .markAsRead: self = .markAsRead(try flag())
        case .markAsStarred: self = .markAsStarred(try flag())
        case .markImportance:
            self = .markImportance(try container.decode(Importance.self, forKey: .value))
        case .forward: self = .forward(try recipients())
        case .forwardAsAttachment: self = .forwardAsAttachment(try recipients())
        case .redirect: self = .redirect(try recipients())
        case .delete:
            self = .delete(permanent: try container.decodeIfPresent(Bool.self, forKey: .permanent) ?? false)
        case .archive: self = .archive
        case .markAsSpam: self = .markAsSpam(try flag())
        case .stopProcessing: self = .stopProcessing
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)

        switch self {
        case .moveTo(let folder), .copyTo(let folder),
             .addLabel(let folder), .removeLabel(let folder):
            try container.encode(folder, forKey: .folder)
        case .markAsRead(let value), .markAsStarred(let value), .markAsSpam(let value):
            try container.encode(value, forKey: .value)
        case .markImportance(let value):
            try container.encode(value, forKey: .value)
        case .forward(let to), .forwardAsAttachment(let to), .redirect(let to):
            try container.encode(to, forKey: .to)
        case .delete(let permanent):
            try container.encode(permanent, forKey: .permanent)
        case .archive, .stopProcessing:
            break
        }
    }
}

extension RuleAction: CustomStringConvertible {
    public var description: String {
        switch self {
        case .moveTo(let f): "move to \(f.label)"
        case .copyTo(let f): "copy to \(f.label)"
        case .addLabel(let f): "add label \(f.label)"
        case .removeLabel(let f): "remove label \(f.label)"
        case .markAsRead(let v): v ? "mark as read" : "mark as unread"
        case .markAsStarred(let v): v ? "star" : "unstar"
        case .markImportance(let v): "set importance to \(v.rawValue)"
        case .forward(let to): "forward to \(to.map(\.address).joined(separator: ", "))"
        case .forwardAsAttachment(let to): "forward as attachment to \(to.map(\.address).joined(separator: ", "))"
        case .redirect(let to): "redirect to \(to.map(\.address).joined(separator: ", "))"
        case .delete(let permanent): permanent ? "delete permanently" : "delete"
        case .archive: "archive"
        case .markAsSpam(let v): v ? "mark as spam" : "never mark as spam"
        case .stopProcessing: "stop processing further rules"
        }
    }
}
