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
            return (200, listsSyncJSON(cursor: 9, projects: [projectJSON(id: "p-1", title: "Garage trash", dueOn: "2026-09-20", seq: 9)]))
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
            (200, listsSyncJSON(cursor: 12, projects: [projectJSON(id: "p-2", title: "Fence", dueOn: "2026-10-01", seq: 12)]))
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
        let project = ProjectRecord(id: "p-4", title: "Shed", dueOn: "2026-09-01", createdAt: listClock, syncedAt: listClock)
        project.seq = 5
        ctx.insert(project)
        try ctx.save()
        try ListActions.setDueOn(project, "2026-09-30", in: ctx, now: listClock)
        StubURLProtocol.reset { req in
            if req.httpMethod == "PATCH" {
                return (503, json(["error": "later"])) // the edit stays queued
            }
            return (200, listsSyncJSON(cursor: 6, projects: [projectJSON(id: "p-4", title: "Shed", dueOn: "2026-09-01", seq: 6)]))
        }
        _ = await client.syncNow()
        XCTAssertEqual(try projectRow("p-4")?.dueOn, "2026-09-30", "the local edit wins until it is sent")
        XCTAssertEqual(try projectRow("p-4")?.pendingFields, [.dueOn])
    }
}
