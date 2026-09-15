@testable import RoostCore
import XCTest

/// Reads the real repo file so the package can never drift from data/chores.json unnoticed.
func repoChoresURL(file: String = #filePath) -> URL {
    // …/Packages/RoostCore/Tests/RoostCoreTests/ChoreListTests.swift → repo root is five levels up.
    var url = URL(fileURLWithPath: file)
    for _ in 0 ..< 5 {
        url.deleteLastPathComponent()
    }
    return url.appendingPathComponent("data/chores.json")
}

final class ChoreListTests: XCTestCase {
    func testRealSeedHas41ChoresTenPinsAndFifteenWindows() throws {
        let list = try ChoreList.load(from: repoChoresURL())
        XCTAssertEqual(list.version, 5)
        XCTAssertEqual(list.chores.count, 41)
        XCTAssertEqual(Set(list.chores.map(\.id)).count, 41, "ids unique")

        let pinned = Dictionary(uniqueKeysWithValues: list.pinned.map { ($0.id, $0.fixedAssignee!) })
        XCTAssertEqual(pinned, [
            "laundry": .anne, "wash-all-rugs": .anne, "mow-lawn": .anne, "trim-wes-hair": .anne,
            "garbage-can-to-street-sunday": .wes,
            "change-bed-sheets": .anne, "am-wet-cat-food": .wes, "pm-wet-cat-food": .anne,
            "charge-cat-play-device": .wes, "put-toy-out-for-cats": .anne,
        ])

        let counts = Dictionary(grouping: list.chores, by: \.cadence).mapValues(\.count)
        XCTAssertEqual(counts, [.daily: 13, .weekly: 12, .biweekly: 5, .monthly: 7, .bimonthly: 1, .quarterly: 3])
        XCTAssertEqual(list.chores.filter { $0.category == .catCare }.count, 7)

        XCTAssertEqual(list["mow-lawn"]?.season, Season(months: [4, 5, 6, 7, 8, 9, 10]))
        XCTAssertEqual(list.chores.filter(\.together).map(\.id), ["clean-out-fridge-pantry"])
        XCTAssertNil(list["take-out-garbages"], "split into three")
        XCTAssertNil(list["clean-out-fridge"], "replaced")
        // Grouped by cadence in Cadence.allCases order: the order is sortOrder on both stores.
        let ranks = list.chores.map { Cadence.allCases.firstIndex(of: $0.cadence)! }
        XCTAssertEqual(ranks, ranks.sorted())

        let weekdays = Dictionary(uniqueKeysWithValues: list.chores.compactMap { c in c.weekdays.map { (c.id, $0) } })
        XCTAssertEqual(weekdays, [
            "take-out-garbage-basement": [5, 6], "take-out-garbage-bathroom": [5, 6],
            "take-out-garbage-kitchen": [5, 6], "garbage-can-to-street-sunday": [7],
        ])
        let dueDays = Dictionary(uniqueKeysWithValues: list.chores.compactMap { c in c.dueDay.map { (c.id, $0) } })
        XCTAssertEqual(dueDays, [
            "clean-under-cushions": 5, "wash-all-rugs": 8, "trim-wes-hair": 10, "clean-inside-ovens": 12,
            "clean-garbage-cans": 14, "wipe-dust-bar-cart": 15, "clean-under-couches": 19, "wipe-down-doors": 21,
            "clean-medicine-cabinet": 22, "change-litter": 25, "clean-out-fridge-pantry": 28,
        ])
        XCTAssertTrue(list.chores.filter { $0.cadence.monthsPerPeriod != nil }.allSatisfy { $0.dueDay != nil })
        XCTAssertEqual(list.chores.filter(\.hasWindow).count, 15)

        XCTAssertEqual(
            list["scoop-litter"]?.rotation,
            .weekdayCycle(weeks: [
                [.anne, .wes, .anne, .wes, .anne, .wes, .anne],
                [.wes, .anne, .wes, .anne, .wes, .anne, .wes],
            ])
        )
        XCTAssertEqual(list["change-litter"]?.rotation, .alternate(start: .wes))
        XCTAssertEqual(list["change-litter"]?.missPenalty, MissPenalty(watch: "scoop-litter", overMisses: 2))
        XCTAssertEqual(list.chores.filter { $0.rotation != nil }.count, 2)
        XCTAssertEqual(list.chores.filter { $0.missPenalty != nil }.count, 1)
        XCTAssertTrue(list.chores.allSatisfy { $0.rotation == nil || $0.fixedAssignee == nil })
    }

