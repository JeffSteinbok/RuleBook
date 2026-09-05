import Foundation

/// Mirrors Microsoft Graph `messageRuleActions`.
public struct MessageRuleActions: Codable, Hashable, Sendable {
    public var assignCategories: [String]?
    public var copyToFolder: String?
    public var delete: Bool?
    public var forwardAsAttachmentTo: [Recipient]?
    public var forwardTo: [Recipient]?
    public var markAsRead: Bool?
    public var markImportance: Importance?
    public var moveToFolder: String?
    public var permanentDelete: Bool?
    public var redirectTo: [Recipient]?
    public var stopProcessingRules: Bool?

    public init(
        assignCategories: [String]? = nil,
        copyToFolder: String? = nil,
        delete: Bool? = nil,
        forwardAsAttachmentTo: [Recipient]? = nil,
        forwardTo: [Recipient]? = nil,
        markAsRead: Bool? = nil,
        markImportance: Importance? = nil,
        moveToFolder: String? = nil,
        permanentDelete: Bool? = nil,
        redirectTo: [Recipient]? = nil,
        stopProcessingRules: Bool? = nil
    ) {
        self.assignCategories = assignCategories
        self.copyToFolder = copyToFolder
        self.delete = delete
        self.forwardAsAttachmentTo = forwardAsAttachmentTo
        self.forwardTo = forwardTo
        self.markAsRead = markAsRead
        self.markImportance = markImportance
        self.moveToFolder = moveToFolder
        self.permanentDelete = permanentDelete
        self.redirectTo = redirectTo
        self.stopProcessingRules = stopProcessingRules
    }

    /// `true` when no action is set — Graph rejects a rule that does nothing.
    public var isEmpty: Bool {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return true }
        return object.isEmpty
    }
}
