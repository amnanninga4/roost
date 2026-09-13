// The inbound half of the list sync: what a /sync delta does to the local rows and the cursor,
// and that an edit still waiting to go out survives it. Fixtures and the shared setup live in
// ListSyncTestCase.swift.
@testable import Roost
import SwiftData
import XCTest

final class ListDeltaTests: ListSyncTestCase {
    // MARK: inbound delta

    func testDeltaWithDeletedRemovesLocalRow() async throws {
        try await pairAsAnne(cursor: 1)
        StubURLProtocol.reset { _ in
            (
                200,
                listsSyncJSON(
                    cursor: 2,
                    shopping: [shoppingJSON(id: "sh-wes", title: "Cat litter", addedBy: "wes", seq: 2)]
                )
            )
        }
        let first = await client.syncNow()
        XCTAssertEqual(first, .synced(posted: 0, deleted: 0, received: 1))
        let row = try XCTUnwrap(try shoppingRow("sh-wes"))
        XCTAssertFalse(row.removed)
        XCTAssertEqual(row.addedBy, "wes")
        XCTAssertNotNil(row.syncedAt, "rows from the server are already synced")

        StubURLProtocol.reset { _ in
            (
                200,
                listsSyncJSON(
                    cursor: 3,
                    shopping: [shoppingJSON(id: "sh-wes", title: "Cat litter", addedBy: "wes", seq: 3, deleted: true)]
                )
            )
        }
        _ = await client.syncNow()
        let gone = try XCTUnwrap(try shoppingRow("sh-wes"))
        XCTAssertTrue(gone.removed)
        XCTAssertTrue(gone.deleteSynced)
        XCTAssertEqual(try state().cursor, 3)
        let visible = try fresh().fetch(FetchDescriptor<ShoppingItemRecord>(predicate: #Predicate { !$0.removed }))
        XCTAssertEqual(visible.count, 0)
        XCTAssertEqual(StubURLProtocol.requests("DELETE").count, 0, "a server-side delete is not echoed back")
    }

    func testNextUpExclusivityIsReflectedAfterADelta() async throws {
        try await pairAsAnne(cursor: 10)
        StubURLProtocol.reset { _ in
            (200, listsSyncJSON(cursor: 12, meals: [
                mealJSON(id: "m-a", title: "Tacos", tag: "Weeknight", seq: 11),
                mealJSON(id: "m-c", title: "Ramen", nextUp: true, seq: 12),
            ]))
        }
        _ = await client.syncNow()
        XCTAssertEqual(try mealRow("m-c")?.nextUp, true)
        XCTAssertEqual(try mealRow("m-a")?.nextUp, false)

        // Wes moves it to Tacos: the server clears Ramen with its own seq and both rows ride the delta.
        StubURLProtocol.reset { _ in
            (200, listsSyncJSON(cursor: 14, meals: [
                mealJSON(id: "m-c", title: "Ramen", seq: 13),
                mealJSON(id: "m-a", title: "Tacos", tag: "Weeknight", nextUp: true, seq: 14),
            ]))
        }
        let outcome = await client.syncNow()
        XCTAssertEqual(outcome, .synced(posted: 0, deleted: 0, received: 2))
        XCTAssertEqual(try mealRow("m-a")?.nextUp, true)
        XCTAssertEqual(try mealRow("m-c")?.nextUp, false)
        XCTAssertEqual(try state().cursor, 14)

        // Even a delta that only names the new holder leaves exactly one badge.
        StubURLProtocol.reset { _ in (
            200,
            listsSyncJSON(cursor: 15, meals: [mealJSON(id: "m-b", title: "Chili", nextUp: true, seq: 15)])
        ) }
        _ = await client.syncNow()
        let holders = try fresh().fetch(FetchDescriptor<MealRecord>(predicate: #Predicate { $0.nextUp && !$0.removed }))
        XCTAssertEqual(holders.map(\.id), ["m-b"])
    }

    func testProjectDeltaWithSubtasksLandsInBothTables() async throws {
        try await pairAsAnne(cursor: 20)
        StubURLProtocol.reset { _ in
            (200, listsSyncJSON(cursor: 23,
                                projects: [projectJSON(id: "p-1", title: "Fix the fence", seq: 21)],
                                subtasks: [
                                    subtaskJSON(
                                        id: "st-1",
                                        projectId: "p-1",
                                        title: "Buy posts",
                                        sortOrder: 0,
                                        seq: 22
                                    ),
                                    subtaskJSON(
                                        id: "st-2",
                                        projectId: "p-1",
                                        title: "Dig holes",
                                        sortOrder: 1,
                                        done: true,
                                        doneBy: "wes",
                                        doneAt: listStamp,
                                        seq: 23
                                    ),
                                ]))
        }
        let outcome = await client.syncNow()
        XCTAssertEqual(outcome, .synced(posted: 0, deleted: 0, received: 3))
        let project = try XCTUnwrap(try projectRow("p-1"))
        XCTAssertEqual(project.title, "Fix the fence")
        XCTAssertEqual(project.seq, 21)
        let steps = try ListActions.liveSubtasks(of: "p-1", in: fresh())
        XCTAssertEqual(steps.map(\.id), ["st-1", "st-2"])
        XCTAssertEqual(steps.map(\.done), [false, true])
        XCTAssertEqual(steps[1].doneBy, "wes")
        XCTAssertEqual(try state().cursor, 23)

        // Deleted from the other phone: the project and every step come back deleted, each with its own seq.
        StubURLProtocol.reset { _ in
            (200, listsSyncJSON(cursor: 26,
                                projects: [projectJSON(id: "p-1", title: "Fix the fence", seq: 26, deleted: true)],
                                subtasks: [
                                    subtaskJSON(
                                        id: "st-1",
                                        projectId: "p-1",
                                        title: "Buy posts",
                                        sortOrder: 0,
                                        seq: 24,
                                        deleted: true
                                    ),
                                    subtaskJSON(
                                        id: "st-2",
                                        projectId: "p-1",
                                        title: "Dig holes",
                                        sortOrder: 1,
                                        seq: 25,
                                        deleted: true
                                    ),
                                ]))
        }
        _ = await client.syncNow()
        XCTAssertEqual(try projectRow("p-1")?.removed, true)
        XCTAssertEqual(try ListActions.liveSubtasks(of: "p-1", in: fresh()).count, 0)
        XCTAssertEqual(try state().cursor, 26)
    }

    func testCursorAdvancesToTheServersValue() async throws {
        try await pairAsAnne(cursor: 7)
        XCTAssertEqual(try state().cursor, 7)

        StubURLProtocol.reset { _ in (
            200,
            listsSyncJSON(cursor: 15, meals: [mealJSON(id: "m-1", title: "Soup", seq: 15)])
        ) }
        _ = await client.syncNow()
        XCTAssertTrue(StubURLProtocol.requests("GET").first?.query?.contains("cursor=7") ?? false)
        XCTAssertEqual(try state().cursor, 15, "the cursor is the server's, the max seq in the response")

        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 15)) }
        _ = await client.syncNow()
        XCTAssertTrue(StubURLProtocol.requests("GET").first?.query?.contains("cursor=15") ?? false)
        XCTAssertEqual(try state().cursor, 15, "holds when nothing changed")
    }

    func testPendingLocalEditSurvivesADeltaForTheSameRow() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let item = ShoppingItemRecord(
            id: "sh-5",
            title: "Dish soap",
            addedBy: "wes",
            createdAt: listClock,
            syncedAt: listClock
        )
        ctx.insert(item)
        try ctx.save()
        try ListActions.setBought(item, true, by: "anne", in: ctx, now: listClock)

        // The PATCH is rate limited, so the tap is still waiting to go out when the pull brings the
        // server's copy of the same row with bought false. That copy must not overwrite the tap.
        StubURLProtocol.reset { req in
            if req.httpMethod == "PATCH" {
                return (429, Data())
            }
            return (
                200,
                listsSyncJSON(
                    cursor: 12,
                    shopping: [shoppingJSON(id: "sh-5", title: "Dish soap", addedBy: "wes", seq: 12)]
                )
            )
        }
        let outcome = await client.syncNow()
        XCTAssertEqual(outcome, .synced(posted: 0, deleted: 0, received: 1), "the pull ran despite the stuck row")
        XCTAssertEqual(StubURLProtocol.requests("PATCH").count, 1)
        let row = try XCTUnwrap(try shoppingRow("sh-5"))
        XCTAssertTrue(row.bought, "the local tap wins over the older server copy")
        XCTAssertEqual(row.boughtBy, "anne")
        XCTAssertEqual(row.pendingFields, [.bought], "and is still queued")
        XCTAssertEqual(row.seq, 12, "the rest of the row is taken")

        // The next pass sends it.
        StubURLProtocol.reset { req in
            if req.httpMethod == "PATCH" {
                let sent = shoppingJSON(
                    id: "sh-5",
                    title: "Dish soap",
                    addedBy: "wes",
                    bought: true,
                    boughtBy: "anne",
                    boughtAt: listStamp,
                    seq: 13
                )
                return (200, json(sent))
            }
            return (200, listsSyncJSON(cursor: 13))
        }
        _ = await client.syncNow()
        XCTAssertEqual(StubURLProtocol.requests("PATCH").first?.body?["bought"] as? Bool, true)
        XCTAssertEqual(try shoppingRow("sh-5")?.pendingPatch, 0)
    }
}
