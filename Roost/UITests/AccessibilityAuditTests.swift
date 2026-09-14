// One audit per screen: contrast, element descriptions, hit regions, traits, clipped text, Dynamic Type.
//
// `performAccessibilityAudit()` walks what is actually on screen and reports what it finds as test
// failures, so this suite fails the moment a screen grows a 30-pt tap target or a label nobody can read.
// Anything a screen is not being fixed for is listed at its call site with the reason, so the list below is
// also the list of what is still owed — see `RoostUITestCase.KnownIssue`.
//
// Two classes of finding recur, and both were checked against the rendered screen before being written off:
//
//   "Dynamic Type font sizes are partially unsupported" on a label set with a `RoostType` rung. Every rung
//   is `Font.custom(_:size:relativeTo:)`, which scales — `Packages/RoostDesign` has a test that walks all
//   twelve settings — but carries no `UIFontDescriptor` text style for the audit to read, so the audit
//   cannot tell. Launching the app at `UICTContentSizeCategoryAccessibilityXXXL` shows every one of these
//   labels at full size and none of them clipped.
//
//   "Text clipped" on a `TextField`. A single-line text field is a single-line text field: iOS scrolls its
//   contents rather than wrapping them, and the alternative — `axis: .vertical` — turns Return into a
//   newline and breaks the composer's whole reason for existing (Return adds the line and keeps the
//   keyboard). Checked at the largest accessibility size: the placeholder and the typed line are legible.
//
// Contrast is printed rather than gated on for the whole suite; the reason is on `RoostUITestCase.audit`.
import XCTest

final class AccessibilityAuditTests: RoostUITestCase {
    // MARK: - the two classes written off across the app

    /// A `RoostType` rung the audit cannot see the Dynamic Type support in. Verified at
    /// `UICTContentSizeCategoryAccessibilityXXXL`.
    private func customFontScales(_ element: String) -> KnownIssue {
        KnownIssue(
            compact: "Dynamic Type font sizes are partially unsupported",
            element: element,
            reason: "a RoostType rung — Font.custom(relativeTo:) scales but reports no text style"
        )
    }

    /// A single-line `TextField` whose contents scroll rather than wrap.
    private func textFieldScrolls(_ element: String) -> KnownIssue {
        KnownIssue(
            compact: "Text clipped",
            element: element,
            reason: "a single-line TextField; axis: .vertical would make Return a newline"
        )
    }

    /// The date eyebrow, on the Tasks tab and on the counter. `Roost/docs/tasks-ax.png` is this line at the
    /// largest accessibility size, wrapped onto two lines and whole; the audit's guess about a tracked,
    /// uppercased mono label is simply wrong. Matched on the identifier rather than the label, because the
    /// label is today's date.
    private var dateLineWraps: KnownIssue {
        KnownIssue(
            compact: "Text clipped",
            element: "dateEyebrow",
            reason: "the date eyebrow wraps rather than clipping — see Roost/docs/tasks-ax.png"
        )
    }

    // MARK: - onboarding

    func testOnboardingWelcomeAudit() throws {
        let app = launch(.onboarding)
        XCTAssertTrue(
            app.buttons["Get started"].waitForExistence(timeout: Self.timeout),
            "the welcome screen never appeared"
        )
        try audit(app, allowing: [
            customFontScales("Anne"),
            customFontScales("Wes"),
        ])
    }

    func testOnboardingCodeEntryAudit() throws {
        let app = launch(.onboarding)
        let start = app.buttons["Get started"]
        XCTAssertTrue(start.waitForExistence(timeout: Self.timeout), "the welcome screen never appeared")
        start.tap()
        let field = app.buttons["Pairing code, six digits"]
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout), "the code screen never appeared")
        // Three of six, so the audit sees a filled box, an empty one, and the one next in line.
        app.typeText("048")
        try audit(app, allowing: [
            // The invisible `TextField` stretched across the six boxes, and the UIKit field editor behind
            // it. SwiftUI does not set `adjustsFontForContentSizeCategory` on the `UITextField` it makes,
            // and there is no modifier that does — but nothing here is ever drawn: the boxes are the
            // drawing, and `described` in CodeEntryField.swift is the one element VoiceOver sees.
            KnownIssue(
                compact: "Dynamic Type font sizes are unsupported",
                element: nil,
                reason: "the invisible field behind the boxes; its own text is never rendered"
            ),
        ])
    }

    // MARK: - the tabs

    func testTasksAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        try audit(app, allowing: [dateLineWraps])
    }

    func testShoppingAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        openList("Shopping", in: app)
        try audit(app, allowing: [
            customFontScales("BOUGHT"),
            customFontScales("Clear bought"),
            textFieldScrolls("Add an item…"),
        ])
    }

    func testMealsAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        openList("Meals", in: app)
        try audit(app, allowing: [textFieldScrolls("Add an idea…")])
    }

    func testProjectsAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        openList("Projects", in: app)
        // The finished card opens itself; open the other one too, so the audit sees a step row, the step
        // composer, and a bar that is not full.
        let second = app.buttons["Clear out the garage"]
        XCTAssertTrue(second.waitForExistence(timeout: Self.timeout), "the second project never appeared")
        second.tap()
        // A List only builds the rows it is about to draw, so the second card's steps are not in the
        // accessibility tree until they are on screen. One flick brings them up.
        app.collectionViews["projectsList"].swipeUp()
        XCTAssertTrue(
            app.buttons["Shelve what stays"].waitForExistence(timeout: Self.timeout),
            "the steps never appeared"
        )
        try audit(app, allowing: [
            customFontScales("Archive"),
            textFieldScrolls("Start a project…"),
        ])
    }


    func testWishlistAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        openList("Wishlist", in: app)
        XCTAssertTrue(app.buttons["Bigger TV"].waitForExistence(timeout: Self.timeout), "the wishlist rows never appeared")
        try audit(app, allowing: [
            customFontScales("$599"),
            textFieldScrolls("Add something you'd like…"),
        ])
    }

    // MARK: - behind the gear

    func testSettingsAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        openFromGearMenu("Settings", in: app)
        XCTAssertTrue(
            app.staticTexts["Paired as"].waitForExistence(timeout: Self.timeout),
            "Settings never appeared"
        )
        try audit(app, allowing: [
            customFontScales("SYNC"),
            customFontScales("Roost 0.1.0 (1)"),
            customFontScales("Roost forgets the token on this phone. You'll need a new code to pair again."),
            customFontScales("Settings"),
            // The navigation bar's own leading button. Bar items keep a fixed size on iOS whatever the
            // reader's text setting says, and there is no modifier that changes that.
            KnownIssue(
                compact: "Dynamic Type font sizes are partially unsupported",
                element: "Close",
                reason: "a navigation bar button; iOS does not scale bar items with Dynamic Type"
            ),
            textFieldScrolls("Address"),
        ])
    }

    func testAllChoresAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        openFromGearMenu("All chores", in: app)
        XCTAssertTrue(
            app.staticTexts["HOUSEHOLD LIST"].waitForExistence(timeout: Self.timeout),
            "All chores never appeared"
        )
        try audit(app)
    }

    func testKitchenModeAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        openFromGearMenu("Kitchen mode", in: app)
        XCTAssertTrue(
            app.staticTexts["DUE TODAY"].waitForExistence(timeout: Self.timeout),
            "Kitchen mode never appeared"
        )
        try audit(app, allowing: [dateLineWraps])
    }
}
