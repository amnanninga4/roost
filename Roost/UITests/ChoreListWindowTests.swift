import XCTest

final class ChoreListWindowTests: RoostUITestCase {
    func testAllChoresShowsTheWindowLine() {
        let app = launch(.pairedWindows)
        openFromMore("All chores", in: app)
        let row = app.staticTexts["Deep-clean the fridge"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["by the 28th"].exists, "the quarterly chore shows its due day")
    }
}
