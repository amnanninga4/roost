@testable import RoostCore
import XCTest

final class SchedulerTests: XCTestCase {
    let cal = HouseholdCalendar()
    let litter = Chore(id: "scoop-litter", title: "Scoop litter", cadence: .daily, category: .catCare)
    let toilet = Chore(id: "clean-toilet-bowl", title: "Clean toilet bowl", cadence: .weekly, category: .chore)
    let garbage = Chore(
        id: "garbage-can-to-street-sunday",
        title: "Garbage can to street, Sunday",
        cadence: .weekly,
        fixedAssignee: .wes,
        category: .chore
    )
    let oven = Chore(id: "clean-inside-ovens", title: "Clean inside ovens", cadence: .monthly, category: .chore)
    let fridge = Chore(
        id: "clean-out-fridge-pantry",
        title: "Clean out fridge and pantry",
        cadence: .quarterly,
        category: .chore
    )
    let mowing = Chore(
        id: "mow-lawn",
        title: "Mow lawn",
        cadence: .weekly,
        fixedAssignee: .anne,
        category: .chore,
        season: Season(months: [4, 5, 6, 7, 8, 9, 10])
    )
    let pantry = Chore(
        id: "clean-out-fridge-pantry",
        title: "Clean out fridge and pantry",
        cadence: .quarterly,
        category: .chore,
        together: true
    )

    // Household starts Monday 2026-09-07. "Today" is Wednesday 2026-09-16 unless a test says otherwise.
    lazy var activeFrom = cal.date(year: 2026, month: 9, day: 7, hour: 0)
    lazy var wed = cal.date(year: 2026, month: 9, day: 16, hour: 9)
    lazy var scheduler = Scheduler(chores: [litter, toilet, garbage, oven], activeFrom: activeFrom, calendar: cal)

    func done(_ chore: Chore, _ person: Person, _ date: Date) -> Completion {
        Completion(
            id: "\(chore.id)-\(date.timeIntervalSince1970)",
            choreId: chore.id,
            person: person,
            completedAt: date
        )
    }

    func testDailyDoneYesterdayIsDueTodayWithNoOverdue() {
        let yesterday = cal.date(year: 2026, month: 9, day: 15, hour: 20)
        let item = scheduler.dueItem(for: litter, on: wed, completions: [done(litter, .anne, yesterday)])
        XCTAssertEqual(item?.daysOverdue, 0)
        XCTAssertEqual(item?.stage, .dueToday)
        XCTAssertEqual(item?.periodStart, cal.startOfDay(wed))
    }

    func testDailyDoneTodayIsNotDue() {
        let item = scheduler.dueItem(for: litter, on: wed, completions: [done(litter, .anne, wed)])
        XCTAssertNil(item)
    }

    func testDailyMissedYesterdayCarriesForwardAsOneDayLate() {
        let twoDaysAgo = cal.date(year: 2026, month: 9, day: 14, hour: 20)
        let item = scheduler.dueItem(for: litter, on: wed, completions: [done(litter, .wes, twoDaysAgo)])
        XCTAssertEqual(
            item?.periodStart,
            cal.date(year: 2026, month: 9, day: 15, hour: 0),
            "oldest incomplete day is yesterday"
        )
        XCTAssertEqual(item?.daysOverdue, 1)
        XCTAssertEqual(item?.stage, .nudge)
    }

    func testNeverDoneCountsFromActiveFromNotForever() {
        let item = scheduler.dueItem(for: litter, on: wed, completions: [])
        XCTAssertEqual(item?.periodStart, activeFrom)
        XCTAssertEqual(item?.daysOverdue, 9, "Sep 7 → Sep 16")
        XCTAssertEqual(item?.stage, .alert)
    }

    func testWeeklyMissedLastWeekIsThreeDaysLateOnWednesday() {
        // No completions since activeFrom (Mon Sep 7). Week of Sep 7 ended Sun Sep 13; Wed Sep 16 is 3 days past.
        let item = scheduler.dueItem(for: toilet, on: wed, completions: [])
        XCTAssertEqual(item?.periodLastDay, cal.date(year: 2026, month: 9, day: 13, hour: 0))
        XCTAssertEqual(item?.daysOverdue, 3)
        XCTAssertEqual(item?.stage, .pointed)
    }

