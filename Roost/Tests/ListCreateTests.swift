// The creates of the list sync: a shopping item, a meal, a project with its first steps in one POST,
// and a step added to a project the server already has. Fixtures and the shared setup live in
// ListSyncTestCase.swift; edits, removals, and the failure modes are in ListReplayTests.swift.
@testable import Roost
import SwiftData
import XCTest

final class ListCreateTests: ListSyncTestCase {
    // MARK: creates

    func testLocalShoppingAddIsPostedOnceAndMarkedSynced() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        // Added before pairing knows who we are: addedBy is blank until the server stamps it from the token.
        let item = try XCTUnwrap(try ListActions.addShoppingItem("  Oat milk ", by: nil, in: ctx, now: listClock))
        let id = item.id
        XCTAssertEqual(item.title, "Oat milk")
        XCTAssertEqual(item.addedBy, "")
        XCTAssertTrue(item.needsPost)

        StubURLProtocol.reset { req in
            if req.httpMethod == "POST" {
                return (201, json(shoppingJSON(id: id, title: "Oat milk", seq: 8)))
            }
            return (200, listsSyncJSON(cursor: 8, shopping: [shoppingJSON(id: id, title: "Oat milk", seq: 8)]))
        }
        let first = await client.syncNow()
        XCTAssertEqual(first, .synced(posted: 1, deleted: 0, received: 1))
        let posts = StubURLProtocol.requests("POST")
        XCTAssertEqual(posts.map(\.path), ["/shopping"])
        XCTAssertEqual(posts.first?.body?["id"] as? String, id)
        XCTAssertEqual(posts.first?.body?["title"] as? String, "Oat milk")
        let synced = try XCTUnwrap(try shoppingRow(id))
        XCTAssertNotNil(synced.syncedAt)
        XCTAssertEqual(synced.seq, 8)
        XCTAssertEqual(synced.addedBy, "anne", "the server's stamp replaces the blank")
        XCTAssertEqual(try state().cursor, 8)

        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 8)) }
        let second = await client.syncNow()
        XCTAssertEqual(second, .synced(posted: 0, deleted: 0, received: 0))
        XCTAssertEqual(StubURLProtocol.requests("POST").count, 0, "already synced rows are not re-posted")
    }

    func testLocalMealAddCarriesTagAndIsPostedOnce() async throws {
        try await pairAsAnne()
        let meal = try XCTUnwrap(try ListActions.addMeal("Tacos", tag: " Weeknight ", in: fresh(), now: listClock))
        let id = meal.id
        XCTAssertEqual(meal.tag, "Weeknight")

        StubURLProtocol.reset { req in
            if req
                .httpMethod == "POST"
            {
                return (201, json(mealJSON(id: id, title: "Tacos", tag: "Weeknight", seq: 3)))
            }
            return (200, listsSyncJSON(cursor: 3, meals: [mealJSON(id: id, title: "Tacos", tag: "Weeknight", seq: 3)]))
        }
        let outcome = await client.syncNow()
        XCTAssertEqual(outcome, .synced(posted: 1, deleted: 0, received: 1))
        let post = try XCTUnwrap(StubURLProtocol.requests("POST").first)
        XCTAssertEqual(post.path, "/meals")
        XCTAssertEqual(post.body?["tag"] as? String, "Weeknight")
        XCTAssertEqual(post.body?["nextUp"] as? Bool, false)
        XCTAssertTrue(post.body?["lastMadeAt"] is NSNull, "unset lastMadeAt is sent as null")
        XCTAssertEqual(try mealRow(id)?.seq, 3)
        XCTAssertNotNil(try mealRow(id)?.syncedAt)
    }

    func testLocalProjectWithStepsIsPostedInOneRequest() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let project = try XCTUnwrap(try ListActions.startProject(
            "Garage",
            steps: ["Sort boxes", "  ", "Sweep"],
            in: ctx,
            now: listClock
        ))
        let steps = try ListActions.liveSubtasks(of: project.id, in: ctx)
        XCTAssertEqual(steps.map(\.title), ["Sort boxes", "Sweep"], "blank lines are skipped")
        XCTAssertEqual(steps.map(\.sortOrder), [0, 1])
        let (pid, sortId, sweepId) = (project.id, steps[0].id, steps[1].id)

        StubURLProtocol.reset { req in
            let rows = [
                subtaskJSON(id: sortId, projectId: pid, title: "Sort boxes", sortOrder: 0, seq: 31),
                subtaskJSON(id: sweepId, projectId: pid, title: "Sweep", sortOrder: 1, seq: 32),
            ]
            if req.httpMethod == "POST" {
                return (
                    201,
                    json(projectJSON(id: pid, title: "Garage", seq: 30, subtasks: rows))
                )
            }
            return (
                200,
                listsSyncJSON(cursor: 32, projects: [projectJSON(id: pid, title: "Garage", seq: 30)], subtasks: rows)
            )
        }
        let outcome = await client.syncNow()
        XCTAssertEqual(outcome, .synced(posted: 3, deleted: 0, received: 3))
        let posts = StubURLProtocol.requests("POST")
        XCTAssertEqual(posts.map(\.path), ["/projects"], "the steps ride the project's POST, not their own")
        XCTAssertEqual(posts.first?.body?["title"] as? String, "Garage")
        let seeds = posts.first?.body?["subtasks"] as? [[String: Any]]
        XCTAssertEqual(seeds?.map { $0["id"] as? String }, [sortId, sweepId])
        XCTAssertEqual(seeds?.map { $0["title"] as? String }, ["Sort boxes", "Sweep"])
        XCTAssertEqual(try projectRow(pid)?.seq, 30)
        XCTAssertEqual(try subtaskRow(sortId)?.seq, 31)
        XCTAssertEqual(try subtaskRow(sweepId)?.seq, 32)
        XCTAssertNotNil(try subtaskRow(sweepId)?.syncedAt)

        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 32)) }
        _ = await client.syncNow()
        XCTAssertEqual(StubURLProtocol.requests("POST").count, 0)
    }

    func testStepAddedToASyncedProjectPostsToTheProjectRouteAndDonePatches() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let project = ProjectRecord(id: "p-2", title: "Plan trip", createdAt: listClock, syncedAt: listClock)
        ctx.insert(project)
        try ctx.save()
        let step = try XCTUnwrap(try ListActions.addSubtask("Book flights", to: project, in: ctx, now: listClock))
        let stepId = step.id
        XCTAssertEqual(step.sortOrder, 0)

        StubURLProtocol.reset { req in
            if req.httpMethod == "POST" {
                return (
                    201,
                    json(subtaskJSON(id: stepId, projectId: "p-2", title: "Book flights", seq: 40))
                )
            }
            return (
                200,
                listsSyncJSON(
                    cursor: 40,
                    subtasks: [subtaskJSON(id: stepId, projectId: "p-2", title: "Book flights", seq: 40)]
                )
            )
        }
        _ = await client.syncNow()
        let post = try XCTUnwrap(StubURLProtocol.requests("POST").first)
        XCTAssertEqual(post.path, "/projects/p-2/subtasks")
        XCTAssertEqual(post.body?["id"] as? String, stepId)
        XCTAssertEqual(post.body?["sortOrder"] as? Int, 0)
        XCTAssertEqual(try subtaskRow(stepId)?.seq, 40)

        // Check it off: only `done` travels.
        let editCtx = fresh()
        try ListActions.setDone(
            XCTUnwrap(try subtaskRow(stepId, in: editCtx)),
            true,
            by: "anne",
            in: editCtx,
            now: listClock
        )
        StubURLProtocol.reset { req in
            if req.httpMethod == "PATCH" {
                return (
                    200,
                    json(subtaskJSON(
                        id: stepId,
                        projectId: "p-2",
                        title: "Book flights",
                        done: true,
                        doneBy: "anne",
                        doneAt: listStamp,
                        seq: 41
                    ))
                )
            }
            return (200, listsSyncJSON(cursor: 41))
        }
        let outcome = await client.syncNow()
        XCTAssertEqual(outcome, .synced(posted: 1, deleted: 0, received: 0))
        let patch = try XCTUnwrap(StubURLProtocol.requests("PATCH").first)
        XCTAssertEqual(patch.path, "/subtasks/\(stepId)")
        XCTAssertEqual(patch.body?["done"] as? Bool, true)
        XCTAssertNil(patch.body?["title"])
        XCTAssertNil(patch.body?["sortOrder"])
        let done = try XCTUnwrap(try subtaskRow(stepId))
        XCTAssertEqual(done.pendingPatch, 0)
        XCTAssertEqual(done.doneBy, "anne")
        XCTAssertEqual(done.doneAt, SyncAPI.parseDate(listStamp), "the server's stamp replaces the local preview")
        XCTAssertEqual(done.seq, 41)
    }
}
