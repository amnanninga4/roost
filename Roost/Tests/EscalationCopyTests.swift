import XCTest
import RoostCore
@testable import Roost

final class EscalationCopyTests: XCTestCase {
    func testDueTodayHasNoSubtitle() {
        XCTAssertNil(EscalationCopy.subtitle(stage: .dueToday, title: "Scoop litter", category: .catCare))
        XCTAssertNil(EscalationCopy.subtitle(stage: .dueToday, title: "Vacuum", category: .chore))
    }

    func testNudgeNamesTheChoreMidSentence() {
        XCTAssertEqual(EscalationCopy.subtitle(stage: .nudge, title: "Scoop litter", category: .catCare), "Still no scoop litter…")
        XCTAssertEqual(EscalationCopy.subtitle(stage: .nudge, title: "Vacuum", category: .chore), "Still no vacuum…")
    }

    func testPointedDependsOnCategory() {
        XCTAssertEqual(EscalationCopy.subtitle(stage: .pointed, title: "Scoop litter", category: .catCare), "The cat has feelings about this.")
        XCTAssertEqual(EscalationCopy.subtitle(stage: .pointed, title: "Vacuum", category: .chore), "Getting overdue.")
    }

    func testAlertCapitalizesTheChore() {
        XCTAssertEqual(EscalationCopy.subtitle(stage: .alert, title: "scoop litter", category: .catCare), "Scoop litter emergency")
        XCTAssertEqual(EscalationCopy.subtitle(stage: .alert, title: "Vacuum", category: .chore), "Vacuum emergency")
    }

    func testEveryOverdueStageForEveryCategoryHasCopy() {
        for stage in EscalationStage.allCases where stage != .dueToday {
            for category in ChoreCategory.allCases {
                XCTAssertNotNil(EscalationCopy.subtitle(stage: stage, title: "Laundry", category: category), "\(stage) \(category)")
            }
        }
    }

    func testRowsFlowThroughTheStage() throws {
        let cal = HouseholdCalendar()
        let chores = try ChoreList.load(from: ChoreSeeder.bundledChoresURL(bundle: Bundle(for: RoostAppMarker.self))).chores
        let start = cal.date(year: 2026, month: 9, day: 1)

        // day one: everything is dueToday, nothing has a subtitle
        let fresh = TodayPlanner.plan(chores: chores, completions: [], asOf: start, activeFrom: cal.startOfDay(start), calendar: cal)
        for row in fresh.rows(for: .anne) + fresh.rows(for: .wes) {
            XCTAssertNil(EscalationCopy.subtitle(for: row), row.chore.title)
        }

        // five days later the dailies are alert
        let later = cal.date(year: 2026, month: 9, day: 6)
        let plan = TodayPlanner.plan(chores: chores, completions: [], asOf: later, activeFrom: cal.startOfDay(start), calendar: cal)
        let daily = try XCTUnwrap((plan.rows(for: .anne) + plan.rows(for: .wes)).first { $0.chore.cadence == .daily })
        XCTAssertEqual(daily.stage, .alert)
        XCTAssertEqual(EscalationCopy.subtitle(for: daily), "\(daily.chore.title.uppercasedFirst) emergency")

        // a done row never gets a subtitle
        let doneRow = TodayRow(chore: daily.chore, person: daily.person, kind: .done(completionId: "x"))
        XCTAssertNil(EscalationCopy.subtitle(for: doneRow))
    }
}