    func testWeeklyDoneLastWeekIsDueThisWeekNotOverdue() {
        let lastThu = cal.date(year: 2026, month: 9, day: 10, hour: 18)
        let item = scheduler.dueItem(for: toilet, on: wed, completions: [done(toilet, .anne, lastThu)])
        XCTAssertEqual(item?.periodStart, cal.date(year: 2026, month: 9, day: 14, hour: 0))
        XCTAssertEqual(item?.daysOverdue, 0)
    }

    func testCompletingNowClearsOlderMissedPeriods() {
        // Missed weeks of Sep 7 and Sep 14; done on Wed Sep 23 → nothing due Thu Sep 24.
        let doneLate = cal.date(year: 2026, month: 9, day: 23, hour: 12)
        let thu = cal.date(year: 2026, month: 9, day: 24, hour: 9)
        XCTAssertNil(scheduler.dueItem(for: toilet, on: thu, completions: [done(toilet, .wes, doneLate)]))
    }

    func testMonthlyPeriod() {
        // Household started Sep 7, so September is the first monthly period; due all month, 0 overdue on Sep 16.
        let item = scheduler.dueItem(for: oven, on: wed, completions: [])
        XCTAssertEqual(item?.daysOverdue, 0)
        // On Oct 3 with nothing done: September ended Sep 30 → 3 days late.
        let oct3 = cal.date(year: 2026, month: 10, day: 3, hour: 9)
        XCTAssertEqual(scheduler.dueItem(for: oven, on: oct3, completions: [])?.daysOverdue, 3)
    }

    func testQuarterlyChoreIsOneDayLateOnTheFirstDayOfTheNextQuarter() {
        // Household started Sep 7, so Jul–Sep 2026 (quarter 2) is the first period; due all quarter.
        let s = Scheduler(chores: [fridge], activeFrom: activeFrom, calendar: cal)
        XCTAssertEqual(s.dueItem(for: fridge, on: wed, completions: [])?.daysOverdue, 0)
        XCTAssertEqual(s.dueItem(for: fridge, on: wed, completions: [])?.periodIndex, 2)
        // Oct 1 with nothing done: the quarter ended Sep 30 → 1 day late, like a daily the morning after.
        let oct1 = cal.date(year: 2026, month: 10, day: 1, hour: 9)
        XCTAssertEqual(s.dueItem(for: fridge, on: oct1, completions: [])?.daysOverdue, 1)
        XCTAssertEqual(s.dueItem(for: fridge, on: oct1, completions: [])?.stage, .nudge)
    }

    func testDueByPersonRespectsPinsAndSortsMostOverdueFirst() {
        let byPerson = scheduler.due(on: wed, completions: [])
        let wesItems = byPerson[.wes] ?? []
        XCTAssertTrue(wesItems.contains { $0.chore.id == garbage.id }, "pinned garbage goes to Wes")
        XCTAssertFalse((byPerson[.anne] ?? []).contains { $0.chore.id == garbage.id })
        for items in byPerson.values {
            let overdue = items.map(\.daysOverdue)
            XCTAssertEqual(overdue, overdue.sorted(by: >), "most overdue first")
        }
        let all = byPerson.values.flatMap(\.self)
        XCTAssertEqual(all.count, 4, "every chore is due somewhere when nothing has been done")
    }

    func testSeasonalChoreIsNotDueInMarchAndStartsFreshInApril() {
        let s = Scheduler(chores: [mowing], activeFrom: activeFrom, calendar: cal)
        // Week of Mar 15 2027: out of season, and not overdue either.
        XCTAssertNil(s.dueItem(for: mowing, on: cal.date(year: 2027, month: 3, day: 17, hour: 9), completions: []))
        // Apr 1 2027 is a Thursday in the week of Mar 29, which starts in March: still out.
        XCTAssertNil(s.dueItem(for: mowing, on: cal.date(year: 2027, month: 4, day: 1, hour: 9), completions: []))
        // Week of Apr 5: in season, and last autumn's missed weeks do not carry over.
        let item = s.dueItem(for: mowing, on: cal.date(year: 2027, month: 4, day: 7, hour: 9), completions: [])
        XCTAssertEqual(item?.periodStart, cal.date(year: 2027, month: 4, day: 5, hour: 0))
        XCTAssertEqual(item?.daysOverdue, 0)
        XCTAssertEqual(item?.person, .anne)
    }

