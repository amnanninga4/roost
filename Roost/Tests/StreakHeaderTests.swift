@testable import Roost
import RoostCore
import XCTest

final class StreakHeaderTests: XCTestCase {
    func testHigherWeekTallyLeads() {
        // Anne's streak is lower, but her week bar number is higher — she leads, matching the bar.
        let m = StreakHeaderModel(streak: [.anne: 2, .wes: 9], doneThisWeek: [.anne: 14, .wes: 11])
        XCTAssertEqual(m.leader, .anne)
        XCTAssertTrue(m.isLeading(.anne))
        XCTAssertFalse(m.isLeading(.wes))

        let flipped = StreakHeaderModel(streak: [.anne: 9, .wes: 2], doneThisWeek: [.anne: 3, .wes: 8])
        XCTAssertEqual(flipped.leader, .wes)
    }

    func testTieHasNoLeader() {
        // Streaks differ; week tallies match — no leader, because the badge follows the bar.
        let tied = StreakHeaderModel(streak: [.anne: 9, .wes: 2], doneThisWeek: [.anne: 5, .wes: 5])
        XCTAssertNil(tied.leader)
        XCTAssertFalse(tied.isLeading(.anne))
        XCTAssertFalse(tied.isLeading(.wes))

        let zero = StreakHeaderModel(streak: [.anne: 4, .wes: 1], doneThisWeek: [:])
        XCTAssertNil(zero.leader, "0 vs 0 is a tie, nobody is tagged")
    }

    func testSidesAreAnneThenWesWithMissingValuesAsZero() {
        let m = StreakHeaderModel(streak: [.wes: 3], doneThisWeek: [.anne: 7])
        XCTAssertEqual(m.sides.map(\.person), [.anne, .wes])
        XCTAssertEqual(m.sides.map(\.streak), [0, 3])
        XCTAssertEqual(m.sides.map(\.doneThisWeek), [7, 0])
    }

    func testTallyLineFollowsTheMockupPattern() {
        let m = StreakHeaderModel(streak: [:], doneThisWeek: [.anne: 14, .wes: 11])
        XCTAssertEqual(m.tallyLine, "Anne · 14   Wes · 11")
    }

    func testBuildsFromAPlan() throws {
        let cal = HouseholdCalendar()
        let chores = try ChoreList.load(from: ChoreSeeder.bundledChoresURL(bundle: Bundle(for: RoostAppMarker.self)))
            .chores
        let day = cal.date(year: 2026, month: 9, day: 14, hour: 18)
        let done = Completion(
            id: "c-1",
            choreId: "scoop-litter",
            person: .anne,
            completedAt: cal.date(year: 2026, month: 9, day: 14, hour: 9)
        )
        let plan = TodayPlanner.plan(
            chores: chores,
            completions: [done],
            asOf: day,
            activeFrom: cal.startOfDay(day),
            calendar: cal
        )
        let m = StreakHeaderModel(plan: plan)
        XCTAssertEqual(m.sides.map(\.doneThisWeek), [1, 0])
        XCTAssertEqual(m.sides.map(\.streak), [plan.streak[.anne], plan.streak[.wes]].map { $0 ?? -1 })
    }

    func testScoreLineLeadsWithThePhonesOwnPersonCalledYou() {
        let m = StreakHeaderModel(streak: [.anne: 12, .wes: 3], doneThisWeek: [.anne: 6, .wes: 4])
        let line = m.scoreLine(me: .anne)
        XCTAssertEqual(line.first, StreakHeaderModel.ScoreLine.Half(person: .anne, label: "You", score: 6))
        XCTAssertEqual(line.second, StreakHeaderModel.ScoreLine.Half(person: .wes, label: "Wes", score: 4))
        XCTAssertEqual(line.streak, 12)
    }

    func testScoreLineUnpairedKeepsAnneFirstAndUsesNames() {
        let m = StreakHeaderModel(streak: [.anne: 2, .wes: 9], doneThisWeek: [.anne: 6, .wes: 4])
        let line = m.scoreLine(me: nil)
        XCTAssertEqual(line.first.label, "Anne")
        XCTAssertEqual(line.second.label, "Wes")
        XCTAssertEqual(line.streak, 9, "the line carries the longest running streak")
    }

    func testScoreLineDropsTheStreakClauseWhenNeitherPersonHasOne() {
        let m = StreakHeaderModel(streak: [:], doneThisWeek: [.anne: 6, .wes: 4])
        XCTAssertNil(m.scoreLine(me: .anne).streak, "no 0-day streak on the line")
    }

    func testStreakLineWording() {
        XCTAssertEqual(Strings.Streak.lineStreak(12), "12-day streak")
        XCTAssertEqual(Strings.Streak.lineStreak(1), "1-day streak")
    }
}
