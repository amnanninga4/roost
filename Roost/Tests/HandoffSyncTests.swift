// The handoff queues against a stub server: an offer goes out once, an answer goes out once, and every
// way the server can say no lands where ListSync's policy says it should.
@testable import Roost
import RoostCore
import SwiftData
import XCTest

final class HandoffSyncTests: ListSyncTestCase {
    private let cal = HouseholdCalendar()

    /// A pending offer made on this phone and not yet sent.
    private func queueOffer(
        id: String = "h-1", choreId: String = "laundry", from: Person = .anne, to: Person = .wes,
        periodIndex: Int = 100, cadence: Cadence = .weekly
    ) throws -> HandoffRecord {
        let context = fresh()
        let record = HandoffRecord(
            id: id,
            choreId: choreId,
            fromPerson: from.rawValue,
            toPerson: to.rawValue,
            periodIndex: periodIndex,
            cadence: cadence.rawValue,
            createdAt: listClock
        )
        context.insert(record)
        try context.save()
        return record
    }

    /// A synced offer from the other person, with this phone's answer queued on it.
    private func queueAnswer(as decision: HandoffRules.Decision, id: String = "h-2") throws -> HandoffRecord {
        let context = fresh()
        let record = HandoffRecord(
            id: id,
            choreId: "laundry",
            fromPerson: Person.wes.rawValue,
            toPerson: Person.anne.rawValue,
            periodIndex: 100,
            cadence: Cadence.weekly.rawValue,
            createdAt: listClock,
            syncedAt: listClock
        )
        record.seq = 5
        context.insert(record)
        try HandoffActions.answer(id, as: decision, in: context, now: listClock)
        return record
    }

    // MARK: - the offer

    func testAQueuedOfferIsPostedOnceAndMarkedSynced() async throws {
        try await pairAsAnne()
        _ = try queueOffer()

        StubURLProtocol.reset { request in
            if request.url?.path == "/handoffs" {
                return (201, json(handoffJSON(
                    id: "h-1", choreId: "laundry", from: "anne", to: "wes", periodIndex: 100, seq: 11
                )))
            }
            return (200, listsSyncJSON(cursor: 11))
        }
        let first = await client.syncNow()
        XCTAssertEqual(first, .synced(posted: 1, deleted: 0, received: 0))

        let row = try XCTUnwrap(handoffRow("h-1"))
        XCTAssertNotNil(row.syncedAt)
        XCTAssertEqual(row.seq, 11)
        XCTAssertFalse(row.rejected)

        let posts = StubURLProtocol.requests("POST").filter { $0.path == "/handoffs" }
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts.first?.body?["id"] as? String, "h-1")
        XCTAssertEqual(posts.first?.body?["choreId"] as? String, "laundry")
        XCTAssertEqual(posts.first?.body?["to"] as? String, "wes")
        XCTAssertEqual(posts.first?.body?["periodIndex"] as? Int, 100)
        XCTAssertEqual(posts.first?.body?["cadence"] as? String, "weekly")
        XCTAssertEqual(posts.first?.authorization, "Bearer anne-token-0123456789abcdef")

