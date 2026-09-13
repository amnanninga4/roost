import XCTest
@testable import Roost

final class RootTabsTests: XCTestCase {
    func testRootHasFourTabsInOrder() {
        XCTAssertEqual(RootTab.allCases.count, 4)
        XCTAssertEqual(RootTab.allCases, [.tasks, .shopping, .meals, .projects])
        XCTAssertEqual(RootTab.allCases.map(\.title), ["Tasks", "Shopping", "Meals", "Projects"])
        XCTAssertEqual(RootTab.allCases.map(\.symbol), ["checklist", "cart", "fork.knife", "hammer"])
    }

    func testOnlyTasksHasARealScreen() {
        XCTAssertNil(RootTab.tasks.placeholderLine)
        for tab in RootTab.allCases where tab != .tasks {
            XCTAssertEqual(tab.placeholderLine, "Nothing here yet.", "\(tab)")
        }
    }
}
