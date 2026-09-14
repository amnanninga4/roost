@testable import Roost
import XCTest

final class RootTabsTests: XCTestCase {
    func testRootHasThreeTabsInOrder() {
        XCTAssertEqual(RootTab.allCases, [.tasks, .lists, .more])
        XCTAssertEqual(RootTab.allCases.map(\.title), ["Tasks", "Lists", "More"])
        XCTAssertEqual(RootTab.allCases.map(\.symbol), ["checklist", "list.bullet.rectangle", "ellipsis.circle"])
    }

    func testListsPagesInOrderWithTheirSymbolsAndAStableStorageKey() {
        XCTAssertEqual(ListPage.allCases, [.shopping, .meals, .projects, .wishlist])
        XCTAssertEqual(ListPage.allCases.map(\.title), ["Shopping", "Meals", "Projects", "Wishlist"])
        XCTAssertEqual(ListPage.allCases.map(\.symbol), ["cart", "fork.knife", "hammer", "gift"])
        XCTAssertEqual(ListPage.storageKey, "roost.lists.page")
        XCTAssertEqual(ListPage(rawValue: "wishlist"), .wishlist, "AppStorage writes the raw value; it must not change")
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
