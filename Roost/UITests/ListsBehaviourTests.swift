// Two promises the Lists container makes: a page keeps its state while another page is showing, and
// the page you left on is the page you come back to after a relaunch.
import XCTest

final class ListsBehaviourTests: RoostUITestCase {
    func testADraftSurvivesSwitchingPagesAndBack() {
        let app = launch(.paired)
        waitForTasks(in: app)
        openList("Shopping", in: app)
        let field = app.textFields["Add an item…"]
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout))
        field.tap()
        field.typeText("Paper towels")
        openList("Meals", in: app)
        openList("Shopping", in: app)
        XCTAssertEqual(app.textFields["Add an item…"].value as? String, "Paper towels", "the draft is still there")
    }

    func testTheChosenPageIsRememberedAcrossALaunch() {
        let app = launch(.paired)
        waitForTasks(in: app)
        openList("Wishlist", in: app)
        app.terminate()
        let again = launch(.paired)
        waitForTasks(in: again)
        again.tabBars.buttons["Lists"].tap()
        XCTAssertTrue(again.staticTexts["Nothing on the wishlist."].waitForExistence(timeout: Self.timeout)
            || again.staticTexts["Wishlist"].waitForExistence(timeout: Self.timeout), "Wishlist came back")
        XCTAssertTrue(again.segmentedControls["listsPicker"].buttons["Wishlist"].isSelected)
        openList("Shopping", in: again) // leave the default for the next test
    }
}
