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
}
