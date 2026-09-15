// The /sync chores payload: version bumps, and the optional keys (season, together, weekdays,
// dueDay, rotation, missPenalty) surviving the round trip. Split out of SyncTests so swiftlint
// type_body_length stays under the limit.
@testable import Roost
import RoostCore
import SwiftData
import XCTest

final class SyncChoresTests: XCTestCase {
    private var container: ModelContainer!
    private var tokens: InMemoryTokenStore!
    private var client: SyncClient!
    private let base = URL(string: "https://stub.local")!

    override func setUp() async throws {
        container = try ModelContainer(
            for: RoostSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = ModelContext(container)
        try ChoreSeeder.seedIfNeeded(
            into: ctx,
            from: ChoreSeeder.bundledChoresURL(bundle: Bundle(for: RoostAppMarker.self))
        )
        tokens = InMemoryTokenStore()
        client = SyncClient(modelContainer: container)
        await client.configure(
            tokenStore: tokens,
            session: StubURLProtocol.makeSession(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    private func fresh() -> ModelContext {
        ModelContext(container)
    }

    private func state() throws -> SyncState {
        try ChoreSeeder.syncState(in: fresh())
    }

    private func pairAsAnne(cursor: Int = 7) async throws {
        StubURLProtocol.reset { _ in (200, syncJSON(person: "anne", cursor: cursor)) }
        _ = try await client.pair(baseURL: base, token: "anne-token-0123456789abcdef")
    }

    func testDeltaWithChoresReseedsAndBumpsVersion() async throws {
        try await pairAsAnne()
        let trimmed = try ChoreList.load(from: ChoreSeeder.bundledChoresURL(bundle: Bundle(for: RoostAppMarker.self)))
            .chores.filter { $0.id != "scoop-litter" }
            .map { [
                "id": $0.id,
                "title": $0.title,
                "cadence": $0.cadence.rawValue,
                "fixedAssignee": $0.fixedAssignee?.rawValue as Any,
                "category": $0.category.rawValue,
                "season": $0.season.map { ["months": Array($0.months)] } as Any,
                "together": $0.together,
                "weekdays": $0.weekdays as Any,
                "dueDay": $0.dueDay as Any,
                "rotation": $0.rotation.map { rot -> Any in
                    switch rot {
                    case let .weekdayCycle(weeks):
                        ["kind": "weekdayCycle", "weeks": weeks.map { $0.map(\.rawValue) }]
                    case let .alternate(start):
                        ["kind": "alternate", "start": start.rawValue]
                    }
                } as Any,
                "missPenalty": $0.missPenalty.map { ["watch": $0.watch, "overMisses": $0.overMisses] } as Any,
            ] }
        StubURLProtocol.reset { _ in (200, syncJSON(cursor: 7, choresVersion: 6, chores: trimmed)) }
        _ = await client.syncNow()
        XCTAssertEqual(try state().choresVersion, 6)
        let active = try fresh().fetch(FetchDescriptor<ChoreRecord>(predicate: #Predicate { !$0.retired }))
        XCTAssertEqual(active.count, 40)
    }

    func testServerSentChoresCarrySeasonAndTogether() async throws {
        try await pairAsAnne()
        let chores: [[String: Any]] = [
            ["id": "mow-lawn", "title": "Mow lawn", "cadence": "weekly", "fixedAssignee": "anne",
             "category": "chore", "season": ["months": [4, 5, 6, 7, 8, 9, 10]], "together": false],
            ["id": "clean-out-fridge-pantry", "title": "Clean out fridge and pantry", "cadence": "quarterly",
             "fixedAssignee": NSNull(), "category": "chore", "season": NSNull(), "together": true],
            ["id": "scoop-litter", "title": "Scoop litter", "cadence": "daily", "fixedAssignee": NSNull(),
             "category": "cat_care"], // an older server: no keys at all
        ]
        StubURLProtocol.reset { _ in (200, syncJSON(cursor: 7, choresVersion: 2, chores: chores)) }
        _ = await client.syncNow()
        let active = try fresh().fetch(FetchDescriptor<ChoreRecord>(
            predicate: #Predicate { !$0.retired }, sortBy: [SortDescriptor(\.sortOrder)]
        ))
        XCTAssertEqual(active.map(\.id), ["mow-lawn", "clean-out-fridge-pantry", "scoop-litter"])
        XCTAssertEqual(try active[0].toChore().season, Season(months: [4, 5, 6, 7, 8, 9, 10]))
        XCTAssertEqual(active[1].together, true)
        XCTAssertEqual(active[2].together, false)
        XCTAssertNil(active[2].season)
    }

    func testServerSentChoresCarryWindows() async throws {
        try await pairAsAnne()
        let chores: [[String: Any]] = [
            ["id": "garbage-can-to-street-sunday", "title": "Garbage can to street, Sunday", "cadence": "weekly",
             "fixedAssignee": "wes", "category": "chore", "weekdays": [7]],
            ["id": "change-litter", "title": "Change litter", "cadence": "monthly",
             "fixedAssignee": NSNull(), "category": "cat_care", "dueDay": 25],
            ["id": "scoop-litter", "title": "Scoop litter", "cadence": "daily", "fixedAssignee": NSNull(),
             "category": "cat_care"], // an older server: no keys at all
        ]
        StubURLProtocol.reset { _ in (200, syncJSON(cursor: 7, choresVersion: 4, chores: chores)) }
        _ = await client.syncNow()
        let active = try fresh().fetch(FetchDescriptor<ChoreRecord>(
            predicate: #Predicate { !$0.retired }, sortBy: [SortDescriptor(\.sortOrder)]
        ))
        XCTAssertEqual(active.map(\.id), ["garbage-can-to-street-sunday", "change-litter", "scoop-litter"])
        XCTAssertEqual(active[0].weekdays, "[7]")
        XCTAssertNil(active[0].dueDay)
        XCTAssertNil(active[1].weekdays)
        XCTAssertEqual(active[1].dueDay, 25)
        XCTAssertNil(active[2].weekdays)
        XCTAssertNil(active[2].dueDay)
    }

    func testServerSentChoresCarryRotations() async throws {
        try await pairAsAnne()
        let chores: [[String: Any]] = [
            ["id": "scoop-litter", "title": "Scoop litter", "cadence": "daily",
             "fixedAssignee": NSNull(), "category": "cat_care",
             "rotation": ["kind": "weekdayCycle", "weeks": [
                 ["anne", "wes", "anne", "wes", "anne", "wes", "anne"],
                 ["wes", "anne", "wes", "anne", "wes", "anne", "wes"],
             ]]],
            ["id": "change-litter", "title": "Change litter", "cadence": "monthly",
             "fixedAssignee": NSNull(), "category": "cat_care", "dueDay": 25,
             "rotation": ["kind": "alternate", "start": "wes"],
             "missPenalty": ["watch": "scoop-litter", "overMisses": 2]],
            ["id": "laundry", "title": "Laundry", "cadence": "weekly", "fixedAssignee": "anne",
             "category": "chore"], // an older server: no keys at all
        ]
        StubURLProtocol.reset { _ in (200, syncJSON(cursor: 7, choresVersion: 5, chores: chores)) }
        _ = await client.syncNow()
        let active = try fresh().fetch(FetchDescriptor<ChoreRecord>(
            predicate: #Predicate { !$0.retired }, sortBy: [SortDescriptor(\.sortOrder)]
        ))
        XCTAssertEqual(active.map(\.id), ["scoop-litter", "change-litter", "laundry"])
        XCTAssertEqual(
            try active[0].toChore().rotation,
            .weekdayCycle(weeks: [
                [.anne, .wes, .anne, .wes, .anne, .wes, .anne],
                [.wes, .anne, .wes, .anne, .wes, .anne, .wes],
            ])
        )
        XCTAssertNil(try active[0].toChore().missPenalty)
        XCTAssertEqual(try active[1].toChore().rotation, .alternate(start: .wes))
        XCTAssertEqual(try active[1].toChore().missPenalty, MissPenalty(watch: "scoop-litter", overMisses: 2))
        XCTAssertNil(active[2].rotation)
        XCTAssertNil(active[2].missPenalty)
    }
}
