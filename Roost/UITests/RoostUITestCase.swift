// The ground every UI test stands on: a launch that needs no server, and the taps that reach each screen.
//
// `-roostUITestState <name>` is the app's own DEBUG launch argument (Sources/Debug/UITestSeed.swift): an
// in-memory store with a fixed set of records, a fake identity in place of the Keychain's token, and no
// base URL, so a sync pass returns `.unpaired` before it builds a request. No stub server, no waiting on
// the network, and the same rows on screen on any day.
import XCTest

/// The fixture names the app understands. Spelled here too, because a UI test cannot import the app.
enum UITestState: String {
    case onboarding
    case paired
    case shoppingLarge = "shopping-large"
}

class RoostUITestCase: XCTestCase {
    /// How long a screen gets to appear. Generous, because a cold launch on a CI runner is not a fast one.
    static let timeout: TimeInterval = 30

    override func setUp() {
        super.setUp()
        // On, on purpose: one `performAccessibilityAudit()` reports every issue it found as its own
        // failure, and stopping at the first one would hide the rest of a screen's list.
        continueAfterFailure = true
    }

    /// Launches the app into `state` and returns it, already on screen.
    @discardableResult
    func launch(_ state: UITestState) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-roostUITestState", state.rawValue]
        app.launch()
        return app
    }

    // MARK: - getting to a screen

    /// Taps a tab in the tab bar and waits for the tab's own title to be on screen.
    func openTab(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: Self.timeout), "the \(title) tab never appeared")
        tab.tap()
        XCTAssertTrue(
            app.staticTexts[title].waitForExistence(timeout: Self.timeout),
            "the \(title) screen never appeared"
        )
    }

    /// Opens the Tasks tab's gear menu and taps one of its items.
    func openFromGearMenu(_ item: String, in app: XCUIApplication) {
        let gear = app.buttons["More"]
        XCTAssertTrue(gear.waitForExistence(timeout: Self.timeout), "the gear menu never appeared")
        gear.tap()
        let entry = app.buttons[item]
        XCTAssertTrue(entry.waitForExistence(timeout: Self.timeout), "'\(item)' is not in the gear menu")
        entry.tap()
    }

    /// Waits for the Tasks tab to have drawn its board, which is the app's slowest first screen.
    func waitForTasks(in app: XCUIApplication) {
        XCTAssertTrue(
            app.staticTexts["Today"].waitForExistence(timeout: Self.timeout),
            "the Tasks tab never appeared"
        )
    }

    // MARK: - the audit

    /// Runs every audit type over whatever is on screen.
    ///
    /// `performAccessibilityAudit` reports what it finds as test failures rather than throwing, so a known
    /// issue is silenced with `XCTExpectFailure` at the call site and stays visible in the log. The handler
    /// returns false every time — it does not suppress anything — and exists so the log says which element
    /// and which numbers, which the one-line failure message does not.
    func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit { issue in
            print("""
            AUDIT \(self.name) | \(issue.auditType) | \(issue.compactDescription)
                  \(issue.detailedDescription)
                  element: \(issue.element?.description ?? "none")
            """)
            return false
        }
    }
}
