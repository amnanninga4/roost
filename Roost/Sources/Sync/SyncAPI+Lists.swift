// The list endpoints of server/ (shopping, wishlist, meals, projects, subtasks; see server/README.md "Endpoints").
// Same rules as the completion calls in SyncAPI.swift: typed, no retries, no storage, SyncAPIError on
// anything but 2xx. ListSync.swift decides what to do with the outcome.
import Foundation

extension SyncAPI {
    struct ShoppingDTO: Codable, Sendable, Equatable {
        let id: String
        let title: String
        let addedBy: String
        let bought: Bool
        let boughtBy: String?
        let boughtAt: String?
        let createdAt: String
        let updatedAt: String
        let deleted: Bool
        let seq: Int
    }


    struct WishlistDTO: Codable, Sendable, Equatable {
        let id: String
        let title: String
        let priceCents: Int?
        let addedBy: String
        let bought: Bool
        let boughtBy: String?
        let boughtAt: String?
        let createdAt: String
        let updatedAt: String
        let deleted: Bool
        let seq: Int
    }

    struct MealDTO: Codable, Sendable, Equatable {
        let id: String
        let title: String
        let tag: String
        let lastMadeAt: String?
        let nextUp: Bool
        let createdAt: String
        let updatedAt: String
        let deleted: Bool
        let seq: Int
    }

    struct SubtaskDTO: Codable, Sendable, Equatable {
        let id: String
        let projectId: String
        let title: String
        let sortOrder: Int
        let done: Bool
        let doneBy: String?
        let doneAt: String?
        let createdAt: String
        let updatedAt: String
        let deleted: Bool
        let seq: Int
    }

    struct ProjectDTO: Codable, Sendable, Equatable {
        let id: String
        let title: String
        let createdAt: String
        let updatedAt: String
        let deleted: Bool
        let seq: Int
        /// On POST/PATCH/DELETE responses. Absent from /sync, where subtasks ride their own array.
        let subtasks: [SubtaskDTO]?
    }

