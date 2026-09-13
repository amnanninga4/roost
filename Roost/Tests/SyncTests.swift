import XCTest
import SwiftData
import RoostCore
@testable import Roost

final class SyncTests: XCTestCase {
    private var container: ModelContainer!
    private var tokens: InMemoryTokenStore!
    private var client: SyncClient!
    private let base = URL(string: "https://stub.local")!

    override func setUp() async throws {
        container = try ModelContainer(for: RoostSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        try ChoreSeeder.seedIfNeeded(into: ctx, from: ChoreSeeder.bundledChoresURL(bundle: Bundle(for: RoostAppMarker.self)))
        tokens = InMemoryTokenStore()
        client = SyncClient(modelContainer: container)
        await client.configure(tokenStore: tokens, session: StubURLProtocol.makeSession(), now: { Date(timeIntervalSince1970: 1_800_000_000) })
    }

    private func fresh() -> ModelContext { ModelContext(container) }

    private func state() throws -> SyncState { try ChoreSeeder.syncState(in: fresh()) }

    private func completion(_ id: String) throws -> CompletionRecord? {
        try fresh().fetch(FetchDescriptor<CompletionRecord>(predicate: #Predicate { $0.id == id })).first
    }

    /// Pairs with a stub that accepts any token and reports the given person/cursor.
    private func pairAsAnne(cursor: Int = 7) async throws {
        StubURLProtocol.reset { _ in (200, syncJSON(person: "anne", cursor: cursor)) }
        _ = try await client.pair(baseURL: base, token: "anne-token-0123456789abcdef")
    }

    private func insertLocal(_ id: String, choreId: String = "scoop-litter", person: String = "anne", deleted: Bool = false, synced: Bool = false) throws {
        let ctx = fresh()
        let r = CompletionRecord(id: id, choreId: choreId, person: person, completedAt: Date(timeIntervalSince1970: 1_799_999_000), syncedAt: synced ? Date() : nil, removed: deleted)
        ctx.insert(r)
        try ctx.save()
    }

    // MARK: pairing

    func testPairingStoresPersonCursorAndToken() async throws {
        try await pairAsAnne(cursor: 7)
        let s = try state()
        XCTAssertEqual(s.person, "anne")
        XCTAssertEqual(s.baseURL, "https://stub.local")
        XCTAssertEqual(s.cursor, 7)
        XCTAssertEqual(try tokens.read(), "anne-token-0123456789abcdef")
        let req = StubURLProtocol.requests("GET").first
        XCTAssertEqual(req?.path, "/sync")
        XCTAssertEqual(req?.authorization, "Bearer anne-token-0123456789abcdef")
        XCTAssertTrue(req?.query?.contains("cursor=0") ?? false)
    }

    func testPairingWith401StoresNothing() async throws {
        StubURLProtocol.reset { _ in (401, json(["error": "unauthorized"])) }
        do {
            _ = try await client.pair(baseURL: base, token: "bad-token-0123456789abcdef")
            XCTFail("expected 401")
        } catch let e as SyncAPIError {
            XCTAssertEqual(e, .unauthorized)
        }
        XCTAssertNil(try tokens.read())
        XCTAssertNil(try state().person)
        let outcome1 = await client.syncNow()
        XCTAssertEqual(outcome1, .unpaired)
    }

    // MARK: outbound queue

    func testQueuedCompletionIsPostedOnceAndMarkedSynced() async throws {
        try await pairAsAnne()
        try insertLocal("c-local-1")

        StubURLProtocol.reset { req in
            if req.httpMethod == "POST" {
                return (201, json(completionJSON(id: "c-local-1", choreId: "scoop-litter", person: "anne", completedAt: "2026-09-14T11:30:00.000Z", seq: 8)))
            }
            return (200, syncJSON(cursor: 8, completions: [completionJSON(id: "c-local-1", choreId: "scoop-litter", person: "anne", completedAt: "2026-09-14T11:30:00.000Z", seq: 8)]))
        }
        let first = await client.syncNow()
        XCTAssertEqual(first, .synced(posted: 1, deleted: 0, received: 1))
        XCTAssertEqual(StubURLProtocol.requests("POST").count, 1)
        XCTAssertEqual(StubURLProtocol.requests("POST").first?.body?["id"] as? String, "c-local-1")
        XCTAssertNotNil(try completion("c-local-1")?.syncedAt)
        XCTAssertEqual(try completion("c-local-1")?.seq, 8)
        XCTAssertEqual(try state().cursor, 8)

        StubURLProtocol.reset { _ in (200, syncJSON(cursor: 8)) }
        let second = await client.syncNow()
        XCTAssertEqual(second, .synced(posted: 0, deleted: 0, received: 0))
        XCTAssertEqual(StubURLProtocol.requests("POST").count, 0, "already synced rows are not re-posted")
        XCTAssertTrue(StubURLProtocol.requests("GET").first?.query?.contains("cursor=8") ?? false)
    }

    func testRejectedCompletionIsMarkedAndNotRetried() async throws {
        try await pairAsAnne()
        try insertLocal("c-bad", choreId: "scoop-litter")

        StubURLProtocol.reset { req in
            if req.httpMethod == "POST" { return (400, json(["error": "unknown or retired choreId"])) }
            return (200, syncJSON(cursor: 7))
        }
        _ = await client.syncNow()
        XCTAssertEqual(StubURLProtocol.requests("POST").count, 1)
        let r = try XCTUnwrap(try completion("c-bad"))
        XCTAssertTrue(r.rejected)
        XCTAssertNil(r.syncedAt)

        StubURLProtocol.reset { _ in (200, syncJSON(cursor: 7)) }
        _ = await client.syncNow()
        XCTAssertEqual(StubURLProtocol.requests("POST").count, 0, "rejected rows are never retried")
    }

    func testOfflineKeepsQueueAndRetriesLater() async throws {
        try await pairAsAnne()
        try insertLocal("c-offline")

        StubURLProtocol.reset { _ in (503, Data()) }
        let outcome = await client.syncNow()
        if case .failed = outcome {} else { XCTFail("expected .failed, got \(outcome)") }
        XCTAssertNil(try completion("c-offline")?.syncedAt)
        XCTAssertFalse(try XCTUnwrap(try completion("c-offline")).rejected)

        StubURLProtocol.reset { req in
            if req.httpMethod == "POST" {
                return (201, json(completionJSON(id: "c-offline", choreId: "scoop-litter", person: "anne", completedAt: "2026-09-14T11:30:00.000Z", seq: 9)))
            }
            return (200, syncJSON(cursor: 9))
        }
        let outcome2 = await client.syncNow()
        XCTAssertEqual(outcome2, .synced(posted: 1, deleted: 0, received: 0))
        XCTAssertNotNil(try completion("c-offline")?.syncedAt)
    }

    func testPendingDeleteReplaysAsDELETE() async throws {
        try await pairAsAnne()
        try insertLocal("c-del", deleted: true, synced: true)

        StubURLProtocol.reset { req in
            if req.httpMethod == "DELETE" {
                return (200, json(completionJSON(id: "c-del", choreId: "scoop-litter", person: "anne", completedAt: "2026-09-14T11:30:00.000Z", seq: 10, deleted: true)))
            }
            return (200, syncJSON(cursor: 10, completions: [completionJSON(id: "c-del", choreId: "scoop-litter", person: "anne", completedAt: "2026-09-14T11:30:00.000Z", seq: 10, deleted: true)]))
        }
        let outcome3 = await client.syncNow()
        XCTAssertEqual(outcome3, .synced(posted: 0, deleted: 1, received: 1))
        XCTAssertEqual(StubURLProtocol.requests("DELETE").map(\.path), ["/completions/c-del"])
        XCTAssertEqual(StubURLProtocol.requests("POST").count, 0, "a deleted row is never posted")
        let r = try XCTUnwrap(try completion("c-del"))
        XCTAssertTrue(r.removed)
        XCTAssertTrue(r.deleteSynced)

        StubURLProtocol.reset { _ in (200, syncJSON(cursor: 10)) }
        _ = await client.syncNow()
        XCTAssertEqual(StubURLProtocol.requests("DELETE").count, 0, "acknowledged deletes are not replayed")
    }

    // MARK: inbound delta

    func testDeltaWithDeletedRemovesLocalCompletion() async throws {
        try await pairAsAnne(cursor: 1)
        StubURLProtocol.reset { _ in
            (200, syncJSON(cursor: 2, completions: [completionJSON(id: "c-wes-1", choreId: "laundry", person: "wes", completedAt: "2026-09-14T13:00:00.000Z", seq: 2)]))
        }
        let outcome4 = await client.syncNow()
        XCTAssertEqual(outcome4, .synced(posted: 0, deleted: 0, received: 1))
        let r1 = try XCTUnwrap(try completion("c-wes-1"))
        XCTAssertFalse(r1.removed)
        XCTAssertEqual(r1.person, "wes")
        XCTAssertNotNil(r1.syncedAt, "rows from the server are already synced")

        StubURLProtocol.reset { _ in
            (200, syncJSON(cursor: 3, completions: [completionJSON(id: "c-wes-1", choreId: "laundry", person: "wes", completedAt: "2026-09-14T13:00:00.000Z", seq: 3, deleted: true)]))
        }
        _ = await client.syncNow()
        let r2 = try XCTUnwrap(try completion("c-wes-1"))
        XCTAssertTrue(r2.removed)
        XCTAssertTrue(r2.deleteSynced)
        XCTAssertEqual(try state().cursor, 3)

        let visible = try fresh().fetch(FetchDescriptor<CompletionRecord>(predicate: #Predicate { !$0.removed }))
        XCTAssertEqual(visible.count, 0)
    }

    func testDeltaWithChoresReseedsAndBumpsVersion() async throws {
        try await pairAsAnne()
        let trimmed = try ChoreList.load(from: ChoreSeeder.bundledChoresURL(bundle: Bundle(for: RoostAppMarker.self)))
            .chores.filter { $0.id != "scoop-litter" }
            .map { ["id": $0.id, "title": $0.title, "cadence": $0.cadence.rawValue, "fixedAssignee": $0.fixedAssignee?.rawValue as Any, "category": $0.category.rawValue] }
        StubURLProtocol.reset { _ in (200, syncJSON(cursor: 7, choresVersion: 2, chores: trimmed)) }
        _ = await client.syncNow()
        XCTAssertEqual(try state().choresVersion, 2)
        let active = try fresh().fetch(FetchDescriptor<ChoreRecord>(predicate: #Predicate { !$0.retired }))
        XCTAssertEqual(active.count, 30)
    }

    func testOverlappingSyncsCoalesce() async throws {
        try await pairAsAnne()
        StubURLProtocol.reset { _ in
            Thread.sleep(forTimeInterval: 0.2)
            return (200, syncJSON(cursor: 7))
        }
        async let a = client.syncNow()
        try await Task.sleep(for: .milliseconds(30))
        async let b = client.syncNow()
        let (ra, rb) = await (a, b)
        XCTAssertEqual(rb, .coalesced)
        if case .synced = ra {} else { XCTFail("first call should complete the sync, got \(ra)") }
        XCTAssertEqual(StubURLProtocol.requests("GET").count, 2, "coalesced call triggers exactly one extra pass")
    }
}
