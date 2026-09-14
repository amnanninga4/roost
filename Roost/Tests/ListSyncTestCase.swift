// Shared ground for ListReplayTests and ListDeltaTests: stub rows shaped like server/src/app.js's
// shape* functions, a full /sync body, and a test case that owns an in-memory store, a stub session,
// and the row lookups.
// MARK: - stub rows

// The server's timestamp on every stub row.
@testable import Roost
import RoostCore
import SwiftData
import XCTest

let listStamp = "2026-09-14T12:00:00.000Z"
/// The tests' "now": 2027-01-15T08:00:00Z.
let listClock = Date(timeIntervalSince1970: 1_800_000_000)

private func orNull(_ value: String?) -> Any {
    value.map { $0 as Any } ?? NSNull()
}

func shoppingJSON(
    id: String, title: String, addedBy: String = "anne", bought: Bool = false,
    boughtBy: String? = nil, boughtAt: String? = nil, seq: Int, deleted: Bool = false
) -> [String: Any] {
    [
        "id": id, "title": title, "addedBy": addedBy, "bought": bought,
        "boughtBy": orNull(boughtBy), "boughtAt": orNull(boughtAt),
        "createdAt": listStamp, "updatedAt": listStamp, "deleted": deleted, "seq": seq,
    ]
}


func wishlistJSON(
    id: String, title: String, priceCents: Int? = nil, addedBy: String = "anne", bought: Bool = false,
    boughtBy: String? = nil, boughtAt: String? = nil, seq: Int, deleted: Bool = false
) -> [String: Any] {
    [
        "id": id, "title": title, "priceCents": priceCents.map { $0 as Any } ?? NSNull(), "addedBy": addedBy,
        "bought": bought, "boughtBy": orNull(boughtBy), "boughtAt": orNull(boughtAt),
        "createdAt": listStamp, "updatedAt": listStamp, "deleted": deleted, "seq": seq,
    ]
}

func mealJSON(
    id: String, title: String, tag: String = "", lastMadeAt: String? = nil, nextUp: Bool = false,
    seq: Int, deleted: Bool = false
) -> [String: Any] {
    [
        "id": id, "title": title, "tag": tag, "lastMadeAt": orNull(lastMadeAt), "nextUp": nextUp,
        "createdAt": listStamp, "updatedAt": listStamp, "deleted": deleted, "seq": seq,
    ]
}

func projectJSON(
    id: String, title: String, seq: Int, deleted: Bool = false, subtasks: [[String: Any]]? = nil
) -> [String: Any] {
    var row: [String: Any] = [
        "id": id, "title": title, "createdAt": listStamp, "updatedAt": listStamp, "deleted": deleted, "seq": seq,
    ]
    if let subtasks {
        row["subtasks"] = subtasks
    }
    return row
}

func subtaskJSON(
    id: String, projectId: String, title: String, sortOrder: Int = 0, done: Bool = false,
    doneBy: String? = nil, doneAt: String? = nil, seq: Int, deleted: Bool = false
) -> [String: Any] {
    [
        "id": id, "projectId": projectId, "title": title, "sortOrder": sortOrder, "done": done,
        "doneBy": orNull(doneBy), "doneAt": orNull(doneAt),
        "createdAt": listStamp, "updatedAt": listStamp, "deleted": deleted, "seq": seq,
    ]
}

func handoffJSON(
    id: String, choreId: String, from: String, to: String, periodIndex: Int, cadence: String = "weekly",
    state: String = "pending", createdAt: String = listStamp, seq: Int, deleted: Bool = false
) -> [String: Any] {
    [
        "id": id, "choreId": choreId, "from": from, "to": to, "periodIndex": periodIndex,
        "cadence": cadence, "state": state,
        "createdAt": createdAt, "updatedAt": listStamp, "deleted": deleted, "seq": seq,
    ]
}

/// A full /sync body: the completions helper plus the five list arrays and the handoffs.
/// `activeFrom` is omitted unless given, which is a server older than R-23 as far as the phone is concerned.
func listsSyncJSON(
    person: String = "anne", cursor: Int, completions: [[String: Any]] = [], shopping: [[String: Any]] = [],
    meals: [[String: Any]] = [], projects: [[String: Any]] = [], subtasks: [[String: Any]] = [],
    wishlist: [[String: Any]] = [],
    handoffs: [[String: Any]] = [], activeFrom: String? = nil
) -> Data {
    var body: [String: Any] = [
        "serverTime": listStamp, "person": person, "choresVersion": 1, "cursor": cursor,
        "completions": completions, "shopping": shopping, "meals": meals, "projects": projects,
        "subtasks": subtasks, "wishlist": wishlist, "handoffs": handoffs,
    ]
    if let activeFrom {
        body["activeFrom"] = activeFrom
    }
    return json(body)
}

// MARK: - the shared test case

/// No tests of its own: the replay and delta suites inherit the store, the client, and the lookups.
class ListSyncTestCase: XCTestCase {
    var container: ModelContainer!
    var tokens: InMemoryTokenStore!
    var client: SyncClient!
    let base = URL(string: "https://stub.local")!

    override func setUp() async throws {
        container = try ModelContainer(
            for: RoostSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        tokens = InMemoryTokenStore()
        client = SyncClient(modelContainer: container)
        await client.configure(tokenStore: tokens, session: StubURLProtocol.makeSession(), now: { listClock })
    }

    func fresh() -> ModelContext {
        ModelContext(container)
    }

    func state() throws -> SyncState {
        try ChoreSeeder.syncState(in: fresh())
    }

    func shoppingRow(_ id: String, in context: ModelContext? = nil) throws -> ShoppingItemRecord? {
        try (context ?? fresh()).fetch(FetchDescriptor<ShoppingItemRecord>(predicate: #Predicate { $0.id == id })).first
    }


    func wishlistRow(_ id: String, in context: ModelContext? = nil) throws -> WishlistItemRecord? {
        try (context ?? fresh()).fetch(FetchDescriptor<WishlistItemRecord>(predicate: #Predicate { $0.id == id })).first
    }

    func mealRow(_ id: String, in context: ModelContext? = nil) throws -> MealRecord? {
        try (context ?? fresh()).fetch(FetchDescriptor<MealRecord>(predicate: #Predicate { $0.id == id })).first
    }

    func projectRow(_ id: String, in context: ModelContext? = nil) throws -> ProjectRecord? {
        try (context ?? fresh()).fetch(FetchDescriptor<ProjectRecord>(predicate: #Predicate { $0.id == id })).first
    }

    func subtaskRow(_ id: String, in context: ModelContext? = nil) throws -> SubtaskRecord? {
        try (context ?? fresh()).fetch(FetchDescriptor<SubtaskRecord>(predicate: #Predicate { $0.id == id })).first
    }

    func handoffRow(_ id: String, in context: ModelContext? = nil) throws -> HandoffRecord? {
        try (context ?? fresh()).fetch(FetchDescriptor<HandoffRecord>(predicate: #Predicate { $0.id == id })).first
    }

    func allHandoffs(in context: ModelContext? = nil) throws -> [HandoffRecord] {
        try (context ?? fresh()).fetch(
            FetchDescriptor<HandoffRecord>(sortBy: [SortDescriptor(\.createdAt)])
        )
    }

    /// Pairs with a stub that accepts any token and reports Anne at the given cursor.
    func pairAsAnne(cursor: Int = 7) async throws {
        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: cursor)) }
        _ = try await client.pair(baseURL: base, token: "anne-token-0123456789abcdef")
    }
}
