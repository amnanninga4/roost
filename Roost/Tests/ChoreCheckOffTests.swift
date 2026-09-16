// What a check-off means, in one place, tested against a real store. Before this existed the
// answer lived privately inside TodayScreen, which is why Home could not tick a box.
@testable import Roost
import RoostCore
import SwiftData
import XCTest

@MainActor
final class ChoreCheckOffTests: XCTestCase {
    private func freshContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ChoreRecord.self, CompletionRecord.self, HandoffRecord.self, SyncState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    func testCheckingADueRowInsertsOneCompletion() throws {
        let context = try freshContext()
        let row = TodayRowFixture.due(chore: "scoop-litter", person: .wes)
        var celebration = TodayBoard.Celebration()

        let outcome = ChoreCheckOff.toggle(
            row, among: [row], me: .wes, completions: [], celebration: &celebration,
            calendar: HouseholdCalendar(), context: context, sync: nil, now: TodayRowFixture.noon
        )

        let saved = try context.fetch(FetchDescriptor<CompletionRecord>())
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.choreId, "scoop-litter")
        XCTAssertEqual(saved.first?.person, Person.wes.rawValue)
        if case .checked = outcome {} else {
            XCTFail("expected .checked, got \(outcome)")
        }
    }

    func testUncheckingMarksTheCompletionRemoved() throws {
        let context = try freshContext()
        let completion = CompletionRecord(
            id: "c1", choreId: "scoop-litter", person: Person.wes.rawValue, completedAt: TodayRowFixture.noon
        )
        context.insert(completion)
        let row = TodayRowFixture.done(chore: "scoop-litter", person: .wes, completionId: "c1")
        var celebration = TodayBoard.Celebration()

        let outcome = ChoreCheckOff.toggle(
            row, among: [row], me: .wes, completions: [completion], celebration: &celebration,
            calendar: HouseholdCalendar(), context: context, sync: nil, now: TodayRowFixture.noon
        )

        XCTAssertTrue(completion.removed)
        if case .unchecked = outcome {} else {
            XCTFail("expected .unchecked, got \(outcome)")
        }
    }

    /// A completion that never reached the server has nothing to replay, so it is marked as
    /// already-deleted rather than queued as a deletion.
    func testUncheckingAnUnsyncedCompletionNeedsNoDeleteReplay() throws {
        let context = try freshContext()
        let completion = CompletionRecord(
            id: "c1", choreId: "scoop-litter", person: Person.wes.rawValue, completedAt: TodayRowFixture.noon
        )
        context.insert(completion)
        let row = TodayRowFixture.done(chore: "scoop-litter", person: .wes, completionId: "c1")
        var celebration = TodayBoard.Celebration()

        _ = ChoreCheckOff.toggle(
            row, among: [row], me: .wes, completions: [completion], celebration: &celebration,
            calendar: HouseholdCalendar(), context: context, sync: nil, now: TodayRowFixture.noon
        )

        XCTAssertTrue(completion.deleteSynced)
    }

    func testClearingYourLastRowCelebratesOnceOnly() throws {
        let context = try freshContext()
        let row = TodayRowFixture.due(chore: "scoop-litter", person: .wes)
        var celebration = TodayBoard.Celebration()

        let first = ChoreCheckOff.toggle(
            row, among: [row], me: .wes, completions: [], celebration: &celebration,
            calendar: HouseholdCalendar(), context: context, sync: nil, now: TodayRowFixture.noon
        )
        let second = ChoreCheckOff.toggle(
            row, among: [row], me: .wes, completions: [], celebration: &celebration,
            calendar: HouseholdCalendar(), context: context, sync: nil, now: TodayRowFixture.noon
        )

        guard case let .checked(firstCelebrates) = first, case let .checked(secondCelebrates) = second else {
            return XCTFail("expected two .checked outcomes")
        }
        XCTAssertTrue(firstCelebrates)
        XCTAssertFalse(secondCelebrates, "the celebration fires once a day, not once a tap")
    }
}

enum TodayRowFixture {
    static let calendar = HouseholdCalendar()
    static let noon = calendar.date(year: 2026, month: 9, day: 10, hour: 12)

    static func due(chore id: String, person: Person) -> TodayRow {
        let chore = Chore(
            id: id,
            title: "Fixture \(id)",
            cadence: .daily,
            fixedAssignee: person,
            category: .chore
        )
        let day = calendar.startOfDay(noon)
        let plan = TodayPlanner.plan(
            chores: [chore],
            completions: [],
            asOf: noon,
            activeFrom: day,
            calendar: calendar
        )
        guard let row = plan.rows(for: person).first else {
            fatalError("failed to plan due row for \(person) / \(id)")
        }
        return row
    }

    static func done(chore id: String, person: Person, completionId: String) -> TodayRow {
        let base = due(chore: id, person: person)
        return TodayRow(
            chore: base.chore,
            person: person,
            kind: .done(completionId: completionId),
            handoff: base.handoff
        )
    }
}
