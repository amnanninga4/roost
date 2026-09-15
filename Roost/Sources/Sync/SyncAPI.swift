// Thin, typed client for server/ (see server/README.md). No retries, no storage: SyncClient owns policy.
import Foundation
import RoostCore

enum SyncAPIError: Error, CustomStringConvertible, Equatable {
    case unauthorized
    case forbidden
    case badRequest(String)
    case notFound
    case rateLimited
    case http(Int)
    case transport(String)
    case decoding(String)

    var description: String {
        switch self {
        case .unauthorized: "That token was not accepted (401)."
        case .forbidden: "The server refused that (403)."
        case let .badRequest(m): "Rejected by the server: \(m)"
        case .notFound: "Not found (404)."
        case .rateLimited: "Too many attempts (429)."
        case let .http(code): "Server returned HTTP \(code)."
        case let .transport(m): "Could not reach the server: \(m)"
        case let .decoding(m): "Unexpected response: \(m)"
        }
    }

    /// True for failures worth retrying later: offline, 5xx, rate limiting (429), a gateway saying no for
    /// now (403, 408), an unreadable reply. False for 400, 401, 404 and the rest of 4xx, which will not
    /// change on retry.
    ///
    /// 403 and 429 have their own cases now (pairing has to tell them apart), so they are named here rather
    /// than matched by number.
    var isTransient: Bool {
        switch self {
        case .transport, .decoding, .rateLimited, .forbidden: true
        case let .http(code): code >= 500 || code == 408
        case .unauthorized, .badRequest, .notFound: false
        }
    }

