@testable import Roost
import RoostCore
import SwiftData
import XCTest

/// Kitchen mode's model, built through the store the way the screen builds it (records in an in-memory
/// container → TodayPlanner → KitchenModel).
@MainActor
final class KitchenModelTests: XCTestCase {
    private let cal = HouseholdCalendar()
    private var container: ModelContainer!
    private var context: ModelContext {
        container.mainContext
    }

    /// Household started Sep 1, 2026. Every chore is pinned so assignment is fixed.
    private let activeFrom = HouseholdCalendar().startOfDay(HouseholdCalendar().date(year: 2026, month: 9, day: 1))
    private let sep6 = HouseholdCalendar().date(year: 2026, month: 9, day: 6, hour: 7)

    private let chores: [Chore] = [
        Chore(id: "scoop-litter", title: "Scoop litter", cadence: .daily, fixedAssignee: .anne, category: .catCare),
        Chore(id: "wipe-tables", title: "Wipe down tables", cadence: .daily, fixedAssignee: .anne, category: .chore),
        Chore(id: "vacuum-basement", title: "Vacuum basement", cadence: .daily, fixedAssignee: .anne, category: .chore),
        Chore(id: "laundry", title: "Laundry", cadence: .weekly, fixedAssignee: .anne, category: .chore),
        Chore(
            id: "refill-cat-water",
            title: "Refill cat water",
            cadence: .daily,
            fixedAssignee: .wes,
            category: .catCare
        ),
        Chore(id: "garbage", title: "Garbage can to street", cadence: .daily, fixedAssignee: .wes, category: .chore),
        Chore(id: "water-plants", title: "Water plants", cadence: .daily, fixedAssignee: .wes, category: .chore),
    ]

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: RoostSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func seed(_ chores: [Chore], completions: [(
        id: String,
        choreId: String,
        person: Person,
        day: Int
    )]) throws {
        try ChoreSeeder.seed(ChoreList(version: 1, chores: chores), into: context)
        try ChoreSeeder.syncState(in: context).activeFrom = activeFrom
        for c in completions {
            context.insert(CompletionRecord(id: c.id, choreId: c.choreId, person: c.person.rawValue,
                                            completedAt: cal.date(year: 2026, month: 9, day: c.day), syncedAt: Date()))
        }
        try context.save()
    }

