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
    func testRealSeedHas39ChoresAndFivePinned() throws {
        let list = try ChoreList.load(from: repoChoresURL())
        XCTAssertEqual(list.version, 2)
        XCTAssertEqual(list.chores.count, 39)
        XCTAssertEqual(Set(list.chores.map(\.id)).count, 39, "ids unique")

        let pinned = Dictionary(uniqueKeysWithValues: list.pinned.map { ($0.id, $0.fixedAssignee!) })
        XCTAssertEqual(pinned, [
            "laundry": .anne, "wash-all-rugs": .anne, "mow-lawn": .anne, "trim-wes-hair": .anne,
            "garbage-can-to-street-sunday": .wes,
        ])

        let counts = Dictionary(grouping: list.chores, by: \.cadence).mapValues(\.count)
        XCTAssertEqual(counts, [.daily: 11, .weekly: 12, .biweekly: 5, .monthly: 7, .bimonthly: 1, .quarterly: 3])
        XCTAssertEqual(list.chores.filter { $0.category == .catCare }.count, 5)

        XCTAssertEqual(list["mow-lawn"]?.season, Season(months: [4, 5, 6, 7, 8, 9, 10]))
        XCTAssertEqual(list.chores.filter(\.together).map(\.id), ["clean-out-fridge-pantry"])
        XCTAssertNil(list["take-out-garbages"], "split into three")
        XCTAssertNil(list["clean-out-fridge"], "replaced")
        // Grouped by cadence in Cadence.allCases order: the order is sortOrder on both stores.
        let ranks = list.chores.map { Cadence.allCases.firstIndex(of: $0.cadence)! }
        XCTAssertEqual(ranks, ranks.sorted())
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
}

