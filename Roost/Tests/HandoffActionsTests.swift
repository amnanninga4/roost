// The local writes a tap makes: offering a turn, answering one, taking an offer back, and clearing the
// "Wes said no" line. Same functions the screen calls.
@testable import Roost
import RoostCore
import SwiftData
import XCTest

final class HandoffActionsTests: XCTestCase {
    private let cal = HouseholdCalendar()
    private lazy var monday = cal.date(year: 2026, month: 9, day: 14, hour: 10)
    private let laundry = Chore(id: "laundry", title: "Laundry", cadence: .weekly, fixedAssignee: .anne,
                                category: .chore)
    private let garbage = Chore(id: "garbage", title: "Garbage out", cadence: .weekly, fixedAssignee: .wes,
                                category: .chore)

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: RoostSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    private func rules(_ handoffs: [Handoff] = []) -> HandoffRules {
        HandoffRules(
            scheduler: Scheduler(
                chores: [laundry, garbage], activeFrom: cal.startOfDay(monday), calendar: cal
            ),
            handoffs: handoffs
        )
    }

    private func rows() throws -> [HandoffRecord] {
        try context.fetch(FetchDescriptor<HandoffRecord>())
    }

    func testOfferingInsertsAPendingRowForTheCurrentPeriod() throws {
        let record = try XCTUnwrap(HandoffActions.offer(
            laundry, from: .anne, to: .wes, rules: rules(), on: monday, in: context
        ))
        XCTAssertEqual(record.choreId, "laundry")
        XCTAssertEqual(record.fromPerson, "anne")
        XCTAssertEqual(record.toPerson, "wes")
        XCTAssertEqual(record.state, "pending")
        XCTAssertEqual(record.cadence, "weekly")
        XCTAssertEqual(record.periodIndex, cal.periodIndex(.weekly, containing: monday))
        XCTAssertNil(record.syncedAt, "queued for POST /handoffs")
        XCTAssertFalse(record.reachedServer)
        // A client-generated UUID, so a replayed POST is a 200 on the same row rather than a second one.
        XCTAssertEqual(record.id.count, 36)
        XCTAssertNotNil(UUID(uuidString: record.id))
        XCTAssertEqual(try rows().count, 1)
    }

    /// HandoffRules owns eligibility, and the action asks it rather than deciding for itself.
    func testOfferingSomethingThatIsNotYoursDoesNothing() throws {
        XCTAssertNil(try HandoffActions.offer(
            garbage, from: .anne, to: .wes, rules: rules(), on: monday, in: context
        ))
        XCTAssertTrue(try rows().isEmpty)
    }

    func testASecondOfferForTheSamePeriodDoesNothing() throws {
        let first = try XCTUnwrap(HandoffActions.offer(
            laundry, from: .anne, to: .wes, rules: rules(), on: monday, in: context
        ))
        let open = try XCTUnwrap(first.toHandoff())
        XCTAssertNil(try HandoffActions.offer(
            laundry, from: .anne, to: .wes, rules: rules([open]), on: monday, in: context
        ))
        XCTAssertEqual(try rows().count, 1)
    }

    func testAnsweringTakesEffectAtOnceAndQueuesTheAnswer() throws {
        let record = HandoffRecord(
            id: "h-1", choreId: "laundry", fromPerson: "wes", toPerson: "anne", periodIndex: 100,
            cadence: "weekly", createdAt: monday, syncedAt: monday
        )
        context.insert(record)
        try HandoffActions.answer("h-1", as: .accept, in: context, now: monday)

        XCTAssertEqual(record.state, "accepted", "the item moves columns under the finger")
        XCTAssertEqual(record.queuedAnswer, .accept)
        XCTAssertTrue(record.needsAnswer)
    }

    func testAnsweringSomethingAlreadyAnsweredChangesNothing() throws {
        let record = HandoffRecord(
            id: "h-1", choreId: "laundry", fromPerson: "wes", toPerson: "anne", periodIndex: 100,
            cadence: "weekly", state: "declined", createdAt: monday, syncedAt: monday
        )
        context.insert(record)
        try HandoffActions.answer("h-1", as: .accept, in: context, now: monday)
        XCTAssertEqual(record.state, "declined")
        XCTAssertNil(record.pendingAnswer)
    }

    func testWithdrawingDeletesAnOfferThatNeverLeftThePhone() throws {
        let record = try XCTUnwrap(HandoffActions.offer(
            laundry, from: .anne, to: .wes, rules: rules(), on: monday, in: context
        ))
        try HandoffActions.withdraw(record.id, in: context)
        XCTAssertTrue(try rows().isEmpty, "nothing on the server knows about it, so nothing is sent")
    }

    /// There is no withdraw endpoint, so a synced offer cannot be taken back at all — the UI does not
    /// offer it, and the action refuses it too.
    func testWithdrawingASyncedOfferDoesNothing() throws {
        let record = HandoffRecord(
            id: "h-1", choreId: "laundry", fromPerson: "anne", toPerson: "wes", periodIndex: 100,
            cadence: "weekly", createdAt: monday, syncedAt: monday
        )
        context.insert(record)
        try context.save()
        try HandoffActions.withdraw("h-1", in: context)
        XCTAssertEqual(try rows().count, 1)
        XCTAssertFalse(record.removed)
    }

    func testClearingNoticesMarksTheAnsweredOnesAndLeavesPendingAlone() throws {
        let declined = HandoffRecord(
            id: "h-no", choreId: "laundry", fromPerson: "anne", toPerson: "wes", periodIndex: 100,
            cadence: "weekly", state: "declined", createdAt: monday, syncedAt: monday
        )
        let refused = HandoffRecord(
            id: "h-bad", choreId: "mop", fromPerson: "anne", toPerson: "wes", periodIndex: 50,
            cadence: "biweekly", createdAt: monday
        )
        refused.rejected = true
        let waiting = HandoffRecord(
            id: "h-wait", choreId: "dishes", fromPerson: "anne", toPerson: "wes", periodIndex: 250,
            cadence: "daily", createdAt: monday, syncedAt: monday
        )
        let his = HandoffRecord(
            id: "h-his", choreId: "garbage", fromPerson: "wes", toPerson: "anne", periodIndex: 100,
            cadence: "weekly", state: "declined", createdAt: monday, syncedAt: monday
        )
        for record in [declined, refused, waiting, his] {
            context.insert(record)
        }
        try context.save()

        try HandoffActions.clearNotices(for: .anne, in: context)
        XCTAssertTrue(declined.noticeCleared)
        XCTAssertTrue(refused.noticeCleared)
        XCTAssertFalse(waiting.noticeCleared, "clearing a pending offer would swallow the answer to come")
        XCTAssertFalse(his.noticeCleared, "his notes are not hers to read")
    }
}
