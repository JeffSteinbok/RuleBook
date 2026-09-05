import Foundation

/// Resolves between a provider's opaque folder identifiers and names people
/// recognise.
///
/// Rules reference destinations by id — Graph folder ids, Gmail label ids —
/// which are unreadable and useless in a UI. A directory turns
/// `AQMkADAwATMwMAItODAxNy1jMTVm…` into `Inbox/Reading`, and a name typed by a
/// person back into the id a write needs.
public protocol FolderDirectory: Sendable {
    /// Every folder, in a stable order.
    func folders() async throws -> [MailboxFolder]
    /// The display path for an id, or nil when it is unknown.
    func name(forID id: String) async throws -> String?
    /// The id for a name or path, matched case-insensitively.
    func id(forName name: String) async throws -> String?
}

public extension FolderDirectory {
    /// Fills in whichever half of a ``MailboxFolder`` is missing, leaving the
    /// folder untouched when it cannot be resolved.
    func resolve(_ folder: MailboxFolder) async -> MailboxFolder {
        var resolved = folder
        if resolved.name == nil, let id = resolved.id {
            resolved.name = try? await name(forID: id)
        }
        if resolved.id == nil, let name = resolved.name {
            resolved.id = try? await id(forName: name)
        }
        return resolved
    }
}

/// A fixed directory, for tests and previews.
public struct StaticFolderDirectory: FolderDirectory {
    private let byID: [String: String]

    public init(_ byID: [String: String]) { self.byID = byID }

    public func folders() async throws -> [MailboxFolder] {
        byID.map { MailboxFolder(id: $0.key, name: $0.value) }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    public func name(forID id: String) async throws -> String? { byID[id] }

    public func id(forName name: String) async throws -> String? {
        byID.first { $0.value.caseInsensitiveCompare(name) == .orderedSame }?.key
    }
}