    /// The screen's path: active chores + live completions + SyncState.activeFrom.
    private func model(asOf date: Date) throws -> KitchenModel {
        let chores = try context.fetch(FetchDescriptor<ChoreRecord>(
            predicate: #Predicate { !$0.retired },
            sortBy: [SortDescriptor(\.sortOrder)]
        ))
        let completions = try context.fetch(FetchDescriptor<CompletionRecord>(predicate: #Predicate { !$0.removed }))
        let state = try context.fetch(FetchDescriptor<SyncState>()).first
        return KitchenModel(
            chores: chores,
            completions: completions,
            activeFrom: state?.activeFrom,
            asOf: date,
            calendar: cal
        )
    }

    /// As of Sep 6:
    ///   Anne  scoop-litter done Sep 4 → 1 day late (nudge, cat)
    ///         wipe-tables done Sep 2 → 3 days late (pointed, home)
    ///         vacuum-basement never → 5 days late (alert)
    ///         laundry: week Aug 31–Sep 6 still open → due today
    ///   Wes   refill-cat-water never → 5 days late (alert, cat)
    ///         garbage done Sep 5 → due today
    ///         water-plants done Sep 3 → 2 days late (nudge)
    private func seedFixture() throws {
        try seed(chores, completions: [
            ("c1", "scoop-litter", .anne, 4),
            ("c2", "wipe-tables", .anne, 2),
            ("c3", "garbage", .wes, 5),
            ("c4", "water-plants", .wes, 3),
        ])
    }

    func testGroupsOverdueByPersonSortedByStageDescending() throws {
        try seedFixture()
        let m = try model(asOf: sep6)

        XCTAssertEqual(m.columns.map(\.person), [.anne, .wes], "Anne then Wes, always both")
        XCTAssertFalse(m.isCaughtUp)

        let anne = m.column(for: .anne)
        XCTAssertEqual(anne.dueCount, 4, "everything owed today, overdue included")
        XCTAssertEqual(anne.overdue.map(\.chore.id), ["vacuum-basement", "wipe-tables", "scoop-litter"])
        XCTAssertEqual(anne.overdue.map(\.stage), [.alert, .pointed, .nudge])
        XCTAssertEqual(anne.overdue.map(\.daysOverdue), [5, 3, 1])
        XCTAssertEqual(
            anne.overdue.map(\.copy),
            ["Vacuum basement emergency", "Getting overdue.", "Still no scoop litter…"]
        )
        XCTAssertTrue(anne.overdue.allSatisfy { $0.person == .anne })

        let wes = m.column(for: .wes)
        XCTAssertEqual(wes.dueCount, 3)
        XCTAssertEqual(wes.overdue.map(\.chore.id), ["refill-cat-water", "water-plants"])
        XCTAssertEqual(wes.overdue.map(\.stage), [.alert, .nudge])
        XCTAssertEqual(wes.overdue.map(\.copy), ["Refill cat water emergency", "Still no water plants…"])
        XCTAssertFalse(
            wes.overdue.contains { $0.chore.id == "laundry" } || anne.overdue.contains { $0.chore.id == "laundry" },
            "due today is not overdue"
        )
        XCTAssertFalse(wes.overdue.contains { $0.chore.id == "garbage" }, "done for today is not overdue")
    }

    func testAlertStageItemsFromBothPeopleAppearInTheBanner() throws {
        try seedFixture()
        let m = try model(asOf: sep6)

        XCTAssertEqual(
            m.alerts.map(\.chore.id),
            ["vacuum-basement", "refill-cat-water"],
            "both 5 days late; Anne first on a tie"
        )
        XCTAssertEqual(m.alerts.map(\.person), [.anne, .wes])
        XCTAssertTrue(m.alerts.allSatisfy { $0.stage == .alert })
        XCTAssertEqual(Set(m.alerts.map(\.person)), Set(Person.allCases), "one alert per person in the fixture")
        XCTAssertFalse(
            m.alerts.contains { $0.chore.id == "wipe-tables" },
            "pointed stays in the column, out of the banner"
        )

        // the alert items are still listed in their person's column
        XCTAssertTrue(m.column(for: .anne).overdue.contains { $0.chore.id == "vacuum-basement" })
        XCTAssertTrue(m.column(for: .wes).overdue.contains { $0.chore.id == "refill-cat-water" })
    }

    func testMostOverdueAlertLeadsTheBanner() throws {
        // Wes's cat water never done since Sep 1 → 7 days late on Sep 8; Anne's vacuum done Sep 2 → Sep 3 missed → 5
        // days late.
        let two = chores.filter { ["refill-cat-water", "vacuum-basement"].contains($0.id) }
        try seed(two, completions: [("c1", "vacuum-basement", .anne, 2)])
        let sep8 = cal.date(year: 2026, month: 9, day: 8, hour: 7)
        let m = try model(asOf: sep8)
        XCTAssertEqual(
            m.alerts.map(\.chore.id),
            ["refill-cat-water", "vacuum-basement"],
            "7 days late leads 5 days late even though Anne's column comes first"
        )
        XCTAssertEqual(m.alerts.map(\.daysOverdue), [7, 5])
        XCTAssertEqual(m.alerts.map(\.person), [.wes, .anne])
    }

    func testEmptyPlanIsCaughtUp() {
        let day = cal.date(year: 2026, month: 9, day: 13)
        let m = KitchenModel(plan: TodayPlanner.plan(
            chores: [],
            completions: [],
            asOf: day,
            activeFrom: cal.startOfDay(day),
            calendar: cal
        ))
        XCTAssertTrue(m.isCaughtUp)
        XCTAssertEqual(m.alerts, [])
        XCTAssertEqual(m.columns.map(\.person), [.anne, .wes])
        XCTAssertEqual(m.columns.map(\.dueCount), [0, 0])
        XCTAssertTrue(m.columns.allSatisfy(\.overdue.isEmpty))
        XCTAssertEqual(m.date, day)
    }

    func testDueTodayWithNothingOverdueIsAlsoCaughtUp() throws {
        // a fresh install: the household started today, so everything is due and nothing is late
        try seed(chores, completions: [])
        let dayOne = cal.date(year: 2026, month: 9, day: 1, hour: 9)
        let m = try model(asOf: dayOne)
        XCTAssertTrue(m.isCaughtUp)
        XCTAssertEqual(m.alerts, [])
        XCTAssertEqual(m.column(for: .anne).dueCount, 4)
        XCTAssertEqual(m.column(for: .wes).dueCount, 3)
    }

    func testFiveDayOverdueLitterBoxForWesIsAnEmergencyInTheBanner() throws {
        try seed(
            [Chore(
                id: "scoop-litter",
                title: "Scoop litter",
                cadence: .daily,
                fixedAssignee: .wes,
                category: .catCare
            )],
            completions: []
        )
        let m = try model(asOf: sep6)

        XCTAssertEqual(m.alerts.count, 1)
        let alert = try XCTUnwrap(m.alerts.first)
        XCTAssertEqual(alert.person, .wes)
        XCTAssertEqual(alert.daysOverdue, 5)
        XCTAssertEqual(alert.stage, .alert)
        XCTAssertEqual(alert.copy, "Scoop litter emergency")
        XCTAssertEqual(m.column(for: .wes).overdue, [alert])
        XCTAssertEqual(m.column(for: .anne).overdue, [])
        XCTAssertFalse(m.isCaughtUp)
    }

    func testActiveFromFallsBackToTodayWhenUnset() throws {
        try ChoreSeeder.seed(ChoreList(version: 1, chores: chores), into: context)
        try context.save()
        // no SyncState.activeFrom: nothing before today counts, so nothing can be overdue
        let m = try model(asOf: sep6)
        XCTAssertTrue(m.isCaughtUp)
        XCTAssertEqual(m.column(for: .anne).dueCount + m.column(for: .wes).dueCount, 7)
    }

    /// An overdue chore somebody took over says so on the counter, the same "from Anne" chip the Tasks tab
    /// puts on the row: whose turn it was this period is the first thing you want to know about it.
    func testAnOverdueCardCarriesTheHandoffChip() throws {
        try seed(chores, completions: [])
        let storedChores = try context.fetch(
            FetchDescriptor<ChoreRecord>(predicate: #Predicate { !$0.retired }, sortBy: [SortDescriptor(\.sortOrder)])
        )
        let vacuum = try XCTUnwrap(chores.first { $0.id == "vacuum-basement" }) // daily, pinned to Anne
        let day = cal.date(year: 2026, month: 9, day: 3, hour: 9)
        let record = HandoffRecord(
            id: "h-kitchen",
            choreId: vacuum.id,
            fromPerson: Person.anne.rawValue,
            toPerson: Person.wes.rawValue,
            periodIndex: cal.periodIndex(.daily, containing: day),
            cadence: Cadence.daily.rawValue,
            state: Handoff.State.accepted.rawValue,
            createdAt: day,
            syncedAt: day
        )
        context.insert(record)
        try context.save()

        // As of Sep 6 the Sep 3 daily is three days late, and it is Wes's because he took that turn.
        let model = KitchenModel(
            chores: storedChores,
            completions: [],
            handoffs: [record],
            activeFrom: cal.startOfDay(day),
            asOf: sep6,
            calendar: cal
        )
        let taken = try XCTUnwrap(model.column(for: .wes).overdue.first { $0.chore.id == vacuum.id })
        XCTAssertEqual(taken.handedOverBy, .anne)
        XCTAssertEqual(taken.daysOverdue, 3)
        XCTAssertFalse(model.column(for: .anne).overdue.contains { $0.chore.id == vacuum.id })
        // Every other overdue card is nobody's hand-me-down.
        let others = (model.column(for: .anne).overdue + model.column(for: .wes).overdue)
            .filter { $0.chore.id != vacuum.id }
        XCTAssertFalse(others.isEmpty)
        XCTAssertTrue(others.allSatisfy { $0.handedOverBy == nil })
    }

    func testATogetherAlertIsInBothColumnsAndOnceInTheBanner() throws {
        let pantry = Chore(id: "clean-out-fridge-pantry", title: "Clean out fridge and pantry",
                           cadence: .daily, category: .chore, together: true)
        try seed(chores + [pantry], completions: [("c1", "scoop-litter", .anne, 4)])
        // Sep 1 never done → 5 days late on Sep 6 for both of them.
        let m = try model(asOf: sep6)
        XCTAssertTrue(m.column(for: .anne).overdue.contains { $0.chore.id == pantry.id })
        XCTAssertTrue(m.column(for: .wes).overdue.contains { $0.chore.id == pantry.id })
        XCTAssertEqual(m.alerts.filter { $0.chore.id == pantry.id }.count, 1, "the banner says it once")
        XCTAssertEqual(m.alerts.first { $0.chore.id == pantry.id }?.person, .anne)
        XCTAssertEqual(m.alerts.first { $0.chore.id == pantry.id }?.copy, "Clean out fridge and pantry emergency")
    }

    func testSyncedLine() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(KitchenModel.syncedLine(lastSyncAt: nil, now: now), "Not synced yet")
        XCTAssertEqual(KitchenModel.syncedLine(lastSyncAt: now.addingTimeInterval(-20), now: now), "Synced just now")
        let older = KitchenModel.syncedLine(lastSyncAt: now.addingTimeInterval(-5 * 60), now: now)
        XCTAssertTrue(older.hasPrefix("Synced "), older)
        XCTAssertNotEqual(older, "Synced just now")
    }
}
