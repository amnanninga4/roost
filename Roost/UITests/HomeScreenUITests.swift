// Arrival, and the one tap from the front door to the board.
//
// The launch goes through `RoostUITestCase.launch(_:)` like every other suite here, so these tests
// get the same no-server fixture the rest of the app's UI tests stand on.
import XCTest

final class HomeScreenUITests: RoostUITestCase {
    func testTheAppOpensOnHomeNotTheBoard() {
        let app = launch(.paired)
        XCTAssertTrue(
            app.staticTexts["home.sentence"].waitForExistence(timeout: Self.timeout),
            "the app never reached Home"
        )
        XCTAssertFalse(app.staticTexts["Today"].exists, "the board was already showing on launch")
    }

    func testTheSegmentReachesTheBoard() {
        let app = launch(.paired)
        XCTAssertTrue(
            app.staticTexts["home.sentence"].waitForExistence(timeout: Self.timeout),
            "the app never reached Home"
        )
        app.buttons["listsPicker.board"].tap()
        // The board's own title is the proof we switched. Not the date eyebrow: Home draws that line
        // under the same identifier, so it is on screen either way and would assert nothing.
        XCTAssertTrue(
            app.staticTexts["Today"].waitForExistence(timeout: Self.timeout),
            "the board never appeared"
        )
    }

    /// The doors are drawn whether or not their rooms hold anything. The `paired` fixture fills all
    /// four, so what this covers is that every door reaches the screen; the empty-room case is
    /// `HomeSummaryTests.testEmptyRoomsShowNoCount`, where it can be asserted rather than looked at.
    func testEveryDoorIsOnTheStrip() {
        let app = launch(.paired)
        XCTAssertTrue(
            app.staticTexts["home.sentence"].waitForExistence(timeout: Self.timeout),
            "the app never reached Home"
        )
        for room in ["shopping", "meals", "projects", "wishlist"] {
            XCTAssertTrue(app.buttons["home.door.\(room)"].exists, "missing door: \(room)")
        }
    }
}
