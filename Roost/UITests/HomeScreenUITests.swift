// Arrival, and the one tap from the front door to the board.
//
// The launch goes through `RoostUITestCase.launch(_:)` like every other suite here, so these tests
// get the same no-server fixture the rest of the app's UI tests stand on.
import XCTest

final class HomeScreenUITests: RoostUITestCase {
    func testTheAppOpensOnHomeNotTheBoard() {
        let app = launch(.paired)
        XCTAssertTrue(
            app.staticTexts["dateEyebrow"].waitForExistence(timeout: Self.timeout),
            "the app never reached Home"
        )
        XCTAssertFalse(app.staticTexts["board.title"].exists, "the board was already showing on launch")
    }

    func testTheSegmentReachesTheBoard() {
        let app = launch(.paired)
        XCTAssertTrue(
            app.staticTexts["dateEyebrow"].waitForExistence(timeout: Self.timeout),
            "the app never reached Home"
        )
        app.buttons["listsPicker.board"].tap()
        // The board's own title is the proof we switched. Not the date eyebrow: Home draws that line
        // under the same identifier, so it is on screen either way and would assert nothing.
        XCTAssertTrue(
            app.staticTexts["board.title"].waitForExistence(timeout: Self.timeout),
            "the board never appeared"
        )
    }

    /// The doors are drawn whether or not their rooms hold anything. The `paired` fixture fills all
    /// four, so what this covers is that every door reaches the screen; the empty-room case is
    /// `HomeSummaryTests.testEmptyRoomsShowNoCount`, where it can be asserted rather than looked at.
    func testEveryDoorIsOnTheStrip() {
        let app = launch(.paired)
        XCTAssertTrue(
            app.staticTexts["dateEyebrow"].waitForExistence(timeout: Self.timeout),
            "the app never reached Home"
        )
        for room in ["shopping", "meals", "projects", "wishlist"] {
            XCTAssertTrue(app.buttons["home.door.\(room)"].exists, "missing door: \(room)")
        }
    }

    /// Home's last section. The fixture's `SyncState` has no `baseURL`, so this phone is unpaired and the
    /// line is the notice wording — which is the point of building it: the screen the app opens on says so
    /// itself instead of leaving it to the board.
    func testHomeDrawsTheSyncNoticeLast() {
        let app = launch(.paired)
        XCTAssertTrue(
            app.staticTexts["dateEyebrow"].waitForExistence(timeout: Self.timeout),
            "the app never reached Home"
        )
        let notice = app.staticTexts["home.syncNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: Self.timeout), "Home draws no sync notice")
        XCTAssertEqual(notice.label, Self.unpairedLine)
        // Last: below the door strip, which is the section the spec puts above it.
        let lastDoor = app.buttons["home.door.wishlist"]
        XCTAssertTrue(lastDoor.exists, "the door strip was never built")
        XCTAssertGreaterThan(
            notice.frame.minY, lastDoor.frame.maxY,
            "the notice is not last: it sits at or above the door strip"
        )
    }

    /// The same line, from the same wiring, on the other segment — so neither screen can start saying
    /// something different about being offline.
    func testTheBoardSaysTheSameThingAboutSync() {
        let app = launch(.paired)
        XCTAssertTrue(
            app.staticTexts["home.syncNotice"].waitForExistence(timeout: Self.timeout),
            "Home draws no sync notice"
        )
        let onHome = app.staticTexts["home.syncNotice"].label
        waitForTasks(in: app)
        XCTAssertTrue(
            app.staticTexts[onHome].waitForExistence(timeout: Self.timeout),
            "the board says something else about sync; Home said '\(onHome)'"
        )
    }

    func testHomeShowsBothPeopleSideBySide() {
        let app = launch(.paired)
        XCTAssertTrue(app.staticTexts["dateEyebrow"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["YOU"].exists, "this phone's column missing")
        XCTAssertTrue(app.staticTexts["Wes"].exists, "the other person's column missing")
    }

    /// Spelled out rather than assembled, because it is what the reader sees. `Strings.Tasks.notPaired`.
    private static let unpairedLine = "Not paired yet · More → Settings"
}
