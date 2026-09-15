@testable import RoostCore
import XCTest

/// Anne's litter rules. Household starts Monday 2026-09-14 (daily period 252, weekly 36, monthly 8).
final class LitterRotationTests: XCTestCase {
    let cal = HouseholdCalendar()
    let scoop = Chore(
        id: "scoop-litter", title: "Scoop litter", cadence: .daily, category: .catCare,
        rotation: .weekdayCycle(weeks: [
            [.anne, .wes, .anne, .wes, .anne, .wes, .anne],
            [.wes, .anne, .wes, .anne, .wes, .anne, .wes],
        ])
    )
    let change = Chore(
        id: "change-litter", title: "Change litter", cadence: .monthly, category: .catCare, dueDay: 25,
        rotation: .alternate(start: .wes), missPenalty: MissPenalty(watch: "scoop-litter", overMisses: 2)
    )
    lazy var activeFrom = cal.date(year: 2026, month: 9, day: 14, hour: 0)
    lazy var scheduler = Scheduler(chores: [scoop, change], activeFrom: activeFrom, calendar: cal)

    func day(_ m: Int, _ d: Int, year: Int = 2026) -> Date { cal.date(year: year, month: m, day: d, hour: 9) }
    func done(_ chore: Chore, _ person: Person, _ date: Date) -> Completion {
        Completion(id: "\(chore.id)-\(date.timeIntervalSince1970)", choreId: chore.id, person: person, completedAt: date)
    }
    /// Misses inside September for the given completions.
    func septemberMisses(_ completions: [Completion], asOf: Date, handoffs: [Handoff] = []) -> [Person: Int] {
        let bounds = cal.periodBounds(.monthly, index: cal.periodIndex(.monthly, containing: day(9, 15)))
        return MissCounter.misses(
            watched: scoop, from: bounds.firstDay, through: bounds.lastDay, asOf: asOf,
            activeFrom: activeFrom, completions: completions, handoffs: handoffs,
            calendar: cal, fallback: RoundRobinRotation()
        )
    }

    func testNothingBeforeTheHouseholdStartedCounts() {
        // Sep 1–13 are before activeFrom; on Sep 15 only Mon 14 has ended.
        XCTAssertEqual(septemberMisses([], asOf: day(9, 15)), [.anne: 1])
    }

    func testTodayIsNeverAMissUntilItIsOver() {
        // Sun 20 is Anne's and unfinished, but it is today: Anne's misses are Mon 14, Wed 16, Fri 18.
        XCTAssertEqual(septemberMisses([], asOf: day(9, 20)), [.anne: 3, .wes: 3])
    }

    func testACompletionByAnyoneClearsTheDay() {
        let covered = [done(scoop, .wes, day(9, 14)), done(scoop, .anne, day(9, 16))]
        XCTAssertEqual(septemberMisses(covered, asOf: day(9, 20)), [.anne: 1, .wes: 3])
    }

    func testAnAcceptedHandoffMovesWhoMissedTheDay() {
        // Wed 16 is Anne's by the table; Wes accepted it, so an empty Wed 16 is Wes's miss.
        let period = cal.periodIndex(.daily, containing: day(9, 16))
        // Source signature: createdAt before state (state defaults to .pending).
        let taken = Handoff(
            id: "h1", choreId: scoop.id, from: .anne, to: .wes, periodIndex: period,
            cadence: .daily, createdAt: day(9, 16), state: .accepted
        )
        let counts = septemberMisses([], asOf: day(9, 20), handoffs: [taken])
        XCTAssertEqual(counts, [.anne: 2, .wes: 4])
    }

    func testPenalisedPicksTheOneOverTheLine() {
        XCTAssertNil(MissCounter.penalised([.anne: 2, .wes: 2], overMisses: 2), "neither is over")
        XCTAssertEqual(MissCounter.penalised([.anne: 3, .wes: 1], overMisses: 2), .anne)
        XCTAssertEqual(MissCounter.penalised([.anne: 4, .wes: 5], overMisses: 2), .wes, "both over, more misses")
        XCTAssertNil(MissCounter.penalised([.anne: 4, .wes: 4], overMisses: 2), "both over and tied")
    }

