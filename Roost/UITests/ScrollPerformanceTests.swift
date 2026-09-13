// Does the Shopping list still scroll when there are 200 rows on it?
//
// Two measurements of the same flick, because they answer different questions. The signpost metric is the
// one worth reading: `scrollDecelerationMetric` collects the frame rate and the hitch time ratio of the
// deceleration after a swipe, which is what a dropped frame actually looks like to a thumb. The wall clock
// is the one worth gating on, because a `measure` block's numbers live in the result bundle and cannot be
// asserted on from inside the test — a plain elapsed-time bound can.
//
// The fixture is `shopping-large`: the four hand-written rows plus 200 more, every fifth one long enough
// to wrap, so the row heights are uneven the way a real list's are.
import XCTest

final class ScrollPerformanceTests: RoostUITestCase {
    /// How many full-screen flicks the wall-clock pass makes.
    private static let flicks = 8
    /// The bound for those flicks, end to end. A flick that lands and settles is comfortably inside
    /// 1.5 s even on a cold CI runner; 2.5 s each is the point at which something is wrong rather than slow.
    private static let flickBudget: TimeInterval = 2.5

    /// The list itself. A SwiftUI `List` is a collection view, so this is what carries the scroll.
    private func shoppingList(in app: XCUIApplication) -> XCUIElement {
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: Self.timeout), "the Shopping list never appeared")
        return list
    }

    private func openLongShoppingList() -> XCUIApplication {
        let app = launch(.shoppingLarge)
        waitForTasks(in: app)
        openTab("Shopping", in: app)
        XCTAssertTrue(
            app.staticTexts["Item 001"].waitForExistence(timeout: Self.timeout),
            "the 200-row fixture never appeared"
        )
        return app
    }

    /// The frame rate and hitch time ratio of the deceleration after one fast flick. Read the numbers in
    /// the result bundle (`xcrun xcresulttool get test-results tests`), or in Xcode's report.
    func testShoppingScrollDeceleration() {
        let app = openLongShoppingList()
        let list = shoppingList(in: app)

        let options = XCTMeasureOptions()
        // The swipe has to be the only thing inside the measured window; everything before it is setup.
        options.invocationOptions = [.manuallyStart]
        options.iterationCount = 3

        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            startMeasuring()
            list.swipeUp(velocity: .fast)
        }
    }

    /// The gate: eight flicks down the list, each inside its budget. This is what fails if the list ever
    /// stops being lazy, or a row's body grows something expensive.
    func testShoppingScrollStaysInBudget() {
        let app = openLongShoppingList()
        let list = shoppingList(in: app)

        // One flick first, untimed: the first one pays for the rows the launch has not drawn yet.
        list.swipeUp(velocity: .fast)

        let started = Date()
        for _ in 0 ..< Self.flicks {
            list.swipeUp(velocity: .fast)
        }
        let elapsed = Date().timeIntervalSince(started)
        let each = elapsed / Double(Self.flicks)

        // Printed either way, so a run that passes still says what it saw.
        print("scroll: \(Self.flicks) flicks in \(String(format: "%.2f", elapsed)) s "
            + "(\(String(format: "%.2f", each)) s each)")
        XCTAssertLessThan(
            each, Self.flickBudget,
            "a flick through the 200-row Shopping list took \(String(format: "%.2f", each)) s"
        )

        // And the list really did move: the row that was at the top is not any more.
        XCTAssertFalse(app.staticTexts["Item 001"].isHittable, "the list did not scroll")
    }
}
