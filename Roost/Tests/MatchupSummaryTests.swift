@testable import Roost
import RoostCore
import XCTest

final class MatchupSummaryTests: XCTestCase {
    private let calendar = HouseholdCalendar()
    /// Monday, noon in Chicago. The adjacent Sunday belongs to the previous week.
    private let monday = Date(timeIntervalSince1970: 1_790_010_000)

    func testHistoryUsesActorKeepsRetiredTitleAndExcludesRemovedAndFutureRows() {
        let retired = ChoreRecord(id: "retired", title: "Old chore", cadence: "daily", fixedAssignee: "anne",
                                  category: "chore", sortOrder: 0, retired: true)
        let records = [
            CompletionRecord(id: "old", choreId: "retired", person: "wes", completedAt: monday),
            CompletionRecord(
                id: "missing",
                choreId: "unknown",
                person: "anne",
                completedAt: monday.addingTimeInterval(-1)
            ),
            CompletionRecord(id: "removed", choreId: "retired", person: "anne", completedAt: monday, removed: true),
            CompletionRecord(
                id: "future",
                choreId: "retired",
                person: "anne",
                completedAt: monday.addingTimeInterval(1)
            ),
        ]
        let summary = MatchupSummary(chores: [retired], completions: records, handoffs: [],
                                     asOf: monday, activeFrom: monday)
        XCTAssertEqual(summary.recent.map(\.id), ["old", "missing"])
        XCTAssertEqual(summary.recent.map(\.person), [.wes, .anne])
        XCTAssertEqual(summary.recent.map(\.title), ["Old chore", Strings.Matchup.unknownChore])
        XCTAssertEqual(summary.plan.dueCount(for: .anne), 0)
    }

    func testWeekBoundaryAndRecentLimitDoNotLimitWeeklyTotals() {
        let week = calendar.weekBounds(containing: monday)
        let now = week.start.addingTimeInterval(3600)
        var records = (0 ..< 10).map { index in
            CompletionRecord(id: "c\(index)", choreId: "chore", person: "anne",
                             completedAt: now.addingTimeInterval(Double(-index)))
        }
        records.append(CompletionRecord(id: "sunday", choreId: "chore", person: "wes",
                                        completedAt: week.start.addingTimeInterval(-1)))
        let summary = MatchupSummary(chores: [], completions: records, handoffs: [],
                                     asOf: now, activeFrom: week.start)
        XCTAssertEqual(summary.plan.doneThisWeek[.anne], 10)
        XCTAssertEqual(summary.plan.doneThisWeek[.wes], 0)
        XCTAssertEqual(summary.recent.map(\.id), (0 ..< 8).map { "c\($0)" })
    }
}
