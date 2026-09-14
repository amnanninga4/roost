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

    func testSeedLoads31RowsAnd2Pinned() throws {
        let count = try ChoreSeeder.seedIfNeeded(into: context, from: bundledURL())
        XCTAssertEqual(count, 31)

        let rows = try activeChores()
        XCTAssertEqual(rows.count, 31)

        let pinned = rows.filter { $0.fixedAssignee != nil }.map { ($0.id, $0.fixedAssignee!) }
        XCTAssertEqual(pinned.count, 2)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: pinned),
            ["laundry": "anne", "garbage-can-to-street-sunday": "wes"]
        )

        let state = try context.fetch(FetchDescriptor<SyncState>())
        XCTAssertEqual(state.count, 1)
        XCTAssertEqual(state.first?.choresVersion, 1)
        XCTAssertEqual(state.first?.cursor, 0)
    }

    func testReseedIsIdempotent() throws {
        try ChoreSeeder.seedIfNeeded(into: context, from: bundledURL())
        try ChoreSeeder.seedIfNeeded(into: context, from: bundledURL())
        try ChoreSeeder.seedIfNeeded(into: context, from: bundledURL())

        XCTAssertEqual(try activeChores().count, 31)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChoreRecord>()).count, 31, "no duplicate rows")
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncState>()).count, 1, "single SyncState row")
    }

    func testChoreRemovedFromFileIsRetiredAndReaddedIsRestored() throws {
        let full = try ChoreList.load(from: bundledURL())
        try ChoreSeeder.seed(full, into: context)

        let trimmed = ChoreList(version: 2, chores: full.chores.filter { $0.id != "scoop-litter" })
        try ChoreSeeder.seed(trimmed, into: context)
        XCTAssertEqual(try activeChores().count, 30)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChoreRecord>()).count, 31, "retired row kept for history")
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncState>()).first?.choresVersion, 2)

        try ChoreSeeder.seed(full, into: context)
        XCTAssertEqual(try activeChores().count, 31, "re-adding un-retires")
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
}