    /// The whole pass stops on these: the token is dead (re-pair), or nothing is getting through at all.
    var endsThePass: Bool {
        switch self {
        case .unauthorized, .transport: true
        case .forbidden, .badRequest, .notFound, .rateLimited, .http, .decoding: false
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
        /// Both optional so a server older than R-29, or a test stub, still decodes.
        let season: Season?
        let together: Bool?
        /// Optional so a server older than due-windows, or a test stub, still decodes.
        let weekdays: [Int]?
        let dueDay: Int?
        /// Optional so a server older than litter-rotations, or a test stub, still decodes.
        let rotation: ChoreRotation?
        let missPenalty: MissPenalty?
    }

    struct SyncResponse: Codable, Sendable {
        let serverTime: String
        let person: String
        let choresVersion: Int
        let cursor: Int
        /// The day the household started using Roost, as a Chicago calendar day (`2026-09-07`). The
        /// server owns it, so both phones get the same scheduling floor. Optional so a server older
        /// than R-23, or a test stub, still decodes; the phone then keeps whatever it had stored.
        let activeFrom: String?
        let completions: [CompletionDTO]
        let chores: [ChoreDTO]?
        // The list deltas (SyncAPI+Lists.swift). Optional so a pre-R-9 server, or a test stub, still decodes.
        let shopping: [ShoppingDTO]?
        let meals: [MealDTO]?
        let projects: [ProjectDTO]?
        let subtasks: [SubtaskDTO]?
        /// Optional so a server older than R-30, or a test stub, still decodes.
        let wishlist: [WishlistDTO]?
        /// The handoff delta (SyncAPI+Handoffs.swift). Optional for the same reason.
        let handoffs: [HandoffDTO]?
    }

    /// `POST /pair` — the only unauthenticated call. The token it returns is the bearer for everything else.
    struct PairResponse: Codable, Sendable, Equatable {
        let token: String
        let person: String
    }

    /// `DELETE /pair/self` — the server's answer when it revoked this device's own token.
    struct UnpairResponse: Codable, Sendable, Equatable {
        let unpaired: Bool
        let person: String
        let label: String?
    }

    /// `GET /me` — the server's own view of the calling device.
    ///
    /// `label` is the line `devices.js list` prints: for a paired phone, the pairing code's label and the
    /// name the phone sent itself, joined ("Anne test · iPhone 17 Pro"). `source` is `paired` or `file`;
    /// `createdAt` is null for a `file` token, because the tokens file has no pairing date.
    struct MeResponse: Codable, Sendable, Equatable {
        let person: String
        let label: String?
        let source: String
        let createdAt: String?
        let lastSeen: String?
    }

    struct ErrorBody: Codable { let error: String }

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        if let d = iso.date(from: s) {
            return d
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    /// `activeFrom` is a calendar day, not a timestamp: `2026-09-07` means the start of that day in
    /// America/Chicago, which is the floor `RoostCore.Scheduler` and `Tallies` count periods from. Parsed
    /// through the household calendar, so the phone's own time zone never moves the household's start.
    static func parseActiveFrom(_ value: String, calendar: HouseholdCalendar = HouseholdCalendar()) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        guard (1 ... 12).contains(month), (1 ... 31).contains(day) else { return nil }
        return calendar.startOfDay(calendar.date(year: year, month: month, day: day))
    }

    let baseURL: URL
    /// nil only for `POST /pair`, which is the one route that takes no bearer.
    let token: String?
    let session: URLSession

    init(baseURL: URL, token: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    // MARK: pairing

    /// Trades a 6-digit code for a bearer token. No auth.
    /// `404` unknown / used / expired (the server answers all three alike), `429` over the attempt limit,
    /// `400` when the code is not six digits or the device name is empty or over 60 characters.
    func pair(code: String, deviceName: String) async throws -> PairResponse {
        let body = try JSONEncoder().encode(["code": code, "deviceName": deviceName])
        let (data, status) = try await send(method: "POST", url: baseURL.appending(path: "pair"), body: body)
        try Self.check(status, data)
        return try Self.decode(PairResponse.self, data)
    }

    /// Revokes this device's own paired token. `403` for a hand-minted token: only the tokens file can revoke one.
    func unpair() async throws -> UnpairResponse {
        let (data, status) = try await send(method: "DELETE", url: baseURL.appending(path: "pair/self"), body: nil)
        try Self.check(status, data)
        return try Self.decode(UnpairResponse.self, data)
    }

    /// Who the server thinks this device is. The one way the app can read the label the household actually
    /// sees in `devices.js list`: pairing hands back a person and a token, never the label.
    func me() async throws -> MeResponse {
        let (data, status) = try await send(method: "GET", url: baseURL.appending(path: "me"), body: nil)
        try Self.check(status, data)
        return try Self.decode(MeResponse.self, data)
    }

    func sync(cursor: Int, choresVersion: Int?) async throws -> SyncResponse {
        var comps = URLComponents(url: baseURL.appending(path: "sync"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "cursor", value: String(cursor))]
        if let v = choresVersion {
            items.append(URLQueryItem(name: "choresVersion", value: String(v)))
        }
        comps.queryItems = items
        let (data, status) = try await send(method: "GET", url: comps.url!, body: nil)
        try Self.check(status, data)
        return try Self.decode(SyncResponse.self, data)
    }

    /// 201 new, 200 replay. Both are success.
    func post(id: String, choreId: String, completedAt: Date) async throws -> CompletionDTO {
        let body = try JSONEncoder().encode([
            "id": id,
            "choreId": choreId,
            "completedAt": Self.iso.string(from: completedAt),
        ])
        let (data, status) = try await send(method: "POST", url: baseURL.appending(path: "completions"), body: body)
        try Self.check(status, data)
        return try Self.decode(CompletionDTO.self, data)
    }

    /// 200 deleted (idempotent), 404 unknown.
    func delete(id: String) async throws -> CompletionDTO {
        let (data, status) = try await send(
            method: "DELETE",
            url: baseURL.appending(path: "completions/\(id)"),
            body: nil
        )
        try Self.check(status, data)
        return try Self.decode(CompletionDTO.self, data)
    }

    /// send / check / decode are shared with the list endpoints in SyncAPI+Lists.swift.
    func send(method: String, url: URL, body: Data?) async throws -> (Data, Int) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
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
        case 200 ... 299: return
        case 401: throw SyncAPIError.unauthorized
        case 403: throw SyncAPIError.forbidden
        case 404: throw SyncAPIError.notFound
        case 429: throw SyncAPIError.rateLimited
        case 400:
            let msg = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "bad request"
            throw SyncAPIError.badRequest(msg)
        default: throw SyncAPIError.http(status)
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch {
            throw SyncAPIError.decoding(error.localizedDescription)
        }
    }
}
