import XCTest
@testable import RoostCore

/// Reads the real repo file so the package can never drift from data/chores.json unnoticed.
func repoChoresURL(file: String = #filePath) -> URL {
    // …/Packages/RoostCore/Tests/RoostCoreTests/ChoreListTests.swift → repo root is five levels up.
    var url = URL(fileURLWithPath: file)
    for _ in 0..<5 { url.deleteLastPathComponent() }
    return url.appendingPathComponent("data/chores.json")
}

final class ChoreListTests: XCTestCase {
    func testRealSeedHas31ChoresAndTwoPinned() throws {
        let list = try ChoreList.load(from: repoChoresURL())
        XCTAssertEqual(list.version, 1)
        XCTAssertEqual(list.chores.count, 31)
        XCTAssertEqual(Set(list.chores.map(\.id)).count, 31, "ids unique")

        let pinned = list.pinned.sorted { $0.id < $1.id }
        XCTAssertEqual(pinned.map(\.id), ["garbage-can-to-street-sunday", "laundry"])
        XCTAssertEqual(list["laundry"]?.fixedAssignee, .anne)
        XCTAssertEqual(list["garbage-can-to-street-sunday"]?.fixedAssignee, .wes)

        let counts = Dictionary(grouping: list.chores, by: \.cadence).mapValues(\.count)
        XCTAssertEqual(counts[.daily], 11)
        XCTAssertEqual(counts[.weekly], 9)
        XCTAssertEqual(counts[.biweekly], 5)
        XCTAssertEqual(counts[.monthly], 6)

        XCTAssertEqual(list.chores.filter { $0.category == .catCare }.count, 5)
    }
}
