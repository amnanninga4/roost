// The Home tab's two segments, and the cross-tab jumps that set them.
@testable import Roost
import XCTest

final class RootNavigationTests: XCTestCase {
    func testTheAppOpensOnHome() {
        let navigation = RootNavigation()
        XCTAssertEqual(navigation.selected, .home)
        XCTAssertEqual(navigation.segment, .home)
    }

    // The raw value is what AppStorage and any persisted selection wrote before the rename.
    // Changing it would silently reset every phone's tab on upgrade.
    func testTheHomeTabKeepsItsOldRawValue() {
        XCTAssertEqual(RootTab.home.rawValue, "tasks")
    }

    func testShowBoardSelectsTheTabAndTheSegment() {
        let navigation = RootNavigation()
        navigation.segment = .home
        navigation.showBoard()
        XCTAssertEqual(navigation.selected, .home)
        XCTAssertEqual(navigation.segment, .board)
    }

    func testShowAllChoresStillReachesTheMoreTab() {
        let navigation = RootNavigation()
        navigation.showAllChores()
        XCTAssertEqual(navigation.selected, .more)
        XCTAssertEqual(navigation.morePath, [.allChores])
    }
}
