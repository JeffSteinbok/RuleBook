import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The Microsoft Graph wire layer: HTTP and JSON only, speaking Graph's own
/// `messageRule` type.
///
/// ``GraphRuleStore`` wraps this with ``GraphRuleMapper`` to expose the
/// neutral ``MailRule`` model. Use this directly only when you need something
/// Graph-specific that the neutral model cannot express.
///
/// Endpoint: `/me/mailFolders/inbox/messageRules` — Graph exposes message
/// rules on the Inbox only.
public struct GraphMessageRuleClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://graph.microsoft.com/v1.0")!

    private let baseURL: URL
    private let tokenProvider: any TokenProvider
    private let session: URLSession

    public init(
        tokenProvider: any TokenProvider,
        baseURL: URL = GraphMessageRuleClient.defaultBaseURL,
        session: URLSession = .shared
    ) {
        self.tokenProvider = tokenProvider
        self.baseURL = baseURL
        self.session = session
    }

    private var rulesURL: URL {
        baseURL.appendingPathComponent("me/mailFolders/inbox/messageRules")
    }

    // MARK: - CRUD

    public func listRules() async throws -> [MessageRule] {
        // Graph pages this collection; follow @odata.nextLink until it stops.
        var url: URL? = rulesURL
        var all: [MessageRule] = []

        while let next = url {
            let page: GraphCollection<MessageRule> = try await send(
                request(.get, url: next),
                expecting: GraphCollection<MessageRule>.self
            )
            all.append(contentsOf: page.value)
            url = page.nextLink.flatMap(URL.init(string:))
        }

        return all.sorted { ($0.sequence, $0.displayName) < ($1.sequence, $1.displayName) }
    }

    public func rule(id: String) async throws -> MessageRule {
        do {
            return try await send(
                request(.get, url: rulesURL.appendingPathComponent(id)),
                expecting: MessageRule.self
            )
        } catch let RuleStoreError.provider(_, status, _, _) where status == 404 {
            throw RuleStoreError.notFound(id: id)
        }
    }

    public func createRule(_ rule: MessageRule) async throws -> MessageRule {
        var req = try await request(.post, url: rulesURL)
        req.httpBody = try Self.encoder.encode(rule.writablePayload())
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(req, expecting: MessageRule.self)
    }

    public func updateRule(id: String, with rule: MessageRule) async throws -> MessageRule {
        var req = try await request(.patch, url: rulesURL.appendingPathComponent(id))
        req.httpBody = try Self.encoder.encode(rule.writablePayload())
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            return try await send(req, expecting: MessageRule.self)
        } catch let RuleStoreError.provider(_, status, _, _) where status == 404 {
            throw RuleStoreError.notFound(id: id)
        }
    }

    public func deleteRule(id: String) async throws {
        let req = try await request(.delete, url: rulesURL.appendingPathComponent(id))
        do {
            try await sendIgnoringBody(req)
        } catch let RuleStoreError.provider(_, status, _, _) where status == 404 {
            throw RuleStoreError.notFound(id: id)
        }
    }

    // MARK: - Plumbing

    private enum Method: String { case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE" }

    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    private func request(_ method: Method, url: URL) async throws -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.setValue("Bearer \(try await tokenProvider.accessToken())", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private func send<T: Decodable>(_ request: URLRequest, expecting: T.Type) async throws -> T {
        let data = try await validated(request)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw RuleStoreError.decoding(error)
        }
    }

    private func sendIgnoringBody(_ request: URLRequest) async throws {
        _ = try await validated(request)
    }

    private func validated(_ request: URLRequest) async throws -> Data {
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
            let error = try? Self.decoder.decode(GraphErrorEnvelope.self, from: data)
            throw RuleStoreError.provider(
                .microsoft,
                status: http.statusCode,
                code: error?.error.code,
                message: error?.error.message
            )
        }
        return data
    }
}

// MARK: - Graph wire envelopes

struct GraphCollection<Element: Decodable>: Decodable {
    let value: [Element]
    let nextLink: String?

    private enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}

struct GraphErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let code: String?
        let message: String?
    }
    let error: Payload
}
