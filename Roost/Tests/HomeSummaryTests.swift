// The Home screen's words, tested without a simulator. Every sentence state the screen can
// reach has a case here, because the sentence replaces the word "Today" as the only thing
// orienting the reader — a wrong one is worse than a blank one.
@testable import Roost
import RoostCore
import XCTest

final class HomeSummaryTests: XCTestCase {
    private let noDoors = HomeSummary.DoorCounts(shopping: 0, meals: 0, projects: 0, wishlist: 0)

    private func plan(anne: Int, wes: Int) -> TodayPlan {
        TodayPlanTestBuilder.plan(anne: anne, wes: wes)
    }

    func testSharedRosterShowsTogetherChoreOnceWithoutChangingPersonalCounts() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-21T17:00:00Z"))
        let chore = Chore(id: "together", title: "Clean the fridge", cadence: .daily, category: .chore, together: true)
        let plan = TodayPlanner.plan(chores: [chore], completions: [], asOf: now, activeFrom: now)
        let summary = HomeSummary(plan: plan, me: .anne, doorCounts: noDoors)
        XCTAssertEqual(summary.columns.map(\.dueCount), [1, 1])
        XCTAssertEqual(summary.openRows.map(\.chore.id), ["together"])
    }

    func testSharedRosterPutsTodayBeforeAnEarlyWeeklyWindow() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-21T17:00:00Z"))
        let chores = [
            Chore(id: "later", title: "Weekly", cadence: .weekly, fixedAssignee: .anne, category: .chore),
            Chore(id: "today", title: "Daily", cadence: .daily, fixedAssignee: .wes, category: .chore),
        ]
        let plan = TodayPlanner.plan(chores: chores, completions: [], asOf: now, activeFrom: now)
        let summary = HomeSummary(plan: plan, me: .anne, doorCounts: noDoors)
        XCTAssertEqual(summary.openRows.map(\.chore.id), ["today", "later"])
    }

    func testBothOweShowsTheSplit() {
        let summary = HomeSummary(plan: plan(anne: 4, wes: 5), me: .wes, doorCounts: noDoors)
        XCTAssertEqual(summary.sentence, "5 for you, 4 for Anne.")
    }

    func testSplitReadsFromTheOtherPhoneToo() {
        let summary = HomeSummary(plan: plan(anne: 4, wes: 5), me: .anne, doorCounts: noDoors)
        XCTAssertEqual(summary.sentence, "4 for you, 5 for Wes.")
    }

    func testClearForYouNamesTheOtherPersonsRemainder() {
        let summary = HomeSummary(plan: plan(anne: 4, wes: 0), me: .wes, doorCounts: noDoors)
        XCTAssertEqual(summary.sentence, "Nothing left for you. Anne still has 4.")
    }

    func testBothClearIsAllCaughtUp() {
        let summary = HomeSummary(plan: plan(anne: 0, wes: 0), me: .wes, doorCounts: noDoors)
        XCTAssertEqual(summary.sentence, "All caught up.")
    }

    func testUnpairedPhoneFallsBackToNothingDue() {
        let summary = HomeSummary(plan: plan(anne: 0, wes: 0), me: nil, doorCounts: noDoors)
        XCTAssertEqual(summary.sentence, "Nothing due today")
    }

    func testColumnsLeadWithThisPhone() {
        let summary = HomeSummary(plan: plan(anne: 4, wes: 5), me: .wes, doorCounts: noDoors)
        XCTAssertEqual(summary.columns.map(\.person), [.wes, .anne])
        XCTAssertEqual(summary.columns.map(\.dueCount), [5, 4])
        XCTAssertEqual(summary.columns.map(\.isMine), [true, false])
    }

    func testColumnsOnTheOtherPhoneLeadWithAnne() {
        let summary = HomeSummary(plan: plan(anne: 4, wes: 5), me: .anne, doorCounts: noDoors)
        XCTAssertEqual(summary.columns.map(\.person), [.anne, .wes])
        XCTAssertTrue(summary.columns[0].isMine)
    }

    /// A door is always shown. Its count is shown only when the room holds something — the
    /// spec's hide rule applies to the number, not to the door.
    func testEmptyRoomsShowNoCount() {
        let summary = HomeSummary(plan: plan(anne: 0, wes: 0), me: .wes, doorCounts: noDoors)
        XCTAssertEqual(summary.doors.count, 4)
        XCTAssertTrue(summary.doors.allSatisfy { $0.count == nil })
    }

    func testDoorsCarryTheirCountsWhenTheRoomsHaveContent() {
        let counts = HomeSummary.DoorCounts(shopping: 3, meals: 0, projects: 1, wishlist: 0)
        let summary = HomeSummary(plan: plan(anne: 0, wes: 0), me: .wes, doorCounts: counts)
        XCTAssertEqual(summary.doors.map(\.count), [3, nil, 1, nil])
        XCTAssertEqual(summary.doors.map(\.title), ["Shopping", "Meals", "Projects", "Wishlist"])
    }
}

/// Builds a `TodayPlan` with a chosen number of due rows per person. The rows' content does not
/// matter to these tests — only how many each person owes — so the chores are minimal and
/// distinct only by id.
enum TodayPlanTestBuilder {
    static func plan(anne: Int, wes: Int) -> TodayPlan {
        let chores = (0 ..< (anne + wes)).map { index in
            Chore(
                id: "c\(index)",
                title: "Chore \(index)",
                cadence: .daily,
                fixedAssignee: index < anne ? .anne : .wes,
                category: .chore
            )
        }
        return TodayPlanner.plan(
            chores: chores,
            completions: [],
            handoffs: [],
            asOf: Date(timeIntervalSince1970: 1_789_000_000),
            activeFrom: Date(timeIntervalSince1970: 1_789_000_000),
            calendar: HouseholdCalendar()
        )
    }
}
