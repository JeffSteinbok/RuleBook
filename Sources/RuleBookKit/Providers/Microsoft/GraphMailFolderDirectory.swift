import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// ``FolderDirectory`` over Graph's `/me/mailFolders`.
///
/// Walks the whole tree — Graph returns only top-level folders by default, and
/// rules routinely target nested ones — and builds `Parent/Child` paths. The
/// result is cached for the lifetime of the instance, since a rule list
/// typically resolves the same handful of folders repeatedly.
///
/// Needs the `Mail.ReadBasic` scope, which `MailboxSettings.ReadWrite` does not
/// include: folders are a different resource from mailbox settings.
public actor GraphMailFolderDirectory: FolderDirectory {
    private let baseURL: URL
    private let tokenProvider: any TokenProvider
    private let session: URLSession

    private var cache: [MailboxFolder]?
    private var pathByID: [String: String] = [:]
    /// Set when a fetch fails — most often because `Mail.ReadBasic` has not
    /// been consented. Resolution then degrades to showing raw ids rather than
    /// re-requesting, and failing, once per folder.
    private var isUnavailable = false

    public init(
        tokenProvider: any TokenProvider,
        baseURL: URL = GraphMessageRuleClient.defaultBaseURL,
        session: URLSession = .shared
    ) {
        self.tokenProvider = tokenProvider
        self.baseURL = baseURL
        self.session = session
    }

    public func folders() async throws -> [MailboxFolder] {
        if let cache { return cache }
        if isUnavailable { return [] }

        let raw: [GraphMailFolder]
        do {
            raw = try await fetchAll()
        } catch {
            isUnavailable = true
            throw error
        }
        let byID = Dictionary(raw.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Build a display path by walking up parentFolderId. Depth is bounded
        // so a cycle in the data cannot hang the caller.
        func path(for folder: GraphMailFolder) -> String {
            var segments = [folder.displayName]
            var parentID = folder.parentFolderId
            var depth = 0
            while let id = parentID, let parent = byID[id], depth < 16 {
                segments.append(parent.displayName)
                parentID = parent.parentFolderId
                depth += 1
            }
            return segments.reversed().joined(separator: "/")
        }

        var resolved: [MailboxFolder] = []
        for folder in raw {
            let display = path(for: folder)
            pathByID[folder.id] = display
            resolved.append(MailboxFolder(id: folder.id, name: display))
        }
        resolved.sort { ($0.name ?? "") < ($1.name ?? "") }

        cache = resolved
        return resolved
    }

    public func name(forID id: String) async throws -> String? {
        _ = try await folders()
        return pathByID[id]
    }

    public func id(forName name: String) async throws -> String? {
        let all = try await folders()

        // An exact path wins; otherwise fall back to a unique leaf name, so
        // "Reading" resolves without anyone typing "Inbox/Reading".
        if let exact = all.first(where: { $0.name?.caseInsensitiveCompare(name) == .orderedSame }) {
            return exact.id
        }
        let leaves = all.filter {
            ($0.name?.split(separator: "/").last).map(String.init)?
                .caseInsensitiveCompare(name) == .orderedSame
        }
        return leaves.count == 1 ? leaves[0].id : nil
    }

    // MARK: - Fetching

    private func fetchAll() async throws -> [GraphMailFolder] {
        var pending: [String?] = [nil]   // nil == the mailbox root
        var found: [GraphMailFolder] = []

        while let parent = pending.popLast() {
            let path = parent.map { "me/mailFolders/\($0)/childFolders" } ?? "me/mailFolders"
            var next: URL? = baseURL
                .appendingPathComponent(path)
                .appending(queryItems: [
                    URLQueryItem(name: "$top", value: "100"),
                    // Graph omits hidden folders by default, and rules can
                    // target them.
                    URLQueryItem(name: "includeHiddenFolders", value: "true"),
                    URLQueryItem(name: "$select", value: "id,displayName,parentFolderId,childFolderCount"),
                ])

            while let url = next {
                let page: GraphCollection<GraphMailFolder> = try await get(url)
                found.append(contentsOf: page.value)
                // Only descend where Graph says there is something to find.
                pending.append(contentsOf: page.value.filter { ($0.childFolderCount ?? 0) > 0 }.map { $0.id })
                next = page.nextLink.flatMap(URL.init(string:))
            }
        }

        return found
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await tokenProvider.accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RuleStoreError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw RuleStoreError.provider(.microsoft, status: -1, code: nil, message: "Non-HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(GraphErrorEnvelope.self, from: data)
            throw RuleStoreError.provider(
                .microsoft,
                status: http.statusCode,
                code: error?.error.code,
                message: error?.error.message
            )
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RuleStoreError.decoding(error)
        }
    }
}

struct GraphMailFolder: Decodable, Sendable {
    let id: String
    let displayName: String
    let parentFolderId: String?
    let childFolderCount: Int?
}