    func testSeasonAndTogetherDecodeAndDefault() throws {
        let json = """
        {
          "version": 2,
          "chores": [
            { "id": "mow-lawn", "title": "Mow lawn", "cadence": "weekly", "fixedAssignee": "anne",
              "category": "chore", "season": { "months": [4, 5, 6, 7, 8, 9, 10] } },
            { "id": "clean-out-fridge-pantry", "title": "Clean out fridge and pantry", "cadence": "quarterly",
              "fixedAssignee": null, "category": "chore", "together": true },
            { "id": "scoop-litter", "title": "Scoop litter", "cadence": "daily", "fixedAssignee": null,
              "category": "cat_care" }
          ]
        }
        """
        let list = try ChoreList.load(json: Data(json.utf8))
        XCTAssertEqual(list["mow-lawn"]?.season, Season(months: [4, 5, 6, 7, 8, 9, 10]))
        XCTAssertEqual(list["mow-lawn"]?.together, false)
        XCTAssertTrue(list["mow-lawn"]?.season?.contains(month: 10) ?? false)
        XCTAssertFalse(list["mow-lawn"]?.season?.contains(month: 11) ?? true)
        XCTAssertEqual(list["clean-out-fridge-pantry"]?.together, true)
        XCTAssertNil(list["clean-out-fridge-pantry"]?.season)
        XCTAssertFalse(list["clean-out-fridge-pantry"]?.isPinned ?? true, "together is not a pin")
        XCTAssertNil(list["scoop-litter"]?.season, "absent keys are the defaults")
        XCTAssertEqual(list["scoop-litter"]?.together, false)
        XCTAssertEqual(
            list["scoop-litter"],
            Chore(id: "scoop-litter", title: "Scoop litter", cadence: .daily, category: .catCare),
            "the memberwise init and the decoder agree on the defaults"
        )
        // Round trip: what we encode, we decode.
        let data = try JSONEncoder().encode(list.chores)
        XCTAssertEqual(try JSONDecoder().decode([Chore].self, from: data), list.chores)
    }

    func testWindowKeysDecodeAndDefault() throws {
        let v3 = #"{"id":"x","title":"X","cadence":"weekly","fixedAssignee":null,"category":"chore"}"#
        let plain = try JSONDecoder().decode(Chore.self, from: Data(v3.utf8))
        XCTAssertNil(plain.weekdays); XCTAssertNil(plain.dueDay); XCTAssertFalse(plain.hasWindow)

        let v4 = #"{"id":"g","title":"G","cadence":"weekly","fixedAssignee":null,"category":"chore","weekdays":[5,6]}"#
        let garbage = try JSONDecoder().decode(Chore.self, from: Data(v4.utf8))
        XCTAssertEqual(garbage.weekdays, [5, 6]); XCTAssertTrue(garbage.hasWindow)

        let litter = Chore(id: "l", title: "L", cadence: .monthly, category: .catCare, dueDay: 25)
        let round = try JSONDecoder().decode(Chore.self, from: JSONEncoder().encode(litter))
        XCTAssertEqual(round.dueDay, 25); XCTAssertEqual(round, litter)
    }

    func testRotationAndPenaltyDecodeAndDefault() throws {
        let plain = #"{"id":"x","title":"X","cadence":"daily","fixedAssignee":null,"category":"chore"}"#
        let bare = try JSONDecoder().decode(Chore.self, from: Data(plain.utf8))
        XCTAssertNil(bare.rotation); XCTAssertNil(bare.missPenalty)

        let cycle =
            #"{"id":"s","title":"S","cadence":"daily","fixedAssignee":null,"category":"cat_care","# +
            #"rotation":{"kind":"weekdayCycle","weeks":[["anne","wes","anne","wes","anne","wes","anne"]]}}"#
        let scoop = try JSONDecoder().decode(Chore.self, from: Data(cycle.utf8))
        XCTAssertEqual(scoop.rotation, .weekdayCycle(weeks: [[.anne, .wes, .anne, .wes, .anne, .wes, .anne]]))

        let change = Chore(id: "c", title: "C", cadence: .monthly, category: .catCare,
                           rotation: .alternate(start: .wes),
                           missPenalty: MissPenalty(watch: "s", overMisses: 2))
        let round = try JSONDecoder().decode(Chore.self, from: JSONEncoder().encode(change))
        XCTAssertEqual(round, change)
    }
}
