@testable import RoostCore
import XCTest

final class CalendarTests: XCTestCase {
    let cal = HouseholdCalendar()

    func testAnchorIsAMondayAndPeriodZero() {
        let weekday = cal.calendar.component(.weekday, from: cal.anchor)
        XCTAssertEqual(weekday, 2, "anchor is Monday")
        for cadence in Cadence.allCases {
            XCTAssertEqual(cal.periodIndex(cadence, containing: cal.anchor), 0, "\(cadence) period 0 holds the anchor")
        }
    }

    func testBimonthlyAndQuarterlyPeriodsAcrossAYearBoundary() {
        // September 2026 is monthIndex 8: bimonthly 4 (Sep–Oct), quarterly 2 (Jul–Sep).
        let sep = cal.date(year: 2026, month: 9, day: 13)
        XCTAssertEqual(cal.monthIndex(sep), 8)
        XCTAssertEqual(cal.periodIndex(.bimonthly, containing: sep), 4)
        XCTAssertEqual(cal.periodIndex(.quarterly, containing: sep), 2)
        let bi = cal.periodBounds(.bimonthly, index: 4)
        XCTAssertEqual(bi.firstDay, cal.date(year: 2026, month: 9, day: 1, hour: 0))
        XCTAssertEqual(bi.lastDay, cal.date(year: 2026, month: 10, day: 31, hour: 0))
        let quarter = cal.periodBounds(.quarterly, index: 2)
        XCTAssertEqual(quarter.firstDay, cal.date(year: 2026, month: 7, day: 1, hour: 0))
        XCTAssertEqual(quarter.lastDay, cal.date(year: 2026, month: 9, day: 30, hour: 0))

        // Across New Year: Nov–Dec 2026 is bimonthly 5, Jan–Feb 2027 is 6; Oct–Dec is quarterly 3, Jan–Mar 2027 is 4.
        let dec31 = cal.date(year: 2026, month: 12, day: 31)
        let jan1 = cal.date(year: 2027, month: 1, day: 1)
        XCTAssertEqual(cal.periodIndex(.bimonthly, containing: dec31), 5)
        XCTAssertEqual(cal.periodIndex(.bimonthly, containing: jan1), 6)
        XCTAssertEqual(cal.periodIndex(.quarterly, containing: dec31), 3)
        XCTAssertEqual(cal.periodIndex(.quarterly, containing: jan1), 4)
        let q4 = cal.periodBounds(.quarterly, index: 4)
        XCTAssertEqual(q4.firstDay, cal.date(year: 2027, month: 1, day: 1, hour: 0))
        XCTAssertEqual(q4.lastDay, cal.date(year: 2027, month: 3, day: 31, hour: 0))

        // Before the anchor the index goes negative and the bounds still land on month starts.
        let dec2025 = cal.date(year: 2025, month: 12, day: 15)
        XCTAssertEqual(cal.periodIndex(.bimonthly, containing: dec2025), -1)
        XCTAssertEqual(cal.periodIndex(.quarterly, containing: dec2025), -1)
        XCTAssertEqual(
            cal.periodBounds(.bimonthly, index: -1).firstDay,
            cal.date(year: 2025, month: 11, day: 1, hour: 0)
        )
        XCTAssertEqual(
            cal.periodBounds(.quarterly, index: -1).firstDay,
            cal.date(year: 2025, month: 10, day: 1, hour: 0)
        )
        XCTAssertEqual(cal.month(of: dec2025), 12)
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

    func testDueWindowInsideThePeriod() {
        // Week of Mon 2026-09-14 is weekly period 36 (dayIndex 252 / 7).
        XCTAssertEqual(cal.periodIndex(.weekly, containing: cal.date(year: 2026, month: 9, day: 14)), 36)
        let garbage = Chore(id: "g", title: "G", cadence: .weekly, category: .chore, weekdays: [5, 6])
        let g = cal.dueWindow(for: garbage, periodIndex: 36)
        XCTAssertEqual(g.firstDay, cal.date(year: 2026, month: 9, day: 18, hour: 0))
        XCTAssertEqual(g.lastDay, cal.date(year: 2026, month: 9, day: 19, hour: 0))

        let can = Chore(id: "c", title: "C", cadence: .weekly, fixedAssignee: .wes, category: .chore, weekdays: [7])
        let s = cal.dueWindow(for: can, periodIndex: 36)
        XCTAssertEqual(s.firstDay, cal.date(year: 2026, month: 9, day: 20, hour: 0))
        XCTAssertEqual(s.lastDay, s.firstDay)

        // September 2026 is monthly period 8, bimonthly 4 (Sep–Oct), quarterly 2 (Jul–Sep).
        let litter = Chore(id: "l", title: "L", cadence: .monthly, category: .catCare, dueDay: 25)
        let m = cal.dueWindow(for: litter, periodIndex: 8)
        XCTAssertEqual(m.firstDay, cal.date(year: 2026, month: 9, day: 19, hour: 0))
        XCTAssertEqual(m.lastDay, cal.date(year: 2026, month: 9, day: 25, hour: 0))

        let hair = Chore(id: "h", title: "H", cadence: .bimonthly, fixedAssignee: .anne, category: .chore, dueDay: 10)
        let b = cal.dueWindow(for: hair, periodIndex: 4)
        XCTAssertEqual(b.firstDay, cal.date(year: 2026, month: 10, day: 4, hour: 0))
        XCTAssertEqual(b.lastDay, cal.date(year: 2026, month: 10, day: 10, hour: 0))

        let pantry = Chore(id: "p", title: "P", cadence: .quarterly, category: .chore, together: true, dueDay: 28)
        let q = cal.dueWindow(for: pantry, periodIndex: 2)
        XCTAssertEqual(q.firstDay, cal.date(year: 2026, month: 9, day: 22, hour: 0))
        XCTAssertEqual(q.lastDay, cal.date(year: 2026, month: 9, day: 28, hour: 0))

        // No window: the period itself. A dueDay early in a month reaches back into the month before.
        let laundry = Chore(id: "w", title: "W", cadence: .weekly, fixedAssignee: .anne, category: .chore)
        let w = cal.dueWindow(for: laundry, periodIndex: 36)
        XCTAssertEqual(w.firstDay, cal.date(year: 2026, month: 9, day: 14, hour: 0))
        XCTAssertEqual(w.lastDay, cal.date(year: 2026, month: 9, day: 20, hour: 0))
        let cushions = Chore(id: "u", title: "U", cadence: .monthly, category: .chore, dueDay: 5)
        XCTAssertEqual(cal.dueWindow(for: cushions, periodIndex: 9).firstDay, cal.date(year: 2026, month: 9, day: 29, hour: 0))
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
