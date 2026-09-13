import XCTest
@testable import Roost

final class RootTabsTests: XCTestCase {
    func testRootHasFourTabsInOrder() {
        XCTAssertEqual(RootTab.allCases.count, 4)
        XCTAssertEqual(RootTab.allCases, [.tasks, .shopping, .meals, .projects])
        XCTAssertEqual(RootTab.allCases.map(\.title), ["Tasks", "Shopping", "Meals", "Projects"])
        XCTAssertEqual(RootTab.allCases.map(\.symbol), ["checklist", "cart", "fork.knife", "hammer"])
    }

    func testListHeadersReadLikeTheMockup() {
        XCTAssertEqual(Strings.Shopping.header(items: 10, bought: 2), "10 items · 2 already bought")
        XCTAssertEqual(Strings.Shopping.header(items: 1, bought: 0), "1 item · 0 already bought")
        XCTAssertEqual(Strings.Meals.header(count: 8), "8 saved ideas")
        XCTAssertEqual(Strings.Meals.header(count: 1), "1 saved idea")
        XCTAssertEqual(Strings.Projects.header(count: 3), "3 active projects")
        XCTAssertEqual(Strings.Projects.header(count: 1), "1 active project")
        XCTAssertEqual(Strings.Projects.progress(done: 1, total: 5), "1/5")
    }
}
