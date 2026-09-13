// The edits and removals of the list sync replayed against the stub server. Fixtures and the shared
// setup live in ListSyncTestCase.swift; the creates are in ListCreateTests.swift and the failure modes
// in ListFailureTests.swift.
@testable import Roost
import SwiftData
import XCTest

final class ListReplayTests: ListSyncTestCase {
    // MARK: edits

    func testBoughtToggleIsPatchedWithOnlyThatField() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let item = ShoppingItemRecord(
            id: "sh-2",
            title: "Eggs",
            addedBy: "wes",
            createdAt: listClock,
            syncedAt: listClock
        )
        item.seq = 5
        ctx.insert(item)
        try ctx.save()
        try ListActions.setBought(item, true, by: "anne", in: ctx, now: listClock)
        XCTAssertTrue(item.needsPatch)
        XCTAssertEqual(item.boughtBy, "anne", "local preview until the server answers")

        StubURLProtocol.reset { req in
            let row = shoppingJSON(
                id: "sh-2",
                title: "Eggs",
                addedBy: "wes",
                bought: true,
                boughtBy: "anne",
                boughtAt: "2026-09-14T12:30:00.000Z",
                seq: 9
            )
            if req.httpMethod == "PATCH" {
                return (200, json(row))
            }
            return (200, listsSyncJSON(cursor: 9, shopping: [row]))
        }
        let outcome = await client.syncNow()
        XCTAssertEqual(outcome, .synced(posted: 1, deleted: 0, received: 1))
        let patches = StubURLProtocol.requests("PATCH")
        XCTAssertEqual(patches.map(\.path), ["/shopping/sh-2"])
        XCTAssertEqual(patches.first?.body?["bought"] as? Bool, true)
        XCTAssertNil(patches.first?.body?["title"], "only the changed field is sent")
        XCTAssertEqual(StubURLProtocol.requests("POST").count, 0)
        let bought = try XCTUnwrap(try shoppingRow("sh-2"))
        XCTAssertEqual(bought.pendingPatch, 0)
        XCTAssertTrue(bought.bought)
        XCTAssertEqual(bought.boughtAt, SyncAPI.parseDate("2026-09-14T12:30:00.000Z"))
        XCTAssertEqual(bought.seq, 9)

