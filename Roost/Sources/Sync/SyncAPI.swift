// Thin, typed client for server/ (see server/README.md). No retries, no storage: SyncClient owns policy.
import Foundation
import RoostCore

enum SyncAPIError: Error, CustomStringConvertible, Equatable {
    case unauthorized
    case badRequest(String)
    case notFound
    case http(Int)
    case transport(String)
    case decoding(String)

    var description: String {
        switch self {
        case .unauthorized: return "That token was not accepted (401)."
        case .badRequest(let m): return "Rejected by the server: \(m)"
        case .notFound: return "Not found (404)."
        case .http(let code): return "Server returned HTTP \(code)."
        case .transport(let m): return "Could not reach the server: \(m)"
        case .decoding(let m): return "Unexpected response: \(m)"
        }
    }

    /// True for failures worth retrying later (offline, 5xx). False for 4xx, which will not change on retry.
    var isTransient: Bool {
        switch self {
        case .transport, .decoding: return true
        case .http(let code): return code >= 500
        case .unauthorized, .badRequest, .notFound: return false
        }
    }
}

struct SyncAPI: Sendable {
    struct CompletionDTO: Codable, Sendable, Equatable {
        let id: String
        let choreId: String
        let person: String
        let completedAt: String
        let createdAt: String
        let updatedAt: String
        let deleted: Bool
        let seq: Int
    }

    struct ChoreDTO: Codable, Sendable {
        let id: String
        let title: String
        let cadence: String
        let fixedAssignee: String?
        let category: String
    }

    struct SyncResponse: Codable, Sendable {
        let serverTime: String
        let person: String
        let choresVersion: Int
        let cursor: Int
        let completions: [CompletionDTO]
        let chores: [ChoreDTO]?
        // The list deltas (SyncAPI+Lists.swift). Optional so a pre-R-9 server, or a test stub, still decodes.
        let shopping: [ShoppingDTO]?
        let meals: [MealDTO]?
        let projects: [ProjectDTO]?
        let subtasks: [SubtaskDTO]?
    }

    struct ErrorBody: Codable { let error: String }

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        if let d = iso.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    let baseURL: URL
    let token: String
    let session: URLSession

    init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    func sync(cursor: Int, choresVersion: Int?) async throws -> SyncResponse {
        var comps = URLComponents(url: baseURL.appending(path: "sync"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "cursor", value: String(cursor))]
        if let v = choresVersion { items.append(URLQueryItem(name: "choresVersion", value: String(v))) }
        comps.queryItems = items
        let (data, status) = try await send(method: "GET", url: comps.url!, body: nil)
        try Self.check(status, data)
        return try Self.decode(SyncResponse.self, data)
    }

    /// 201 new, 200 replay. Both are success.
    func post(id: String, choreId: String, completedAt: Date) async throws -> CompletionDTO {
        let body = try JSONEncoder().encode(["id": id, "choreId": choreId, "completedAt": Self.iso.string(from: completedAt)])
        let (data, status) = try await send(method: "POST", url: baseURL.appending(path: "completions"), body: body)
        try Self.check(status, data)
        return try Self.decode(CompletionDTO.self, data)
    }

    /// 200 deleted (idempotent), 404 unknown.
    func delete(id: String) async throws -> CompletionDTO {
        let (data, status) = try await send(method: "DELETE", url: baseURL.appending(path: "completions/\(id)"), body: nil)
        try Self.check(status, data)
        return try Self.decode(CompletionDTO.self, data)
    }

    // send / check / decode are shared with the list endpoints in SyncAPI+Lists.swift.
    func send(method: String, url: URL, body: Data?) async throws -> (Data, Int) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        req.timeoutInterval = 15
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw SyncAPIError.transport("no HTTP response") }
            return (data, http.statusCode)
        } catch let e as SyncAPIError {
            throw e
        } catch {
            throw SyncAPIError.transport(error.localizedDescription)
        }
    }

    static func check(_ status: Int, _ data: Data) throws {
        switch status {
        case 200...299: return
        case 401: throw SyncAPIError.unauthorized
        case 404: throw SyncAPIError.notFound
        case 400:
            let msg = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "bad request"
            throw SyncAPIError.badRequest(msg)
        default: throw SyncAPIError.http(status)
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw SyncAPIError.decoding(error.localizedDescription) }
    }
}
