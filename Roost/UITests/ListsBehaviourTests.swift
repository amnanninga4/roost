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
        XCTAssertTrue(again.buttons["listsPicker.wishlist"].isSelected, "the Wishlist segment is the selected one")
        openList("Shopping", in: again) // leave the default for the next test
    }

    /// At the largest text sizes the segments show their symbols only; the word lives on as the
    /// segment's VoiceOver name, which is what the audits reach for.
    func testSegmentsAreSymbolsOnlyAtAccessibilitySizes() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-roostUITestState", "paired",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        waitForTasks(in: app)
        app.tabBars.buttons["Lists"].tap()
        let segment = app.buttons["listsPicker.meals"]
        XCTAssertTrue(segment.waitForExistence(timeout: Self.timeout), "the symbol segment never appeared")
        XCTAssertEqual(segment.label, "Meals", "the word lives on as the segment's VoiceOver name")
        // Leave the remembered page on Shopping for the next test.
        app.buttons["listsPicker.shopping"].tap()
        app.terminate()
    }

    /// Long-press a Shopping row: Edit opens the little sheet, Save writes through the store, and the
    /// renamed row carries no "Didn't sync" marker — the edit is queued, not refused.
    func testAShoppingRowEditsThroughItsMenu() {
        let app = launch(.paired)
        waitForTasks(in: app)
        openList("Shopping", in: app)
        let row = app.buttons["Cat litter"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "the shopping rows never appeared")
        row.press(forDuration: 1.2)
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: Self.timeout), "no Edit in the row's menu")
        edit.tap()
        let field = app.textFields["Add an item…"]
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout), "the edit sheet never opened")
        // The sheet focuses the field on appear, with the insertion point at the end of the existing
        // title, so typing goes straight in — tapping the field first would move the cursor mid-word.
        app.typeText(" (clumping)")
        app.buttons["Save"].tap()
        let renamed = app.buttons["Cat litter (clumping)"]
        XCTAssertTrue(renamed.waitForExistence(timeout: Self.timeout), "the renamed row never appeared")
        // The fixture seeds "Dish soap" as rejected, so a "Didn't sync" marker is always somewhere on the
        // page; the claim is about this row, whose VoiceOver value would carry the words if it were refused.
        XCTAssertFalse(
            (renamed.value as? String ?? "").contains("Didn't sync"),
            "an edit queues a PATCH; it is not a refusal"
        )
    }
}