        // Un-buy: PATCH bought=false, then nothing more to send.
        let editCtx = fresh()
        try ListActions.setBought(
            XCTUnwrap(try shoppingRow("sh-2", in: editCtx)),
            false,
            by: "anne",
            in: editCtx,
            now: listClock
        )
        StubURLProtocol.reset { req in
            if req.httpMethod == "PATCH" {
                return (
                    200,
                    json(shoppingJSON(id: "sh-2", title: "Eggs", addedBy: "wes", seq: 10))
                )
            }
            return (200, listsSyncJSON(cursor: 10))
        }
        _ = await client.syncNow()
        XCTAssertEqual(StubURLProtocol.requests("PATCH").first?.body?["bought"] as? Bool, false)
        XCTAssertNil(try shoppingRow("sh-2")?.boughtBy)

        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 10)) }
        _ = await client.syncNow()
        XCTAssertEqual(StubURLProtocol.requests("PATCH").count, 0, "acknowledged edits are not replayed")
    }

    func testMadeItTodayAndNextUpPatchTheMealAndClearTheOldOneLocally() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let chili = MealRecord(id: "m-chili", title: "Chili", nextUp: true, createdAt: listClock, syncedAt: listClock)
        let tacos = MealRecord(id: "m-tacos", title: "Tacos", createdAt: listClock, syncedAt: listClock)
        ctx.insert(chili)
        ctx.insert(tacos)
        try ctx.save()
        try ListActions.madeToday(tacos, in: ctx, now: listClock)
        try ListActions.setNextUp(tacos, true, in: ctx, now: listClock)
        XCTAssertFalse(chili.nextUp, "the badge moves at once")
        XCTAssertEqual(chili.pendingPatch, 0, "the server clears the old holder itself; nothing to send for it")
        XCTAssertEqual(tacos.pendingFields, [.lastMadeAt, .nextUp])

        StubURLProtocol.reset { req in
            let row = mealJSON(
                id: "m-tacos",
                title: "Tacos",
                lastMadeAt: "2027-01-15T08:00:00.000Z",
                nextUp: true,
                seq: 13
            )
            if req.httpMethod == "PATCH" {
                return (200, json(row))
            }
            return (200, listsSyncJSON(cursor: 13, meals: [mealJSON(id: "m-chili", title: "Chili", seq: 12), row]))
        }
        let outcome = await client.syncNow()
        XCTAssertEqual(outcome, .synced(posted: 1, deleted: 0, received: 2))
        let patches = StubURLProtocol.requests("PATCH")
        XCTAssertEqual(patches.map(\.path), ["/meals/m-tacos"], "one PATCH carries both edits")
        XCTAssertEqual(patches.first?.body?["lastMadeAt"] as? String, "2027-01-15T08:00:00.000Z")
        XCTAssertEqual(patches.first?.body?["nextUp"] as? Bool, true)
        XCTAssertNil(patches.first?.body?["title"])
        XCTAssertEqual(try mealRow("m-tacos")?.pendingPatch, 0)
        XCTAssertEqual(try mealRow("m-tacos")?.nextUp, true)
        XCTAssertEqual(try mealRow("m-chili")?.nextUp, false)
        XCTAssertEqual(try mealRow("m-chili")?.seq, 12)
    }

    // MARK: deletes

    func testShoppingDeleteReplaysAsDELETE() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let item = ShoppingItemRecord(
            id: "sh-3",
            title: "Sponges",
            addedBy: "anne",
            createdAt: listClock,
            syncedAt: listClock
        )
        ctx.insert(item)
        try ctx.save()
        try ListActions.removeShoppingItem(item, in: ctx, now: listClock)
        XCTAssertTrue(item.needsDelete)

        StubURLProtocol.reset { req in
            let row = shoppingJSON(id: "sh-3", title: "Sponges", seq: 10, deleted: true)
            if req.httpMethod == "DELETE" {
                return (200, json(row))
            }
            return (200, listsSyncJSON(cursor: 10, shopping: [row]))
        }
        let outcome = await client.syncNow()
        XCTAssertEqual(outcome, .synced(posted: 0, deleted: 1, received: 1))
        XCTAssertEqual(StubURLProtocol.requests("DELETE").map(\.path), ["/shopping/sh-3"])
        XCTAssertEqual(StubURLProtocol.requests("POST").count, 0, "a removed row is never posted")
        let gone = try XCTUnwrap(try shoppingRow("sh-3"))
        XCTAssertTrue(gone.removed)
        XCTAssertTrue(gone.deleteSynced)

        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 10)) }
        _ = await client.syncNow()
        XCTAssertEqual(StubURLProtocol.requests("DELETE").count, 0, "acknowledged deletes are not replayed")
    }

    func testRemovingARowTheServerNeverSawSendsNothing() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let meal = try XCTUnwrap(try ListActions.addMeal("Sushi bake", tag: "", in: ctx, now: listClock))
        try ListActions.removeMeal(meal, in: ctx, now: listClock)
        XCTAssertTrue(meal.deleteSynced)

        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 7)) }
        let outcome = await client.syncNow()
        XCTAssertEqual(outcome, .synced(posted: 0, deleted: 0, received: 0))
        XCTAssertEqual(StubURLProtocol.requests("POST").count, 0)
        XCTAssertEqual(StubURLProtocol.requests("DELETE").count, 0)
    }

    func testRemovingAProjectCascadesLocallyAndSendsOneDELETE() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let project = ProjectRecord(id: "p-3", title: "Fence", createdAt: listClock, syncedAt: listClock)
        let posts = SubtaskRecord(
            id: "st-a",
            projectId: "p-3",
            title: "Posts",
            sortOrder: 0,
            createdAt: listClock,
            syncedAt: listClock
        )
        let panels = SubtaskRecord(
            id: "st-b",
            projectId: "p-3",
            title: "Panels",
            sortOrder: 1,
            createdAt: listClock,
            syncedAt: listClock
        )
        ctx.insert(project)
        ctx.insert(posts)
        ctx.insert(panels)
        try ctx.save()
        try ListActions.removeProject(project, in: ctx, now: listClock)
        XCTAssertTrue(posts.removed && posts.deleteSynced, "steps are covered by the project's DELETE")
        XCTAssertTrue(project.needsDelete)

        StubURLProtocol.reset { req in
            let steps = [
                subtaskJSON(id: "st-a", projectId: "p-3", title: "Posts", sortOrder: 0, seq: 50, deleted: true),
                subtaskJSON(id: "st-b", projectId: "p-3", title: "Panels", sortOrder: 1, seq: 51, deleted: true),
            ]
            if req.httpMethod == "DELETE" {
                return (
                    200,
                    json(projectJSON(id: "p-3", title: "Fence", seq: 52, deleted: true, subtasks: steps))
                )
            }
            return (
                200,
                listsSyncJSON(
                    cursor: 52,
                    projects: [projectJSON(id: "p-3", title: "Fence", seq: 52, deleted: true)],
                    subtasks: steps
                )
            )
        }
        let outcome = await client.syncNow()
        XCTAssertEqual(outcome, .synced(posted: 0, deleted: 1, received: 3))
        XCTAssertEqual(StubURLProtocol.requests("DELETE").map(\.path), ["/projects/p-3"])
        XCTAssertEqual(try projectRow("p-3")?.seq, 52)
        XCTAssertEqual(try subtaskRow("st-a")?.seq, 50, "the cascade's seqs come back on the response")
        XCTAssertEqual(try ListActions.liveSubtasks(of: "p-3", in: fresh()).count, 0)
        XCTAssertEqual(try state().cursor, 52)
    }
}
