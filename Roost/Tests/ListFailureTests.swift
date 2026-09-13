// What the list sync does when the server says no, or nothing: a 400 is final, a 503 or a 429 keeps the
// row queued, and no single stuck row keeps the pull from running. Fixtures and the shared setup live in
// ListSyncTestCase.swift.
@testable import Roost
import SwiftData
import XCTest

final class ListFailureTests: ListSyncTestCase {
    func testRejectedCreateIsKeptLocallyAndNeverRetried() async throws {
        try await pairAsAnne()
        let meal = try XCTUnwrap(try ListActions.addMeal("x", tag: "", in: fresh(), now: listClock))
        let id = meal.id
        StubURLProtocol.reset { req in
            if req.httpMethod == "POST" {
                return (400, json(["error": "title required: 1-200 chars"]))
            }
            return (200, listsSyncJSON(cursor: 7))
        }
        _ = await client.syncNow()
        XCTAssertEqual(StubURLProtocol.requests("POST").count, 1)
        let rejected = try XCTUnwrap(try mealRow(id))
        XCTAssertTrue(rejected.rejected)
        XCTAssertNil(rejected.syncedAt)
        XCTAssertFalse(rejected.removed, "still on the phone")

        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 7)) }
        _ = await client.syncNow()
        XCTAssertEqual(StubURLProtocol.requests("POST").count, 0, "rejected rows are never retried")
    }

    func testOfflineKeepsTheListQueue() async throws {
        try await pairAsAnne()
        let item = try XCTUnwrap(try ListActions.addShoppingItem("Coffee", by: "anne", in: fresh(), now: listClock))
        let id = item.id
        StubURLProtocol.reset { _ in (503, Data()) }
        let outcome = await client.syncNow()
        if case .failed = outcome {} else {
            XCTFail("expected .failed, got \(outcome)")
        }
        let queued = try XCTUnwrap(try shoppingRow(id))
        XCTAssertNil(queued.syncedAt)
        XCTAssertFalse(queued.rejected)

        StubURLProtocol.reset { req in
            if req.httpMethod == "POST" {
                return (201, json(shoppingJSON(id: id, title: "Coffee", seq: 9)))
            }
            return (200, listsSyncJSON(cursor: 9))
        }
        let retried = await client.syncNow()
        XCTAssertEqual(retried, .synced(posted: 1, deleted: 0, received: 0))
        XCTAssertNotNil(try shoppingRow(id)?.syncedAt)
    }

    func testRateLimitedDeleteStaysQueuedAndThePullStillRuns() async throws {
        try await pairAsAnne(cursor: 7)
        let ctx = fresh()
        let item = ShoppingItemRecord(
            id: "sh-7",
            title: "Bread",
            addedBy: "anne",
            createdAt: listClock,
            syncedAt: listClock
        )
        ctx.insert(item)
        try ctx.save()
        try ListActions.removeShoppingItem(item, in: ctx, now: listClock)

        StubURLProtocol.reset { req in
            if req.httpMethod == "DELETE" {
                return (429, Data())
            }
            return (200, listsSyncJSON(cursor: 8, meals: [mealJSON(id: "m-9", title: "Soup", seq: 8)]))
        }
        let outcome = await client.syncNow()
        XCTAssertEqual(outcome, .synced(posted: 0, deleted: 0, received: 1), "one stuck row does not stop the pull")
        XCTAssertEqual(StubURLProtocol.requests("DELETE").count, 1)
        XCTAssertEqual(try mealRow("m-9")?.title, "Soup", "the delta landed")
        XCTAssertEqual(try state().cursor, 8)
        let queued = try XCTUnwrap(try shoppingRow("sh-7"))
        XCTAssertTrue(queued.removed)
        XCTAssertFalse(queued.deleteSynced, "still queued")
        XCTAssertFalse(queued.rejected)

        StubURLProtocol.reset { req in
            if req.httpMethod == "DELETE" {
                return (200, json(shoppingJSON(id: "sh-7", title: "Bread", seq: 9, deleted: true)))
            }
            return (200, listsSyncJSON(cursor: 9))
        }
        let retried = await client.syncNow()
        XCTAssertEqual(retried, .synced(posted: 0, deleted: 1, received: 0))
        XCTAssertEqual(try shoppingRow("sh-7")?.deleteSynced, true)
    }

    func testRefusedDeleteIsAcknowledgedAndNeverRetried() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let meal = MealRecord(id: "m-4", title: "Stew", createdAt: listClock, syncedAt: listClock)
        ctx.insert(meal)
        try ctx.save()
        try ListActions.removeMeal(meal, in: ctx, now: listClock)

        StubURLProtocol.reset { req in
            if req.httpMethod == "DELETE" {
                return (400, json(["error": "bad id"]))
            }
            return (200, listsSyncJSON(cursor: 7))
        }
        let outcome = await client.syncNow()
        XCTAssertEqual(outcome, .synced(posted: 0, deleted: 0, received: 0))
        let refused = try XCTUnwrap(try mealRow("m-4"))
        XCTAssertTrue(refused.rejected)
        XCTAssertTrue(refused.deleteSynced)
        XCTAssertTrue(refused.removed, "gone from the phone either way")

        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 7)) }
        _ = await client.syncNow()
        XCTAssertEqual(StubURLProtocol.requests("DELETE").count, 0, "never retried")
    }

    func testTransportFailureEndsThePassWithTheQueueIntact() async throws {
        // Nothing would get through, so the pass stops at the first row instead of timing out on each.
        try await pairAsAnne()
        let ctx = fresh()
        _ = try ListActions.addShoppingItem("Eggs", by: "anne", in: ctx, now: listClock)
        _ = try ListActions.addShoppingItem("Milk", by: "anne", in: ctx, now: listClock)
        StubURLProtocol.reset { _ in (StubURLProtocol.connectionLost, Data()) }
        let outcome = await client.syncNow()
        if case .failed = outcome {} else {
            XCTFail("expected .failed, got \(outcome)")
        }
        XCTAssertEqual(StubURLProtocol.requests("POST").count, 1, "one attempt, then the pass ends")
        XCTAssertEqual(StubURLProtocol.requests("GET").count, 0)
        let queued = try fresh()
            .fetch(FetchDescriptor<ShoppingItemRecord>(predicate: #Predicate { $0.syncedAt == nil }))
        XCTAssertEqual(queued.count, 2)
        XCTAssertTrue(queued.allSatisfy { !$0.rejected })
    }
}
