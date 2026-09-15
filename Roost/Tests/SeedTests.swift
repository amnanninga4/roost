@testable import Roost
import RoostCore
import SwiftData
import XCTest

@MainActor
final class SeedTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext {
        container.mainContext
    }

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: RoostSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// The real data/chores.json, bundled into the app target as a resource.
    private func bundledURL() throws -> URL {
        try ChoreSeeder.bundledChoresURL(bundle: Bundle(for: RoostAppMarker.self))
    }

    private func activeChores() throws -> [ChoreRecord] {
        try context.fetch(FetchDescriptor<ChoreRecord>(
            predicate: #Predicate { !$0.retired },
            sortBy: [SortDescriptor(\.sortOrder)]
        ))
    }

    func testSeedLoads41RowsAnd10Pinned() throws {
        let count = try ChoreSeeder.seedIfNeeded(into: context, from: bundledURL())
        XCTAssertEqual(count, 41)

        let rows = try activeChores()
        XCTAssertEqual(rows.count, 41)

        let pinned = rows.filter { $0.fixedAssignee != nil }.map { ($0.id, $0.fixedAssignee!) }
        XCTAssertEqual(pinned.count, 10)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: pinned),
            [
                "laundry": "anne", "wash-all-rugs": "anne", "mow-lawn": "anne", "trim-wes-hair": "anne",
                "garbage-can-to-street-sunday": "wes",
                "change-bed-sheets": "anne", "am-wet-cat-food": "wes", "pm-wet-cat-food": "anne",
                "charge-cat-play-device": "wes", "put-toy-out-for-cats": "anne",
            ]
        )

        let state = try context.fetch(FetchDescriptor<SyncState>())
        XCTAssertEqual(state.count, 1)
        XCTAssertEqual(state.first?.choresVersion, 5)
        XCTAssertEqual(state.first?.cursor, 0)
    }

    func testReseedIsIdempotent() throws {
        try ChoreSeeder.seedIfNeeded(into: context, from: bundledURL())
        try ChoreSeeder.seedIfNeeded(into: context, from: bundledURL())
        try ChoreSeeder.seedIfNeeded(into: context, from: bundledURL())

        XCTAssertEqual(try activeChores().count, 41)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChoreRecord>()).count, 41, "no duplicate rows")
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncState>()).count, 1, "single SyncState row")
    }

    func testChoreRemovedFromFileIsRetiredAndReaddedIsRestored() throws {
        let full = try ChoreList.load(from: bundledURL())
        try ChoreSeeder.seed(full, into: context)

        let trimmed = ChoreList(version: 6, chores: full.chores.filter { $0.id != "scoop-litter" })
        try ChoreSeeder.seed(trimmed, into: context)
        XCTAssertEqual(try activeChores().count, 40)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChoreRecord>()).count, 41, "retired row kept for history")
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncState>()).first?.choresVersion, 6)

        try ChoreSeeder.seed(full, into: context)
        XCTAssertEqual(try activeChores().count, 41, "re-adding un-retires")
    }

    func testConverterRoundTrip() throws {
        let list = try ChoreList.load(from: bundledURL())
        for (i, chore) in list.chores.enumerated() {
            let record = ChoreRecord(chore, sortOrder: i)
            XCTAssertEqual(try record.toChore(), chore)
        }

        let done = Completion(
            id: "c-1",
            choreId: "laundry",
            person: .anne,
            completedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let record = CompletionRecord(done)
        XCTAssertNil(record.syncedAt)
        XCTAssertFalse(record.removed)
        XCTAssertEqual(try record.toCompletion(), done)

        record.removed = true
        XCTAssertNil(try record.toCompletion(), "soft-deleted rows are invisible to RoostCore")

        let bad = ChoreRecord(
            id: "x",
            title: "x",
            cadence: "fortnightly",
            fixedAssignee: nil,
            category: "chore",
            sortOrder: 0
        )
        XCTAssertThrowsError(try bad.toChore())
    }

    func testSeasonAndTogetherRoundTripThroughTheRecord() throws {
        let mowing = Chore(id: "mow-lawn", title: "Mow lawn", cadence: .weekly, fixedAssignee: .anne,
                           category: .chore, season: Season(months: [4, 5, 6, 7, 8, 9, 10]))
        let pantry = Chore(id: "clean-out-fridge-pantry", title: "Clean out fridge and pantry",
                           cadence: .quarterly, category: .chore, together: true)
        try ChoreSeeder.seed(ChoreList(version: 2, chores: [mowing, pantry]), into: context)
        let rows = try activeChores()
        XCTAssertEqual(try rows.map { try $0.toChore() }, [mowing, pantry])
        XCTAssertEqual(rows[0].together, false)
        XCTAssertEqual(rows[1].together, true)
        XCTAssertEqual(rows[1].season, nil)
        XCTAssertNotNil(rows[0].season)

        // Re-seeding without the season clears it; a broken season text is a conversion error, not a crash.
        let plain = Chore(id: "mow-lawn", title: "Mow lawn", cadence: .weekly, fixedAssignee: .anne, category: .chore)
        try ChoreSeeder.seed(ChoreList(version: 3, chores: [plain, pantry]), into: context)
        XCTAssertNil(try activeChores()[0].season)
        rows[0].season = "{not json"
        XCTAssertThrowsError(try rows[0].toChore())
    }

    func testWindowsRoundTripThroughTheRecord() throws {
        let can = Chore(id: "garbage-can-to-street-sunday", title: "Garbage can to street, Sunday", cadence: .weekly,
                        fixedAssignee: .wes, category: .chore, weekdays: [7])
        let litter = Chore(
            id: "change-litter",
            title: "Change litter",
            cadence: .monthly,
            category: .catCare,
            dueDay: 25
        )
        let laundry = Chore(id: "laundry", title: "Laundry", cadence: .weekly, fixedAssignee: .anne, category: .chore)
        try ChoreSeeder.seed(ChoreList(version: 4, chores: [can, litter, laundry]), into: context)
        let rows = try activeChores()
        XCTAssertEqual(try rows.map { try $0.toChore() }, [can, litter, laundry])
        XCTAssertEqual(rows[0].weekdays, "[7]")
        XCTAssertNil(rows[0].dueDay)
        XCTAssertNil(rows[1].weekdays)
        XCTAssertEqual(rows[1].dueDay, 25)
        XCTAssertNil(rows[2].weekdays)
        XCTAssertNil(rows[2].dueDay)

        // Re-seeding without the window clears it; broken weekday text is a conversion error, not a crash.
        let plainCan = Chore(id: can.id, title: can.title, cadence: .weekly, fixedAssignee: .wes, category: .chore)
        try ChoreSeeder.seed(ChoreList(version: 5, chores: [plainCan, litter, laundry]), into: context)
        XCTAssertNil(try activeChores()[0].weekdays)
        rows[0].weekdays = "[not json"
        XCTAssertThrowsError(try rows[0].toChore())
    }

    func testRotationsRoundTripThroughTheRecord() throws {
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
        let laundry = Chore(id: "laundry", title: "Laundry", cadence: .weekly, fixedAssignee: .anne, category: .chore)
        try ChoreSeeder.seed(ChoreList(version: 5, chores: [scoop, change, laundry]), into: context)
        let rows = try activeChores()
        XCTAssertEqual(try rows.map { try $0.toChore() }, [scoop, change, laundry])
        XCTAssertNotNil(rows[0].rotation)
        XCTAssertNil(rows[0].missPenalty)
        XCTAssertEqual(
            try JSONDecoder().decode(ChoreRotation.self, from: Data(XCTUnwrap(rows[0].rotation?.utf8))),
            scoop.rotation
        )
        XCTAssertNotNil(rows[1].rotation)
        XCTAssertNotNil(rows[1].missPenalty)
        XCTAssertEqual(
            try JSONDecoder().decode(ChoreRotation.self, from: Data(XCTUnwrap(rows[1].rotation?.utf8))),
            change.rotation
        )
        XCTAssertEqual(
            try JSONDecoder().decode(MissPenalty.self, from: Data(XCTUnwrap(rows[1].missPenalty?.utf8))),
            change.missPenalty
        )
        XCTAssertNil(rows[2].rotation)
        XCTAssertNil(rows[2].missPenalty)

        // Re-seeding without the keys clears them; broken rotation text is a conversion error, not a crash.
        let plainScoop = Chore(id: scoop.id, title: scoop.title, cadence: .daily, category: .catCare)
        let plainChange = Chore(id: change.id, title: change.title, cadence: .monthly, category: .catCare, dueDay: 25)
        try ChoreSeeder.seed(ChoreList(version: 6, chores: [plainScoop, plainChange, laundry]), into: context)
        let cleared = try activeChores()
        XCTAssertNil(cleared[0].rotation)
        XCTAssertNil(cleared[0].missPenalty)
        XCTAssertNil(cleared[1].rotation)
        XCTAssertNil(cleared[1].missPenalty)
        rows[0].rotation = "{not json"
        XCTAssertThrowsError(try rows[0].toChore())
    }
}