    func testSeasonalChoreStaysDueWhileItsLastPeriodRunsIntoNovember() {
        let s = Scheduler(chores: [mowing], activeFrom: activeFrom, calendar: cal)
        let mowed = done(mowing, .anne, cal.date(year: 2026, month: 10, day: 22, hour: 17)) // week of Oct 19
        // The week of Oct 26 starts in October, so it is due through Sunday Nov 1.
        let oct30 = s.dueItem(for: mowing, on: cal.date(year: 2026, month: 10, day: 30, hour: 9), completions: [mowed])
        XCTAssertEqual(oct30?.periodStart, cal.date(year: 2026, month: 10, day: 26, hour: 0))
        XCTAssertEqual(oct30?.daysOverdue, 0)
        XCTAssertNotNil(s.dueItem(for: mowing, on: cal.date(year: 2026, month: 11, day: 1, hour: 9), completions: [mowed]))
        // The week of Nov 2 starts out of season: not due, and the missed Oct 26 week is not overdue.
        XCTAssertNil(s.dueItem(for: mowing, on: cal.date(year: 2026, month: 11, day: 3, hour: 9), completions: [mowed]))
    }

    func testSeasonalChoreInsideTheSeasonCarriesLikeAnyOther() {
        let s = Scheduler(chores: [mowing], activeFrom: activeFrom, calendar: cal)
        // Household started Sep 7 (in season). Nothing done by Wed Sep 16 → the week of Sep 7 is 3 days late.
        let item = s.dueItem(for: mowing, on: wed, completions: [])
        XCTAssertEqual(item?.periodStart, activeFrom)
        XCTAssertEqual(item?.daysOverdue, 3)
    }
    func testTogetherChoreIsARowForBothAndOneCheckOffClearsBoth() {
        let s = Scheduler(chores: [litter, pantry], activeFrom: activeFrom, calendar: cal)
        let plan = s.plan(on: wed, completions: [])
        let anne = plan[.anne]?.first { $0.chore.id == pantry.id }
        let wes = plan[.wes]?.first { $0.chore.id == pantry.id }
        XCTAssertEqual(anne?.id, "clean-out-fridge-pantry#2#anne")
        XCTAssertEqual(wes?.id, "clean-out-fridge-pantry#2#wes")
        XCTAssertEqual(anne?.periodIndex, wes?.periodIndex)
        XCTAssertEqual(anne?.daysOverdue, wes?.daysOverdue)
        XCTAssertEqual(s.dueItems(for: pantry, on: wed, completions: []).map(\.person), [.anne, .wes])
        XCTAssertEqual(s.dueItem(for: pantry, on: wed, completions: [])?.person, .anne, "the single-row call answers Anne's row")

        // Wes does it: gone from both columns.
        let cleared = s.plan(on: wed, completions: [done(pantry, .wes, wed)])
        XCTAssertFalse(cleared[.anne]!.contains { $0.chore.id == pantry.id })
        XCTAssertFalse(cleared[.wes]!.contains { $0.chore.id == pantry.id })
        XCTAssertEqual(s.dueItems(for: pantry, on: wed, completions: [done(pantry, .wes, wed)]), [])

        // An ordinary chore's id is what it always was.
        let day = cal.periodIndex(.daily, containing: wed)
        XCTAssertEqual(s.dueItem(for: litter, on: wed, completions: [])?.id, "scoop-litter#\(day)")
        XCTAssertEqual(s.dueItems(for: litter, on: wed, completions: []).count, 1)
    }

}

final class TalliesTests: XCTestCase {
    let cal = HouseholdCalendar()
    /// Two pinned dailies so assignment is fixed regardless of rotation.
    let anneDaily = Chore(
        id: "am-wet-cat-food",
        title: "AM wet cat food",
        cadence: .daily,
        fixedAssignee: .anne,
        category: .catCare
    )
    let wesDaily = Chore(
        id: "pm-wet-cat-food",
        title: "PM wet cat food",
        cadence: .daily,
        fixedAssignee: .wes,
        category: .catCare
    )
    let weekly = Chore(id: "laundry", title: "Laundry", cadence: .weekly, fixedAssignee: .anne, category: .chore)

    lazy var activeFrom = cal.date(year: 2026, month: 9, day: 7, hour: 0)
    lazy var tallies = Tallies(scheduler: Scheduler(
        chores: [anneDaily, wesDaily, weekly],
        activeFrom: activeFrom,
        calendar: cal
    ))

