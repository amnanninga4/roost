// The two project fields through a sync pass: the due day and the step owner, each patched alone,
// cleared with null, taken from a delta, and tolerated when an older server leaves the key out.
@testable import Roost
import SwiftData
import XCTest

final class ProjectFieldsSyncTests: ListSyncTestCase {
    func testDueDayPatchSendsOnlyTheDayAndClearingSendsNull() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let project = ProjectRecord(id: "p-1", title: "Garage trash", createdAt: listClock, syncedAt: listClock)
        project.seq = 4
        ctx.insert(project)
        try ctx.save()
        try ListActions.setDueOn(project, "2026-09-20", in: ctx, now: listClock)
        StubURLProtocol.reset { req in
            let row = projectJSON(id: "p-1", title: "Garage trash", dueOn: "2026-09-20", seq: 9, subtasks: [])
            if req.httpMethod == "PATCH" {
                return (200, json(row))
            }
            return (
                200,
                listsSyncJSON(
                    cursor: 9,
                    projects: [projectJSON(id: "p-1", title: "Garage trash", dueOn: "2026-09-20", seq: 9)]
                )
            )
        }
        _ = await client.syncNow()
        let patch = try XCTUnwrap(StubURLProtocol.requests("PATCH").first)
        XCTAssertEqual(patch.path, "/projects/p-1")
        XCTAssertEqual(patch.body?["dueOn"] as? String, "2026-09-20")
        XCTAssertNil(patch.body?["title"], "only the changed field is sent")
        XCTAssertEqual(try projectRow("p-1")?.pendingPatch, 0)

        let again = fresh()
        try ListActions.setDueOn(XCTUnwrap(try projectRow("p-1", in: again)), nil, in: again, now: listClock)
        StubURLProtocol.reset { req in
            if req.httpMethod == "PATCH" {
                return (200, json(projectJSON(id: "p-1", title: "Garage trash", seq: 10, subtasks: [])))
            }
            return (200, listsSyncJSON(cursor: 10))
        }
        _ = await client.syncNow()
        XCTAssertTrue(StubURLProtocol.requests("PATCH").first?.body?["dueOn"] is NSNull, "clearing sends null")
        XCTAssertNil(try projectRow("p-1")?.dueOn)
    }

    func testDeltaCarriesTheDueDayAndAnOlderServerLeavesItNil() async throws {
        try await pairAsAnne()
        StubURLProtocol.reset { _ in
            (
                200,
                listsSyncJSON(
                    cursor: 12,
                    projects: [projectJSON(id: "p-2", title: "Fence", dueOn: "2026-10-01", seq: 12)]
                )
            )
        }
        _ = await client.syncNow()
        XCTAssertEqual(try projectRow("p-2")?.dueOn, "2026-10-01")

        var older = projectJSON(id: "p-3", title: "Old server", seq: 13)
        older.removeValue(forKey: "dueOn")
        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 13, projects: [older])) }
        let outcome = await client.syncNow()
        XCTAssertEqual(outcome, .synced(posted: 0, deleted: 0, received: 1), "a missing key is not a decoding failure")
        XCTAssertNil(try projectRow("p-3")?.dueOn)
    }

    func testAPendingDueDayOutlivesADeltaWithTheServersOlderCopy() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let project = ProjectRecord(
            id: "p-4",
            title: "Shed",
            dueOn: "2026-09-01",
            createdAt: listClock,
            syncedAt: listClock
        )
        project.seq = 5
        ctx.insert(project)
        try ctx.save()
        try ListActions.setDueOn(project, "2026-09-30", in: ctx, now: listClock)
        StubURLProtocol.reset { req in
            if req.httpMethod == "PATCH" {
                return (503, json(["error": "later"])) // the edit stays queued
            }
            return (
                200,
                listsSyncJSON(cursor: 6, projects: [projectJSON(id: "p-4", title: "Shed", dueOn: "2026-09-01", seq: 6)])
            )
        }
        _ = await client.syncNow()
        XCTAssertEqual(try projectRow("p-4")?.dueOn, "2026-09-30", "the local edit wins until it is sent")
        XCTAssertEqual(try projectRow("p-4")?.pendingFields, [.dueOn])
    }

    func testAStepAddedWithAnOwnerPostsTheOwnerAndA201ClearsIt() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let project = ProjectRecord(id: "p-5", title: "Garage", createdAt: listClock, syncedAt: listClock)
        project.seq = 3
        ctx.insert(project)
        try ctx.save()
        let step = try XCTUnwrap(try ListActions.addSubtask(
            "Bag it",
            to: project,
            assignee: "wes",
            in: ctx,
            now: listClock
        ))
        let id = step.id
        StubURLProtocol.reset { req in
            let row = subtaskJSON(id: id, projectId: "p-5", title: "Bag it", assignee: "wes", seq: 7)
            if req.httpMethod == "POST" {
                return (201, json(row))
            }
            return (200, listsSyncJSON(cursor: 7, subtasks: [row]))
        }
        _ = await client.syncNow()
        let post = try XCTUnwrap(StubURLProtocol.requests("POST").first)
        XCTAssertEqual(post.path, "/projects/p-5/subtasks")
        XCTAssertEqual(post.body?["assignee"] as? String, "wes")
        XCTAssertEqual(StubURLProtocol.requests("PATCH").count, 0, "the create carried the owner")
        XCTAssertEqual(try subtaskRow(id)?.pendingPatch, 0)
    }

    func testOwnerPatchSendsOnlyTheOwnerAndTheDoerStaysWhoeverTapped() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let step = SubtaskRecord(
            id: "st-9",
            projectId: "p-5",
            title: "Haul it",
            sortOrder: 1,
            createdAt: listClock,
            syncedAt: listClock
        )
        step.seq = 8
        ctx.insert(step)
        try ctx.save()
        try ListActions.setAssignee(step, "wes", in: ctx, now: listClock)
        StubURLProtocol.reset { req in
            let row = subtaskJSON(id: "st-9", projectId: "p-5", title: "Haul it", sortOrder: 1, assignee: "wes", seq: 9)
            if req.httpMethod == "PATCH" {
                return (200, json(row))
            }
            return (200, listsSyncJSON(cursor: 9, subtasks: [row]))
        }
        _ = await client.syncNow()
        let patch = try XCTUnwrap(StubURLProtocol.requests("PATCH").first)
        XCTAssertEqual(patch.path, "/subtasks/st-9")
        XCTAssertEqual(patch.body?["assignee"] as? String, "wes")
        XCTAssertNil(patch.body?["done"])
        XCTAssertNil(patch.body?["title"])

        StubURLProtocol.reset { _ in
            (200, listsSyncJSON(cursor: 10, subtasks: [
                subtaskJSON(
                    id: "st-9",
                    projectId: "p-5",
                    title: "Haul it",
                    sortOrder: 1,
                    done: true,
                    doneBy: "anne",
                    doneAt: listStamp,
                    assignee: "wes",
                    seq: 10
                ),
            ]))
        }
        _ = await client.syncNow()
        let row = try XCTUnwrap(try subtaskRow("st-9"))
        XCTAssertEqual(row.assignee, "wes")
        XCTAssertEqual(row.doneBy, "anne", "the owner and the doer are two facts")

        var older = subtaskJSON(id: "st-old", projectId: "p-5", title: "Old server", seq: 11)
        older.removeValue(forKey: "assignee")
        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 11, subtasks: [older])) }
        let syncResult = await client.syncNow()
        XCTAssertEqual(syncResult, .synced(posted: 0, deleted: 0, received: 1))
        XCTAssertNil(try subtaskRow("st-old")?.assignee)
    }
}
