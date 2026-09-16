// The Home tab's two segments, and the cross-tab jumps that set them.
@testable import Roost
import XCTest

final class RootNavigationTests: XCTestCase {
    /// A fresh install. The defaults suite is a throwaway rather than the phone's, because the segment
    /// is remembered now: reading `.standard` here would make this test depend on whatever the last run
    /// of the app — or of the UI suite — happened to leave showing.
    func testTheAppOpensOnHome() throws {
        let suite = "roost-fresh-install-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let navigation = RootNavigation(defaults: defaults)
        XCTAssertEqual(navigation.selected, .home)
        XCTAssertEqual(navigation.segment, .home)
    }

    /// The raw value is what AppStorage and any persisted selection wrote before the rename.
    /// Changing it would silently reset every phone's tab on upgrade.
    func testTheHomeTabKeepsItsOldRawValue() {
        XCTAssertEqual(RootTab.home.rawValue, "tasks")
    }

    func testShowBoardSelectsTheTabAndTheSegment() throws {
        let suite = "roost-show-board-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let navigation = RootNavigation(defaults: defaults)
        navigation.segment = .home
        navigation.showBoard()
        XCTAssertEqual(navigation.selected, .home)
        XCTAssertEqual(navigation.segment, .board)
    }

    // MARK: - the remembered segment

    /// A key rename resets everybody's phone back to Home without saying so, which is why the string is
    /// asserted here rather than only spelled in one place.
    func testTheSegmentKeyIsPinned() {
        XCTAssertEqual(HomeSegment.storageKey, "roost.home.segment")
        XCTAssertEqual(HomeSegment.home.rawValue, "home")
        XCTAssertEqual(HomeSegment.board.rawValue, "board")
    }

    /// The whole point of Fix 3: what the reader left showing is what the next launch shows. Written
    /// against a throwaway suite, so running the suite does not move the segment on this Mac's simulator.
    func testTheSegmentSurvivesARelaunch() throws {
        let suite = "roost-segment-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = RootNavigation(defaults: defaults)
        XCTAssertEqual(first.segment, .home, "a fresh install opens on Home")

        first.showBoard()
        XCTAssertEqual(
            defaults.string(forKey: HomeSegment.storageKey), "board",
            "the raw value is what is stored, so an AppStorage read of the same key would agree"
        )

        // A second object is the relaunch: nothing is carried over in memory.
        XCTAssertEqual(RootNavigation(defaults: defaults).segment, .board)

        // And back, so the write is not one-way.
        first.segment = .home
        XCTAssertEqual(defaults.string(forKey: HomeSegment.storageKey), "home")
        XCTAssertEqual(RootNavigation(defaults: defaults).segment, .home)
    }

    /// A string this build does not know reads as Home rather than taking the tab with it.
    func testAJunkValueUnderTheKeyReadsAsHome() throws {
        let suite = "roost-segment-junk-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(HomeSegment.stored(nil), .home)
        XCTAssertEqual(HomeSegment.stored("scoreboard"), .home)

        defaults.set("scoreboard", forKey: HomeSegment.storageKey)
        XCTAssertEqual(RootNavigation(defaults: defaults).segment, .home)
    }

    /// A tapped push lands on Home, and that is deliberate — `RootTabView` sets both the tab and the
    /// segment on `push.openTasksRequests`. Remembering the segment must not quietly make that a
    /// no-op for someone who was last on the board.
    func testForcingHomeWorksFromABoardSegmentThatWasRemembered() throws {
        let suite = "roost-segment-push-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(HomeSegment.board.rawValue, forKey: HomeSegment.storageKey)
        let navigation = RootNavigation(defaults: defaults)
        XCTAssertEqual(navigation.segment, .board)

        navigation.selected = .lists
        // What the push handler does.
        navigation.selected = .home
        navigation.segment = .home
        XCTAssertEqual(navigation.selected, .home)
        XCTAssertEqual(navigation.segment, .home)
    }

    func testShowAllChoresStillReachesTheMoreTab() {
        let navigation = RootNavigation()
        navigation.showAllChores()
        XCTAssertEqual(navigation.selected, .more)
        XCTAssertEqual(navigation.morePath, [.allChores])
    }
}