    func c(_ chore: Chore, _ person: Person, month: Int, day: Int, hour: Int = 12) -> Completion {
        Completion(
            id: "\(chore.id)-\(month)-\(day)-\(hour)",
            choreId: chore.id,
            person: person,
            completedAt: cal.date(year: 2026, month: month, day: day, hour: hour)
        )
    }

    func testWeekTallyStartsMondayChicago() {
        let completions = [
            c(anneDaily, .anne, month: 9, day: 13, hour: 23), // Sunday before → previous week
            c(anneDaily, .anne, month: 9, day: 14, hour: 0), // Monday 00:00 → this week
            c(anneDaily, .anne, month: 9, day: 16),
            c(weekly, .anne, month: 9, day: 15),
            c(wesDaily, .wes, month: 9, day: 15),
            c(wesDaily, .wes, month: 9, day: 21, hour: 0), // next Monday → next week
        ]
        let wed = cal.date(year: 2026, month: 9, day: 16, hour: 18)
        let counts = tallies.doneThisWeek(asOf: wed, completions: completions)
        XCTAssertEqual(counts[.anne], 3)
        XCTAssertEqual(counts[.wes], 1)
    }

    func testStreakCountsCompleteDaysAndBreaksOnAMiss() {
        // Anne did her daily on Sep 13, 14, 15; today (Sep 16) not yet.
        var completions = [
            c(anneDaily, .anne, month: 9, day: 13),
            c(anneDaily, .anne, month: 9, day: 14),
            c(anneDaily, .anne, month: 9, day: 15),
        ]
        let wedMorning = cal.date(year: 2026, month: 9, day: 16, hour: 9)
        XCTAssertEqual(
            tallies.streak(for: .anne, asOf: wedMorning, completions: completions),
            3,
            "unfinished today does not break"
        )

        completions.append(c(anneDaily, .anne, month: 9, day: 16, hour: 8))
        XCTAssertEqual(
            tallies.streak(for: .anne, asOf: wedMorning, completions: completions),
            4,
            "finished today counts"
        )

        // Remove Sep 14 → streak is only Sep 15 + Sep 16.
        let withGap = completions.filter { !($0.choreId == anneDaily.id && cal.calendar.component(
            .day,
            from: $0.completedAt
        ) == 14) }
        XCTAssertEqual(tallies.streak(for: .anne, asOf: wedMorning, completions: withGap), 2)

        // Wes has done nothing: 0.
        XCTAssertEqual(tallies.streak(for: .wes, asOf: wedMorning, completions: completions), 0)
    }

    func testStreakDoesNotCountBeforeActiveFrom() {
        // Every day from Sep 1 done, but the household started Sep 7 → at most Sep 7..Sep 16 = 10 days.
        let completions = (1 ... 16).map { c(anneDaily, .anne, month: 9, day: $0) }
        let wedNight = cal.date(year: 2026, month: 9, day: 16, hour: 22)
        XCTAssertEqual(tallies.streak(for: .anne, asOf: wedNight, completions: completions), 10)
    }

    func testTogetherCompletionCountsForBothInTheWeekTallyAndTheStreak() {
        let bothDaily = Chore(id: "feed-together", title: "Feed the cat together", cadence: .daily,
                              category: .catCare, together: true)
        let both = Tallies(scheduler: Scheduler(
            chores: [anneDaily, wesDaily, bothDaily],
            activeFrom: activeFrom,
            calendar: cal
        ))
        let wed = cal.date(year: 2026, month: 9, day: 16, hour: 18)
        let completions = [
            c(anneDaily, .anne, month: 9, day: 15),
            c(bothDaily, .wes, month: 9, day: 15), // one row, credited to both
        ]
        XCTAssertEqual(both.doneThisWeek(asOf: wed, completions: completions), [.anne: 2, .wes: 1])

        // Sep 15 is complete for Anne (her daily + the shared one) and incomplete for Wes (his daily is missing).
        XCTAssertEqual(both.streak(for: .anne, asOf: wed, completions: completions), 1)
        XCTAssertEqual(both.streak(for: .wes, asOf: wed, completions: completions), 0)
        // Without the shared completion Anne's day is incomplete too: a together daily is owed by both.
        XCTAssertEqual(both.streak(for: .anne, asOf: wed, completions: [c(anneDaily, .anne, month: 9, day: 15)]), 0)
    }
}
