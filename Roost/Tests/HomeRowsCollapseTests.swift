// The collapse threshold, as arithmetic rather than as a view. Six is a spec ruling, not a taste
// call, so it gets a test that will fail loudly if someone "tidies" it.
@testable import Roost
import XCTest

final class HomeRowsCollapseTests: XCTestCase {
    func testSixOrFewerAreAllVisible() {
        XCTAssertEqual(HomeRowsCollapse.visible(6, expanded: false), 6)
        XCTAssertEqual(HomeRowsCollapse.hiddenCount(6), 0)
    }

    func testSevenCollapsesToSix() {
        XCTAssertEqual(HomeRowsCollapse.visible(7, expanded: false), 6)
        XCTAssertEqual(HomeRowsCollapse.hiddenCount(7), 1)
    }

    func testNineCollapsesToSixWithThreeMore() {
        XCTAssertEqual(HomeRowsCollapse.visible(9, expanded: false), 6)
        XCTAssertEqual(HomeRowsCollapse.hiddenCount(9), 3)
    }

    func testExpandedShowsEverything() {
        XCTAssertEqual(HomeRowsCollapse.visible(9, expanded: true), 9)
    }

    func testZeroRowsIsNotACollapse() {
        XCTAssertEqual(HomeRowsCollapse.visible(0, expanded: false), 0)
        XCTAssertEqual(HomeRowsCollapse.hiddenCount(0), 0)
    }
}