    func testScoopingRunsFourThreeAndSwapsEachWeek() {
        let week1: [(Int, Person)] = [(14, .anne), (15, .wes), (16, .anne), (17, .wes), (18, .anne), (19, .wes), (20, .anne)]
        for (d, who) in week1 {
            XCTAssertEqual(scheduler.assignee(for: scoop, periodIndex: cal.periodIndex(.daily, containing: day(9, d))), who, "Sep \(d)")
        }
        let week2: [(Int, Person)] = [(21, .wes), (22, .anne), (23, .wes), (24, .anne), (25, .wes), (26, .anne), (27, .wes)]
        for (d, who) in week2 {
            XCTAssertEqual(scheduler.assignee(for: scoop, periodIndex: cal.periodIndex(.daily, containing: day(9, d))), who, "Sep \(d)")
        }
        // and back: Mon 28 is Anne's again
        XCTAssertEqual(scheduler.assignee(for: scoop, periodIndex: cal.periodIndex(.daily, containing: day(9, 28))), .anne)
        // four days one week, three the next, for each of them
        XCTAssertEqual(week1.filter { $0.1 == .anne }.count, 4)
        XCTAssertEqual(week2.filter { $0.1 == .anne }.count, 3)
    }

    func testAnAcceptedHandoffStillBeatsTheTableAndDoesNotLeakIntoNextWeek() {
        let wed = cal.periodIndex(.daily, containing: day(9, 16))
        let taken = Handoff(
            id: "h1", choreId: scoop.id, from: .anne, to: .wes, periodIndex: wed,
            cadence: .daily, createdAt: day(9, 16), state: .accepted
        )
        XCTAssertEqual(scheduler.assignee(for: scoop, periodIndex: wed, on: day(9, 16), handoffs: [taken]), .wes)
        XCTAssertEqual(scheduler.assignee(for: scoop, periodIndex: wed + 1, on: day(9, 17), handoffs: [taken]), .wes, "Thu is Wes's anyway")
        let nextWed = cal.periodIndex(.daily, containing: day(9, 23))
        XCTAssertEqual(scheduler.assignee(for: scoop, periodIndex: nextWed, on: day(9, 23), handoffs: [taken]), .wes, "week B")
        let weekAfter = cal.periodIndex(.daily, containing: day(9, 30))
        XCTAssertEqual(scheduler.assignee(for: scoop, periodIndex: weekAfter, on: day(9, 30), handoffs: [taken]), .anne, "week A again")
    }

    func testTheChangeAlternatesFromWes() {
        XCTAssertEqual(scheduler.assignee(for: change, periodIndex: cal.periodIndex(.monthly, containing: day(9, 25))), .wes)
        XCTAssertEqual(scheduler.assignee(for: change, periodIndex: cal.periodIndex(.monthly, containing: day(10, 25))), .anne)
        XCTAssertEqual(scheduler.assignee(for: change, periodIndex: cal.periodIndex(.monthly, containing: day(11, 25))), .wes)
    }

    func testTheChangeMovesToWhoeverMissedMoreThanTwoScoops() {
        // Anne scooped none of hers; Wes did all of his through Sep 24, so only Anne is over the line.
        // Through Sep 24 Anne owed Mon14/Wed16/Fri18/Sun20/Tue22/Thu24 (6); Wes owed five days and finished them.
        var completions: [Completion] = []
        for d in [15, 17, 19, 21, 23] { completions.append(done(scoop, .wes, day(9, d))) }
        let plan = scheduler.plan(on: day(9, 25), completions: completions)
        let wesRows = plan[.wes]?.map(\.chore.id) ?? []
        let anneRows = plan[.anne]?.map(\.chore.id) ?? []
        XCTAssertTrue(anneRows.contains(change.id), "Anne missed 6 scoops, so September's change is hers")
        XCTAssertFalse(wesRows.contains(change.id), "the rotation said Wes; the penalty moved it")

        // Covering four of Anne's six leaves exactly two misses — not over the line — so the rotation's Wes returns.
        // (Plan sketch covered only 14/16/18, which still leaves three misses; corrected to match spec intent.)
        for d in [14, 16, 18, 20] { completions.append(done(scoop, .anne, day(9, d))) }
        let after = scheduler.plan(on: day(9, 25), completions: completions)
        XCTAssertTrue((after[.wes]?.map(\.chore.id) ?? []).contains(change.id), "Anne is back under the line")
    }

    func testTheOtherChoresAreUnaffected() {
        let laundry = Chore(id: "laundry", title: "Laundry", cadence: .weekly, fixedAssignee: .anne, category: .chore)
        let toilet = Chore(id: "clean-toilet-bowl", title: "Clean toilet bowl", cadence: .weekly, category: .chore)
        let s = Scheduler(chores: [laundry, toilet], activeFrom: activeFrom, calendar: cal)
        let week = cal.periodIndex(.weekly, containing: day(9, 16))
        XCTAssertEqual(s.assignee(for: laundry, periodIndex: week), .anne, "a pin still wins")
        XCTAssertEqual(
            s.assignee(for: toilet, periodIndex: week),
            RoundRobinRotation().assignee(for: toilet, periodIndex: week),
            "an ordinary chore still hash-rotates"
        )
    }
}
