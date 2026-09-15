@testable import RoostCore
import XCTest

/// The spec's "Dates that must hold": household starts Monday 2026-09-14.
final class DueWindowTests: XCTestCase {
    let cal = HouseholdCalendar()
    let garbage = Chore(id: "take-out-garbage-kitchen", title: "Take out garbage: kitchen", cadence: .weekly,
                        category: .chore, weekdays: [5, 6])
    let can = Chore(id: "garbage-can-to-street-sunday", title: "Garbage can to street, Sunday", cadence: .weekly,
                    fixedAssignee: .wes, category: .chore, weekdays: [7])
    let litter = Chore(id: "change-litter", title: "Change litter", cadence: .monthly, category: .catCare, dueDay: 25)
    let hair = Chore(id: "trim-wes-hair", title: "Trim Wes's hair", cadence: .bimonthly, fixedAssignee: .anne,
                     category: .chore, dueDay: 10)
    let pantry = Chore(id: "clean-out-fridge-pantry", title: "Clean out fridge and pantry", cadence: .quarterly,
                       category: .chore, together: true, dueDay: 28)
    let cushions = Chore(id: "clean-under-cushions", title: "Clean/vacuum under cushions", cadence: .monthly,
                         category: .chore, dueDay: 5)
    let laundry = Chore(id: "laundry", title: "Laundry", cadence: .weekly, fixedAssignee: .anne, category: .chore)

    lazy var activeFrom = cal.date(year: 2026, month: 9, day: 14, hour: 0)
    lazy var scheduler = Scheduler(chores: [garbage, can, litter, hair, pantry, cushions, laundry],
                                   activeFrom: activeFrom, calendar: cal)

    func day(_ month: Int, _ day: Int, year: Int = 2026) -> Date { cal.date(year: year, month: month, day: day, hour: 9) }
    func overdue(_ chore: Chore, _ date: Date, _ completions: [Completion] = []) -> Int? {
        scheduler.dueItem(for: chore, on: date, completions: completions)?.daysOverdue
    }
    func done(_ chore: Chore, _ person: Person, _ date: Date) -> Completion {
        Completion(id: "\(chore.id)-\(date.timeIntervalSince1970)", choreId: chore.id, person: person, completedAt: date)
    }

    func testGarbageIsFridaySaturdayThenLate() {
        for d in 14 ... 17 { XCTAssertNil(overdue(garbage, day(9, d)), "Sep \(d) is before the window") }
        XCTAssertEqual(overdue(garbage, day(9, 18)), 0)
        XCTAssertEqual(overdue(garbage, day(9, 19)), 0)
        XCTAssertEqual(overdue(garbage, day(9, 20)), 1)
        // Monday: the oldest incomplete period is still the week of the 14th; late counts from Sat 19.
        let monday = scheduler.dueItem(for: garbage, on: day(9, 21), completions: [])
        XCTAssertEqual(monday?.daysOverdue, 2)
        XCTAssertEqual(monday?.periodIndex, 36)
        XCTAssertEqual(monday?.dueFirstDay, cal.date(year: 2026, month: 9, day: 18, hour: 0))
        XCTAssertEqual(monday?.dueLastDay, cal.date(year: 2026, month: 9, day: 19, hour: 0))
        XCTAssertEqual(monday?.periodLastDay, cal.date(year: 2026, month: 9, day: 20, hour: 0))
        // Done on Sunday: clear, and the next window opens Fri 25.
        let sunday = [done(garbage, .anne, day(9, 20))]
        for d in 21 ... 24 { XCTAssertNil(overdue(garbage, day(9, d), sunday)) }
        XCTAssertEqual(overdue(garbage, day(9, 25), sunday), 0)
    }

    func testCanIsSundayOnly() {
        for d in 14 ... 19 { XCTAssertNil(overdue(can, day(9, d))) }
        XCTAssertEqual(overdue(can, day(9, 20)), 0)
        XCTAssertEqual(overdue(can, day(9, 21)), 1)
        XCTAssertEqual(scheduler.dueItem(for: can, on: day(9, 20), completions: [])?.person, .wes)
    }

    func testLitterChangeIsTheWeekEndingOnThe25th() {
        for d in 14 ... 18 { XCTAssertNil(overdue(litter, day(9, d))) }
        XCTAssertEqual(overdue(litter, day(9, 19)), 0)
        XCTAssertEqual(overdue(litter, day(9, 25)), 0)
        XCTAssertEqual(overdue(litter, day(9, 26)), 1)
        let doneEarly = [done(litter, .wes, day(9, 20))]
        XCTAssertNil(overdue(litter, day(9, 26), doneEarly))
        for d in 1 ... 18 { XCTAssertNil(overdue(litter, day(10, d), doneEarly)) }
        XCTAssertEqual(overdue(litter, day(10, 19), doneEarly), 0)
    }

    func testBimonthlyAndQuarterlyUseThePeriodsLastMonth() {
        XCTAssertNil(overdue(hair, day(9, 30)))
        XCTAssertNil(overdue(hair, day(10, 3)))
        XCTAssertEqual(overdue(hair, day(10, 4)), 0)
        XCTAssertEqual(overdue(hair, day(10, 10)), 0)
        XCTAssertEqual(overdue(hair, day(10, 11)), 1)

        XCTAssertNil(overdue(pantry, day(9, 21)))
        let both = scheduler.dueItems(for: pantry, on: day(9, 22), completions: [])
        XCTAssertEqual(both.map(\.person), [.anne, .wes])
        XCTAssertEqual(both.map(\.daysOverdue), [0, 0])
        XCTAssertEqual(overdue(pantry, day(9, 29)), 1)
        XCTAssertTrue(scheduler.dueItems(for: pantry, on: day(9, 29), completions: [done(pantry, .anne, day(9, 23))]).isEmpty)
    }

    func testWindowClosedBeforeTheHouseholdStartedWasNeverOwed() {
        // Cushions are due by the 5th; the household starts the 14th. Nothing in September, then Sep 29 – Oct 5.
        for d in 14 ... 28 { XCTAssertNil(overdue(cushions, day(9, d)), "Sep \(d)") }
        XCTAssertEqual(overdue(cushions, day(9, 29)), 0)
        XCTAssertEqual(overdue(cushions, day(10, 5)), 0)
        XCTAssertEqual(overdue(cushions, day(10, 6)), 1)
        // Same rule for a weekly window: start on Sunday Sep 13 and the Fri–Sat garbage was never owed that week.
        let sundayStart = Scheduler(chores: [garbage], activeFrom: cal.date(year: 2026, month: 9, day: 13, hour: 0), calendar: cal)
        XCTAssertNil(sundayStart.dueItem(for: garbage, on: day(9, 13), completions: []))
        XCTAssertNil(sundayStart.dueItem(for: garbage, on: day(9, 17), completions: []))
        XCTAssertEqual(sundayStart.dueItem(for: garbage, on: day(9, 18), completions: [])?.daysOverdue, 0)
    }

    func testUnwindowedChoreIsUnchanged() {
        for d in 14 ... 20 { XCTAssertEqual(overdue(laundry, day(9, d)), 0) }
        XCTAssertEqual(overdue(laundry, day(9, 21)), 1)
        let item = scheduler.dueItem(for: laundry, on: day(9, 16), completions: [])
        XCTAssertEqual(item?.dueFirstDay, item?.periodStart)
        XCTAssertEqual(item?.dueLastDay, item?.periodLastDay)
    }
}
