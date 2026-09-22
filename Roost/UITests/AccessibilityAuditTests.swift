// One audit per screen: contrast, element descriptions, hit regions, traits, clipped text, Dynamic Type.
//
// `performAccessibilityAudit()` walks what is actually on screen and reports what it finds as test
// failures, so this suite fails the moment a screen grows a 30-pt tap target or a label nobody can read.
// Anything a screen is not being fixed for is listed at its call site with the reason, so the list below is
// also the list of what is still owed — see `RoostUITestCase.KnownIssue`.
//
// Single-line TextFields scroll their contents rather than wrapping them. Exceptions for those
// fields stay explicit; the native fonts and redesigned Home have no blanket clipping exemptions.
// Contrast remains reported under the existing policy in RoostUITestCase.audit.
import XCTest

final class AccessibilityAuditTests: RoostUITestCase {
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
        try audit(app)
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

    /// Home is the screen the app opens on, so the launch is the whole setup — there is nothing to
    /// navigate to.
    func testHomeAudit() throws {
        let app = launch(.paired)
        XCTAssertTrue(
            app.staticTexts["dateEyebrow"].waitForExistence(timeout: Self.timeout),
            "the app never reached Home"
        )
        try audit(app, allowing: [dateLineWraps])
    }

    /// The bottom of Home — the door strip and the row fold — which starts below the fold on a 17 Pro.
    ///
    /// This audit was owed: an earlier version of it was believed to fail because 32 pt of bottom
    /// padding did not clear the floating tab bar. It does clear it. The bar contributes its whole
    /// 83-pt band to the bottom safe area, the `ScrollView` insets its content by that, and the 32 pt
    /// is breathing room on top — at rest the door strip ends 38 pt above the bar. Content passing
    /// under the glass *during* a flick is iOS 26 drawing content under the bar on purpose, and no
    /// amount of bottom padding changes it. The scroll is settled before the audit runs.
    /// On hosted Xcode 26.6, `performAccessibilityAudit` then shifts that content by 31 pt
    /// and reports three unattributed text hits. The waiver is that shift.
    func testHomeScrolledToTheDoorsAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-roostUITestState", "paired", "-appearance", "dark"]
        app.launch()
        XCTAssertTrue(
            app.staticTexts["dateEyebrow"].waitForExistence(timeout: Self.timeout),
            "the app never reached Home"
        )
        let lastDoor = app.buttons["home.door.meals"]
        XCTAssertTrue(lastDoor.waitForExistence(timeout: Self.timeout), "the door strip was never built")
        // Flicked to the end rather than until the doors are merely visible: the state worth auditing is
        // the one where the last row is as close to the bar as it ever gets.
        for _ in 0 ..< 6 {
            app.swipeUp()
        }
        let bar = app.tabBars.firstMatch.frame
        XCTAssertFalse(
            lastDoor.frame.intersects(bar),
            "the last door rests under the floating tab bar: door \(lastDoor.frame), bar \(bar)"
        )
        // Runs 35652405767, 35659816474, and 35663998109 each report exactly three hits
        // with element none. Diag screenshots screen-02 and screen-03 are the settled frame
        // and the frame after the audit moves it. Main ac778db run 35643850498 passed.
        try audit(app, allowing: [
            dateLineWraps,
            KnownIssue(
                compact: "Potentially inaccessible text",
                element: nil,
                reason: "performAccessibilityAudit shifts the settled scroll by 31pt and reports element none"
            ),
        ])
    }

    func testMatchupAudit() throws {
        let app = launch(.paired)
        let matchup = app.buttons["home.open.matchup"]
        XCTAssertTrue(matchup.waitForExistence(timeout: Self.timeout))
        scrollIntoView(matchup, in: app)
        matchup.tap()
        XCTAssertTrue(app.navigationBars["Matchup"].waitForExistence(timeout: Self.timeout))
        try audit(app)
    }

    func testTasksAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        try audit(app, allowing: [dateLineWraps])
    }

    func testShoppingAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        openList("Shopping", in: app)
        // Audit the Bought controls fully above the floating tab bar, not partially occluded.
        scrollIntoView(app.buttons["Clear bought"], in: app)
        try audit(app, allowing: [
            // The rendered field grows and Return still submits at accessibility XXXL;
            // ListsBehaviourTests.testShoppingComposerScalesAndSubmitsAtLargestTextSize checks both.
            textFieldScrolls("Add an item…"),
            // Native supplementary header nodes are reported as partially unsupported even with
            // semantic fonts. The dedicated sizing test measures >1.5x growth, stacked controls,
            // and a working clear action; see docs/household-shopping-largest.png.
            KnownIssue(
                compact: "Dynamic Type font sizes are partially unsupported",
                element: "BOUGHT",
                reason: "native header audit false positive; actual largest-text growth is tested"
            ),
            KnownIssue(
                compact: "Dynamic Type font sizes are partially unsupported",
                element: "Clear bought",
                reason: "native header audit false positive; actual largest-text growth and action are tested"
            ),
        ])
    }

    func testMealsAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        openList("Meals", in: app)
        // iOS 26.5 reports the styled header fonts as partially unsupported. The sizing test
        // measures all three labels at >1.5x growth and opens Add at maximum text size.
        try audit(app, allowing: [
            KnownIssue(compact: "Dynamic Type font sizes are partially unsupported", element: "Meals",
                       reason: "actual growth is measured in testMealsHeaderScalesAndAddRemainsReachableAtLargestTextSize"),
            KnownIssue(compact: "Dynamic Type font sizes are partially unsupported", element: "4 saved ideas",
                       reason: "actual growth is measured in testMealsHeaderScalesAndAddRemainsReachableAtLargestTextSize"),
            KnownIssue(
                compact: "Dynamic Type font sizes are partially unsupported",
                element: "Not paired · More → Settings",
                reason: "actual growth is measured in testMealsHeaderScalesAndAddRemainsReachableAtLargestTextSize"
            ),
        ])
    }

    func testProjectsAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        openList("Projects", in: app)
        // The finished card opens itself; open the other one too, so the audit sees a step row, the step
        // composer, and a bar that is not full.
        // The pill picker is taller than the system control it replaced, so on a 17 Pro the second card
        // starts below the fold — and a List does not build a row it is not about to draw. Flick until
        // it exists.
        let list = app.collectionViews["projectsList"]
        let second = app.buttons["Clear out the garage"]
        var flicks = 0
        while !second.exists, flicks < 4 {
            list.swipeUp()
            flicks += 1
        }
        XCTAssertTrue(second.waitForExistence(timeout: Self.timeout), "the second project never appeared")
        second.tap()
        // A List only builds the rows it is about to draw, so the second card's steps are not in the
        // accessibility tree until they are on screen. One flick brings them up.
        app.collectionViews["projectsList"].swipeUp()
        XCTAssertTrue(
            app.buttons["Shelve what stays"].waitForExistence(timeout: Self.timeout),
            "the steps never appeared"
        )
        let ownedValue = app.buttons["Shelve what stays"].value as? String ?? ""
        XCTAssertTrue(ownedValue.contains("For Wes"), "the owner is spoken; got \(ownedValue)")
        try audit(app, allowing: [
            textFieldScrolls("Start a project…"),
            KnownIssue(
                compact: "Dynamic Type font sizes are partially unsupported",
                element: "Archive",
                reason: "actual label growth is measured in testMoreVersionAndProjectArchiveScaleAtLargestTextSize"
            ),
        ])
    }

    func testWishlistAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        openList("Wishlist", in: app)
        XCTAssertTrue(
            app.buttons["Bigger TV"].waitForExistence(timeout: Self.timeout),
            "the wishlist rows never appeared"
        )
        try audit(app, allowing: [
            textFieldScrolls("Add something you'd like…"),
        ])
    }

    // MARK: - the More tab

    func testMoreAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        openTab("More", in: app)
        XCTAssertTrue(app.buttons["All chores"].waitForExistence(timeout: Self.timeout), "the More page never appeared")
        try audit(app, allowing: [
            KnownIssue(
                compact: "Dynamic Type font sizes are partially unsupported",
                element: "more.version",
                reason: "actual footer growth is measured in testMoreVersionAndProjectArchiveScaleAtLargestTextSize"
            ),
        ])
    }

    func testSettingsAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        openFromMore("Settings", in: app)
        XCTAssertTrue(
            app.staticTexts["Paired as"].waitForExistence(timeout: Self.timeout),
            "Settings never appeared"
        )
        try audit(app, allowing: [
            // The navigation bar's back button. Bar items keep a fixed size on iOS whatever the reader's
            // text setting says, and there is no modifier that changes that.
            KnownIssue(
                compact: "Dynamic Type font sizes are partially unsupported",
                element: "More",
                reason: "a navigation bar button; iOS does not scale bar items with Dynamic Type"
            ),
            textFieldScrolls("Address"),
        ])
    }

    func testAllChoresAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        openFromMore("All chores", in: app)
        XCTAssertTrue(
            app.staticTexts["HOUSEHOLD LIST"].waitForExistence(timeout: Self.timeout),
            "All chores never appeared"
        )
        try audit(app)
    }

    func testKitchenAtLargestTextSize() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-roostUITestState", "paired", "-appearance", "dark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        openFromMore("Kitchen mode", in: app)
        XCTAssertTrue(app.staticTexts["VISIBLE TO BOTH OF YOU"].waitForExistence(timeout: Self.timeout))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Kitchen-largest-text"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testKitchenModeAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        openFromMore("Kitchen mode", in: app)
        XCTAssertTrue(
            app.staticTexts["DUE TODAY"].waitForExistence(timeout: Self.timeout),
            "Kitchen mode never appeared"
        )
        try audit(app, allowing: [
            dateLineWraps,
            KnownIssue(
                compact: "Text clipped",
                element: "VISIBLE TO BOTH OF YOU",
                reason: "wraps across three complete lines at maximum text size; see household-kitchen-largest.png"
            ),
        ])
    }
}
