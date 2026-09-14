// The Today tab's interactive chrome: the row menu and what is on it. The streak line and the swipe
// live here too as later tasks land them.
import XCTest

final class TodayBehaviourTests: RoostUITestCase {
    /// Long-press a row: the menu offers the handoff, the way into All chores, and the preview card.
    func testTheRowMenuHandsOffAndShowsInAllChores() {
        let app = launch(.paired)
        waitForTasks(in: app)
        let row = app.buttons["Feed the cat"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "the chore rows never appeared")
        row.press(forDuration: 1.2)
        let ask = app.buttons["Ask Wes to take this"]
        XCTAssertTrue(ask.waitForExistence(timeout: Self.timeout), "no Hand off in the menu")
        let showAll = app.buttons["Show in All chores"]
        XCTAssertTrue(showAll.waitForExistence(timeout: Self.timeout), "no Show in All chores")
        showAll.tap()
        XCTAssertTrue(
            app.staticTexts["HOUSEHOLD LIST"].waitForExistence(timeout: Self.timeout),
            "All chores never opened"
        )
    }

    /// The fixture's one unsynced offer (Step 1): Withdraw is on the menu, next to Show in All chores.
    func testTheRowMenuWithdrawsAnUnsyncedOffer() {
        let app = launch(.paired)
        waitForTasks(in: app)
        let row = app.buttons["Wipe down the kitchen counters and the bathroom mirror"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "the chore rows never appeared")
        row.press(forDuration: 1.2)
        XCTAssertTrue(
            app.buttons["Don't ask after all"].waitForExistence(timeout: Self.timeout),
            "no Withdraw in the menu"
        )
        XCTAssertTrue(
            app.buttons["Show in All chores"].waitForExistence(timeout: Self.timeout),
            "Show in All chores should be on every row's menu"
        )
    }

    /// A left swipe on an offerable row reveals Hand off in the assign colour; tapping it asks the
    /// same confirmation the menu does.
    func testTheTrailingSwipeOffersAHandoff() {
        let app = launch(.paired)
        waitForTasks(in: app)
        let row = app.buttons["Feed the cat"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "the chore rows never appeared")
        row.swipeLeft()
        let ask = app.buttons["Ask Wes to take this"]
        XCTAssertTrue(ask.waitForExistence(timeout: Self.timeout), "the swipe revealed no Hand off")
        ask.tap()
        XCTAssertTrue(
            app.buttons["Ask Wes"].waitForExistence(timeout: Self.timeout),
            "the handoff confirmation never appeared"
        )
        app.buttons["Cancel"].tap()
    }
}
