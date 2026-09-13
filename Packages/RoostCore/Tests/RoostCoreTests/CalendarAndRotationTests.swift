@testable import RoostCore
import XCTest

final class CalendarTests: XCTestCase {
    let cal = HouseholdCalendar()

    func testAnchorIsAMondayAndPeriodZero() {
        let weekday = cal.calendar.component(.weekday, from: cal.anchor)
        XCTAssertEqual(weekday, 2, "anchor is Monday")
        XCTAssertEqual(cal.periodIndex(.daily, containing: cal.anchor), 0)
        XCTAssertEqual(cal.periodIndex(.weekly, containing: cal.anchor), 0)
        XCTAssertEqual(cal.periodIndex(.biweekly, containing: cal.anchor), 0)
        XCTAssertEqual(cal.periodIndex(.monthly, containing: cal.anchor), 0)
    }

    func testWeekBoundsStartMondayChicago() {
        let wed = cal.date(year: 2026, month: 9, day: 16, hour: 15)
        let week = cal.weekBounds(containing: wed)
        XCTAssertEqual(week.start, cal.date(year: 2026, month: 9, day: 14, hour: 0))
        XCTAssertEqual(week.end, cal.date(year: 2026, month: 9, day: 21, hour: 0))
        // Sunday 11:59pm Chicago is still the same week.
        let sunLate = cal.date(year: 2026, month: 9, day: 20, hour: 23, minute: 59)
        XCTAssertEqual(cal.weekBounds(containing: sunLate).start, week.start)
    }

    func testMonthlyBounds() {
        let sep = cal.periodIndex(.monthly, containing: cal.date(year: 2026, month: 9, day: 13))
        XCTAssertEqual(sep, 8)
        let b = cal.periodBounds(.monthly, index: sep)
        XCTAssertEqual(b.firstDay, cal.date(year: 2026, month: 9, day: 1, hour: 0))
        XCTAssertEqual(b.lastDay, cal.date(year: 2026, month: 9, day: 30, hour: 0))
    }

    func testDSTTransitionDoesNotShiftDayIndex() {
        // 2026-11-01 is the fall-back day in Chicago.
        let before = cal.date(year: 2026, month: 10, day: 31)
        let after = cal.date(year: 2026, month: 11, day: 2)
        XCTAssertEqual(cal.dayIndex(after) - cal.dayIndex(before), 2)
    }
}

final class RotationTests: XCTestCase {
    let unpinned = Chore(id: "wipe-tables", title: "Wipe down tables", cadence: .daily, category: .chore)
    let pinned = Chore(id: "laundry", title: "Laundry", cadence: .weekly, fixedAssignee: .anne, category: .chore)

    func testRoundRobinAlternatesEveryPeriodAndIsDeterministic() {
        let r = RoundRobinRotation()
        let a = r.assignee(for: unpinned, periodIndex: 10)
        let b = r.assignee(for: unpinned, periodIndex: 11)
        let c = r.assignee(for: unpinned, periodIndex: 12)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a, c)
        XCTAssertEqual(a, RoundRobinRotation().assignee(for: unpinned, periodIndex: 10), "same across instances")
    }

    func testStartingPersonVariesByChoreId() throws {
        let r = RoundRobinRotation()
        let list = try ChoreList.load(from: repoChoresURL())
        let starters = Set(list.chores.filter { !$0.isPinned }.map { r.assignee(for: $0, periodIndex: 0) })
        XCTAssertEqual(starters, Set(Person.allCases), "not every chore starts with the same person")
    }

    func testSchedulerHonorsPinnedOverRotation() {
        struct AlwaysWes: Rotation {
            func assignee(for _: Chore, periodIndex _: Int) -> Person {
                .wes
            }
        }
        let cal = HouseholdCalendar()
        let s = Scheduler(chores: [pinned, unpinned], activeFrom: cal.anchor, rotation: AlwaysWes(), calendar: cal)
        XCTAssertEqual(s.assignee(for: pinned, periodIndex: 40), .anne)
        XCTAssertEqual(s.assignee(for: unpinned, periodIndex: 40), .wes)
    }
}

final class EscalationTests: XCTestCase {
    func testLadder() {
        XCTAssertEqual(EscalationStage.stage(daysOverdue: 0), .dueToday)
        XCTAssertEqual(EscalationStage.stage(daysOverdue: 1), .nudge)
        XCTAssertEqual(EscalationStage.stage(daysOverdue: 2), .nudge)
        XCTAssertEqual(EscalationStage.stage(daysOverdue: 3), .pointed)
        XCTAssertEqual(EscalationStage.stage(daysOverdue: 4), .pointed)
        XCTAssertEqual(EscalationStage.stage(daysOverdue: 5), .alert)
        XCTAssertEqual(EscalationStage.stage(daysOverdue: 30), .alert)
        XCTAssertTrue(EscalationStage.dueToday < EscalationStage.alert)
    }
}
