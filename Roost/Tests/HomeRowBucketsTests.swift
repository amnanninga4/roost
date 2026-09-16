@testable import Roost
@testable import RoostCore
import XCTest

final class HomeRowBucketsTests: XCTestCase {
    let cal = HouseholdCalendar()
    // Wednesday 16 Sep 2026.
    lazy var today: Date = cal.date(year: 2026, month: 9, day: 16)
    lazy var tomorrow: Date = cal.date(year: 2026, month: 9, day: 17)

    func testOverdueIsDaysOverduePositive() {
        let row = due(id: "late", daysOverdue: 2, last: today)
        XCTAssertEqual(HomeRowBuckets.bucket(for: row, calendar: cal, on: today), .overdue)
    }

    func testDailyWindowEndingTodayIsToday() {
        let row = due(id: "daily", daysOverdue: 0, last: today)
        XCTAssertEqual(HomeRowBuckets.bucket(for: row, calendar: cal, on: today), .today)
    }

    func testWindowThatStillHasDaysLeftIsLater() {
        let row = due(id: "garbage", daysOverdue: 0, last: tomorrow)
        XCTAssertEqual(HomeRowBuckets.bucket(for: row, calendar: cal, on: today), .later)
    }

    func testDoneRowsSitUnderToday() {
        let chore = Chore(id: "x", title: "X", cadence: .daily, category: .chore)
        let done = TodayRow(chore: chore, person: .anne, kind: .done(completionId: "c1"))
        let groups = HomeRowBuckets.group([done], calendar: cal, on: today)
        XCTAssertEqual(groups.today.map(\.id), [done.id])
        XCTAssertTrue(groups.overdue.isEmpty)
        XCTAssertTrue(groups.later.isEmpty)
    }

    func testEmptyBucketsAreEmptyArraysNotNil() {
        let groups = HomeRowBuckets.group([], calendar: cal, on: today)
        XCTAssertTrue(groups.overdue.isEmpty && groups.today.isEmpty && groups.later.isEmpty)
    }

    func testGroupPreservesPlannerOrderInsideABucket() {
        let a = due(id: "a", daysOverdue: 5, last: today)
        let b = due(id: "b", daysOverdue: 3, last: today)
        let groups = HomeRowBuckets.group([a, b], calendar: cal, on: today)
        XCTAssertEqual(groups.overdue.map(\.chore.id), ["a", "b"])
    }

    private func due(id: String, daysOverdue: Int, last: Date) -> TodayRow {
        let chore = Chore(id: id, title: id, cadence: .daily, category: .chore)
        let item = DueItem(
            chore: chore,
            person: .anne,
            periodIndex: 0,
            periodStart: today,
            periodLastDay: last,
            dueFirstDay: today,
            dueLastDay: last,
            daysOverdue: daysOverdue
        )
        return TodayRow(chore: chore, person: .anne, kind: .due(item))
    }
}
