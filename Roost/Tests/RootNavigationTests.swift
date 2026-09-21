// Home routes and cross-tab jumps, without a simulator.
@testable import Roost
import XCTest

@MainActor
final class RootNavigationTests: XCTestCase {
    func testTheAppOpensAtTheHomeRoot() {
        let navigation = RootNavigation()
        XCTAssertEqual(navigation.selected, .home)
        XCTAssertTrue(navigation.homePath.isEmpty)
    }

    /// Preserve the value written by earlier installs.
    func testTheHomeTabKeepsItsOldRawValue() {
        XCTAssertEqual(RootTab.home.rawValue, "tasks")
    }

    func testShowBoardReplacesTheHomePathAndSelectsHome() {
        let navigation = RootNavigation()
        navigation.showPerson(.anne)
        navigation.selected = .more
        navigation.showBoard()
        XCTAssertEqual(navigation.selected, .home)
        XCTAssertEqual(navigation.homePath, [.board])
    }

    func testPeopleAndMatchupPushOntoHomeWithoutDuplicateDestinations() {
        let navigation = RootNavigation()
        navigation.selected = .lists
        navigation.showMatchup()
        navigation.showMatchup()
        XCTAssertEqual(navigation.selected, .home)
        XCTAssertEqual(navigation.homePath, [.matchup])

        navigation.showPerson(.anne)
        navigation.showPerson(.anne)
        XCTAssertEqual(navigation.homePath, [.matchup, .person(.anne)])

        navigation.showPerson(.wes)
        XCTAssertEqual(navigation.homePath, [.matchup, .person(.anne), .person(.wes)])
    }

    func testOpeningAPersonFromAnotherTabSelectsHome() {
        let navigation = RootNavigation()
        navigation.selected = .more
        navigation.showPerson(.wes)
        XCTAssertEqual(navigation.selected, .home)
        XCTAssertEqual(navigation.homePath, [.person(.wes)])
    }

    /// A tapped push must reach today's work even if a detail page was left open.
    func testShowHomeClearsThePathAndSelectsHome() {
        let navigation = RootNavigation()
        navigation.showMatchup()
        navigation.showPerson(.anne)
        navigation.selected = .lists
        navigation.showHome()
        XCTAssertEqual(navigation.selected, .home)
        XCTAssertTrue(navigation.homePath.isEmpty)
    }

    func testShowAllChoresStillReachesTheMoreTab() {
        let navigation = RootNavigation()
        navigation.showAllChores()
        XCTAssertEqual(navigation.selected, .more)
        XCTAssertEqual(navigation.morePath, [.allChores])
    }
}