    /// One PATCH (or POST) body value. `.null` clears a nullable field such as `lastMadeAt`.
    enum FieldValue: Encodable, Sendable, Equatable {
        case string(String)
        case bool(Bool)
        case int(Int)
        case null

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .string(text): try container.encode(text)
            case let .bool(flag): try container.encode(flag)
            case let .int(number): try container.encode(number)
            case .null: try container.encodeNil()
            }
        }
    }

    typealias Fields = [String: FieldValue]

    struct SubtaskSeed: Encodable, Sendable, Equatable {
        let id: String
        let title: String
    }

    private struct ProjectBody: Encodable {
        let id: String
        let title: String
        let subtasks: [SubtaskSeed]
    }

    /// A create's reply. `isNew` is a 201: the server built the row from this body, so `row` mirrors what
    /// was sent. A 200 is a replay of a POST the phone never heard back from: the body was ignored and
    /// `row` is whatever the server already had, which may be older than the phone's copy.
    struct Posted<Row: Decodable & Sendable>: Sendable {
        let row: Row
        let isNew: Bool
    }

    // MARK: shopping

    /// 201 new, 200 replay. `addedBy` comes back stamped from the token.
    func postShopping(id: String, title: String) async throws -> Posted<ShoppingDTO> {
        try await post("shopping", body: ["id": .string(id), "title": .string(title)] as Fields)
    }

    func patchShopping(id: String, _ fields: Fields) async throws -> ShoppingDTO {
        try await call("PATCH", "shopping/\(id)", body: fields)
    }

    func deleteShopping(id: String) async throws -> ShoppingDTO {
        try await call("DELETE", "shopping/\(id)")
    }


    // MARK: wishlist

    /// 201 new, 200 replay. The create carries the price too (null for none), so a 201 leaves only a
    /// pending `bought` to follow. `addedBy` comes back stamped from the token.
    func postWishlist(id: String, title: String, priceCents: Int?) async throws -> Posted<WishlistDTO> {
        let body: Fields = [
            "id": .string(id), "title": .string(title),
            "priceCents": priceCents.map { .int($0) } ?? .null,
        ]
        return try await post("wishlist", body: body)
    }

    func patchWishlist(id: String, _ fields: Fields) async throws -> WishlistDTO {
        try await call("PATCH", "wishlist/\(id)", body: fields)
    }

    func deleteWishlist(id: String) async throws -> WishlistDTO {
        try await call("DELETE", "wishlist/\(id)")
    }

    // MARK: meals

    /// 201 new, 200 replay. Every field rides the create, so a 201 reply is the phone's own values.
    func postMeal(
        id: String, title: String, tag: String, lastMadeAt: Date?, nextUp: Bool
    ) async throws -> Posted<MealDTO> {
        let body: Fields = [
            "id": .string(id), "title": .string(title), "tag": .string(tag),
            "lastMadeAt": lastMadeAt.map { .string(Self.iso.string(from: $0)) } ?? .null,
            "nextUp": .bool(nextUp),
        ]
        return try await post("meals", body: body)
    }

    func patchMeal(id: String, _ fields: Fields) async throws -> MealDTO {
        try await call("PATCH", "meals/\(id)", body: fields)
    }

    func deleteMeal(id: String) async throws -> MealDTO {
        try await call("DELETE", "meals/\(id)")
    }

    // MARK: projects + subtasks

    /// `subtasks` are created in order with `sortOrder` 0..n. On a 200 replay the server ignores them and
    /// returns what it already has, so callers reconcile against `subtasks` in the response.
    func postProject(id: String, title: String, subtasks: [SubtaskSeed]) async throws -> Posted<ProjectDTO> {
        try await post("projects", body: ProjectBody(id: id, title: title, subtasks: subtasks))
    }

    func patchProject(id: String, _ fields: Fields) async throws -> ProjectDTO {
        try await call("PATCH", "projects/\(id)", body: fields)
    }

    /// Cascades: the response's `subtasks` carry the seqs their soft-deletes took.
    func deleteProject(id: String) async throws -> ProjectDTO {
        try await call("DELETE", "projects/\(id)")
    }

    /// 400 when the project is unknown or deleted on the server.
    func postSubtask(projectId: String, id: String, title: String, sortOrder: Int) async throws -> Posted<SubtaskDTO> {
        let body: Fields = ["id": .string(id), "title": .string(title), "sortOrder": .int(sortOrder)]
        return try await post("projects/\(projectId)/subtasks", body: body)
    }

    func patchSubtask(id: String, _ fields: Fields) async throws -> SubtaskDTO {
        try await call("PATCH", "subtasks/\(id)", body: fields)
    }

    func deleteSubtask(id: String) async throws -> SubtaskDTO {
        try await call("DELETE", "subtasks/\(id)")
    }

    // MARK: plumbing

    /// A create: the reply says whether the server built the row (201) or already had it (200).
    private func post<T: Decodable & Sendable>(_ path: String, body: some Encodable) async throws -> Posted<T> {
        let (response, status) = try await send(method: "POST", url: baseURL.appending(path: path), body: encode(body))
        try Self.check(status, response)
        return try Posted(row: Self.decode(T.self, response), isNew: status == 201)
    }

    private func call<T: Decodable>(_ method: String, _ path: String, body: some Encodable) async throws -> T {
        try await call(method, path, data: encode(body))
    }

    private func call<T: Decodable>(_ method: String, _ path: String, data: Data? = nil) async throws -> T {
        let (response, status) = try await send(method: method, url: baseURL.appending(path: path), body: data)
        try Self.check(status, response)
        return try Self.decode(T.self, response)
    }

    private func encode(_ body: some Encodable) throws -> Data {
        do {
            return try JSONEncoder().encode(body)
        } catch {
            throw SyncAPIError.decoding("could not encode the request: \(error.localizedDescription)")
        }
    }
}