        // A second pass has nothing to send: the row is synced.
        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 11)) }
        _ = await client.syncNow()
        XCTAssertTrue(StubURLProtocol.requests("POST").isEmpty)
    }

    /// 403 is the server saying this is not your chore to give away. It will say the same next time, so
    /// the row is kept, marked, and never sent again — even though a 403 stays retryable everywhere else.
    func testA403OnAnOfferIsFinalAndNeverRetried() async throws {
        try await pairAsAnne()
        _ = try queueOffer()
        try await assertOfferRefused(status: 403, message: "only the current owner may offer this chore")
    }

    func testA409OnAnOfferIsFinal() async throws {
        try await pairAsAnne()
        _ = try queueOffer()
        try await assertOfferRefused(status: 409, message: "an open handoff already exists")
    }

    func testA400OnAnOfferIsFinal() async throws {
        try await pairAsAnne()
        _ = try queueOffer()
        try await assertOfferRefused(status: 400, message: "periodIndex cannot be in the future")
    }

    private func assertOfferRefused(status: Int, message: String) async throws {
        StubURLProtocol.reset { request in
            if request.url?.path == "/handoffs" {
                return (status, json(["error": message]))
            }
            return (200, listsSyncJSON(cursor: 12))
        }
        let outcome = await client.syncNow()
        // The pull still runs: one refused row is not a failed pass.
        XCTAssertEqual(outcome, .synced(posted: 0, deleted: 0, received: 0))

        let row = try XCTUnwrap(handoffRow("h-1"))
        XCTAssertTrue(row.rejected, "a refused offer is kept locally and marked")
        XCTAssertNil(row.syncedAt)
        XCTAssertEqual(try state().cursor, 12)

        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 12)) }
        _ = await client.syncNow()
        XCTAssertTrue(StubURLProtocol.requests("POST").isEmpty, "a rejected offer is never retried")
    }

    func testA503OnAnOfferKeepsItQueuedAndStillPulls() async throws {
        try await pairAsAnne()
        _ = try queueOffer()

        StubURLProtocol.reset { request in
            if request.url?.path == "/handoffs" {
                return (503, Data())
            }
            return (200, listsSyncJSON(cursor: 13))
        }
        _ = await client.syncNow()

        let row = try XCTUnwrap(handoffRow("h-1"))
        XCTAssertFalse(row.rejected)
        XCTAssertNil(row.syncedAt, "still queued for the next pass")
        XCTAssertEqual(try state().cursor, 13, "the pull went ahead")
    }

    func testADeadConnectionEndsThePassWithTheOfferIntact() async throws {
        try await pairAsAnne(cursor: 7)
        _ = try queueOffer()

        StubURLProtocol.reset { _ in (StubURLProtocol.connectionLost, Data()) }
        let outcome = await client.syncNow()
        guard case .failed = outcome else {
            return XCTFail("a transport failure ends the pass: \(outcome)")
        }
        let row = try XCTUnwrap(handoffRow("h-1"))
        XCTAssertFalse(row.rejected)
        XCTAssertNil(row.syncedAt)
        XCTAssertEqual(try state().cursor, 7, "the cursor cannot move when the pull never happened")
    }

    // MARK: - the answer

    func testAQueuedAcceptIsPostedToTheAcceptRoute() async throws {
        try await pairAsAnne()
        _ = try queueAnswer(as: .accept)

        StubURLProtocol.reset { request in
            if request.url?.path == "/handoffs/h-2/accept" {
                return (200, json(handoffJSON(
                    id: "h-2", choreId: "laundry", from: "wes", to: "anne", periodIndex: 100,
                    state: "accepted", seq: 21
                )))
            }
            return (200, listsSyncJSON(cursor: 21))
        }
        _ = await client.syncNow()

        let row = try XCTUnwrap(handoffRow("h-2"))
        XCTAssertNil(row.pendingAnswer, "the answer has gone out")
        XCTAssertEqual(row.state, "accepted")
        XCTAssertEqual(row.seq, 21)
        XCTAssertEqual(StubURLProtocol.requests("POST").map(\.path), ["/handoffs/h-2/accept"])
    }

    func testAQueuedDeclineIsPostedToTheDeclineRoute() async throws {
        try await pairAsAnne()
        _ = try queueAnswer(as: .decline)

        StubURLProtocol.reset { request in
            if request.url?.path == "/handoffs/h-2/decline" {
                return (200, json(handoffJSON(
                    id: "h-2", choreId: "laundry", from: "wes", to: "anne", periodIndex: 100,
                    state: "declined", seq: 22
                )))
            }
            return (200, listsSyncJSON(cursor: 22))
        }
        _ = await client.syncNow()

        let row = try XCTUnwrap(handoffRow("h-2"))
        XCTAssertNil(row.pendingAnswer)
        XCTAssertEqual(row.state, "declined")
        XCTAssertEqual(StubURLProtocol.requests("POST").map(\.path), ["/handoffs/h-2/decline"])
    }

    /// A 409 reloads the row rather than rejecting it: the server has this handoff, only our answer lost.
    func testA409OnAnAnswerTakesTheServersStateBack() async throws {
        try await pairAsAnne()
        _ = try queueAnswer(as: .accept)

        StubURLProtocol.reset { request in
            if request.url?.path.hasPrefix("/handoffs/") == true {
                return (409, json([
                    "error": "handoff period has ended",
                    "handoff": handoffJSON(
                        id: "h-2", choreId: "laundry", from: "wes", to: "anne", periodIndex: 100,
                        state: "expired", seq: 23
                    ),
                ]))
            }
            return (200, listsSyncJSON(cursor: 23))
        }
        _ = await client.syncNow()

        let row = try XCTUnwrap(handoffRow("h-2"))
        XCTAssertNil(row.pendingAnswer, "the answer is dropped, never retried")
        XCTAssertEqual(row.state, "expired", "the row shows what the server says it is")
        XCTAssertFalse(row.rejected, "the server has this row: rejecting it would hide a real handoff")

        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 23)) }
        _ = await client.syncNow()
        XCTAssertTrue(StubURLProtocol.requests("POST").isEmpty)
    }

    func testA403OnAnAnswerDropsTheAnswerAndKeepsTheRow() async throws {
        try await pairAsAnne()
        _ = try queueAnswer(as: .decline)

        StubURLProtocol.reset { request in
            if request.url?.path.hasPrefix("/handoffs/") == true {
                return (403, json(["error": "only the person offered the handoff may answer"]))
            }
            return (200, listsSyncJSON(cursor: 24))
        }
        _ = await client.syncNow()

        let row = try XCTUnwrap(handoffRow("h-2"))
        XCTAssertNil(row.pendingAnswer)
        XCTAssertFalse(row.rejected)
    }

    // MARK: - the delta

    func testTheDeltaUpsertsByIdAndAdvancesTheCursorOnce() async throws {
        try await pairAsAnne(cursor: 0)

        StubURLProtocol.reset { _ in
            (200, listsSyncJSON(cursor: 31, handoffs: [
                handoffJSON(id: "h-9", choreId: "laundry", from: "anne", to: "wes", periodIndex: 100, seq: 30),
                handoffJSON(
                    id: "h-10", choreId: "mop-floors", from: "wes", to: "anne", periodIndex: 50,
                    cadence: "biweekly", state: "accepted", seq: 31
                ),
            ]))
        }
        _ = await client.syncNow()

        XCTAssertEqual(try allHandoffs().map(\.id).sorted(), ["h-10", "h-9"])
        let accepted = try XCTUnwrap(handoffRow("h-10"))
        XCTAssertEqual(accepted.state, "accepted")
        XCTAssertEqual(accepted.fromPerson, "wes")
        XCTAssertEqual(accepted.toPerson, "anne")
        XCTAssertEqual(accepted.cadence, "biweekly")
        XCTAssertEqual(accepted.periodIndex, 50)
        XCTAssertNotNil(accepted.syncedAt)
        // The cursor is written after every row above is in the store, so it can never skip one.
        XCTAssertEqual(try state().cursor, 31)

        // Replay of the same delta: the same two rows, moved on, not duplicated.
        StubURLProtocol.reset { _ in
            (200, listsSyncJSON(cursor: 32, handoffs: [
                handoffJSON(
                    id: "h-9", choreId: "laundry", from: "anne", to: "wes", periodIndex: 100,
                    state: "declined", seq: 32
                ),
            ]))
        }
        _ = await client.syncNow()
        XCTAssertEqual(try allHandoffs().count, 2)
        XCTAssertEqual(try handoffRow("h-9")?.state, "declined")
        XCTAssertEqual(try state().cursor, 32)
    }

    func testADeletedDeltaRowIsRemovedLocally() async throws {
        try await pairAsAnne(cursor: 0)
        StubURLProtocol.reset { _ in
            (200, listsSyncJSON(cursor: 40, handoffs: [
                handoffJSON(
                    id: "h-11", choreId: "laundry", from: "anne", to: "wes", periodIndex: 100,
                    seq: 40, deleted: true
                ),
            ]))
        }
        _ = await client.syncNow()

        let row = try XCTUnwrap(handoffRow("h-11"))
        XCTAssertTrue(row.removed)
        XCTAssertTrue(row.deleteSynced, "nothing is sent back: there is no DELETE /handoffs")
        XCTAssertNil(try row.toHandoff(), "a removed row never reaches RoostCore")
    }

    /// The one field a delta must not clobber: a local answer that has not gone out yet.
    func testADeltaLeavesAQueuedAnswerAlone() async throws {
        try await pairAsAnne(cursor: 0)
        _ = try queueAnswer(as: .accept)

        StubURLProtocol.reset { request in
            if request.url?.path.hasPrefix("/handoffs/") == true {
                return (503, Data()) // the answer stays queued
            }
            return (200, listsSyncJSON(cursor: 41, handoffs: [
                handoffJSON(
                    id: "h-2", choreId: "laundry", from: "wes", to: "anne", periodIndex: 100,
                    state: "pending", seq: 41
                ),
            ]))
        }
        _ = await client.syncNow()

        let row = try XCTUnwrap(handoffRow("h-2"))
        XCTAssertEqual(row.state, "accepted", "the local answer outlives the server's older copy")
        XCTAssertEqual(row.queuedAnswer, .accept)
        XCTAssertEqual(row.seq, 41)
    }
}
