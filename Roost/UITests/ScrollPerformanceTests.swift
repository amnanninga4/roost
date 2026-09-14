// Does the Shopping list still scroll when there are 200 rows on it?
//
// Three measurements, because on a simulator they answer different halves of the question.
//
//   `testShoppingScrollDeceleration` is the numbers: `XCTOSSignpostMetric.scrollDecelerationMetric` times
//   the deceleration after one fast flick. It records rather than asserts, because a `measure` block's
//   values live in the result bundle and cannot be read from inside the test. On this simulator it is
//   2.43 s with a relative standard deviation of 0.06% — the flick is the same flick every time. Hitch
//   time ratio and frame rate are the metrics worth watching, and the simulator does not report them:
//   they need a real display, so they will appear the first time this runs on a device.
//
//   `testShoppingListStaysLazy` is the assertion that would actually catch the regression the numbers are
//   there to warn about. A `List` builds only the rows it is about to draw; a `ScrollView { VStack }`
//   builds all 204. Counting the cells in the accessibility tree tells the two apart with no timing in it
//   at all, which is why it is the gate.
//
//   `testShoppingScrollStaysInBudget` is a smoke alarm on wall-clock time, with a budget set well wide of
//   what was observed (2.9 s a flick) because most of that is XCUITest synthesising the gesture and
//   waiting for the app to go idle, not the app drawing. It catches an order of magnitude, not a percent.
//
// The fixture is `shopping-large`: the four hand-written rows plus 200 more, every fifth one long enough
// to wrap, so the row heights are uneven the way a real list's are.
import XCTest

final class ScrollPerformanceTests: RoostUITestCase {
    /// How many full-screen flicks the wall-clock pass makes.
    private static let flicks = 8
    /// Seconds per flick, end to end. Observed: 2.9 on this simulator, almost all of it harness overhead.
    private static let flickBudget: TimeInterval = 6
    /// The fixture's length: `UITestSeed.longListLength` plus the four hand-written rows.
    private static let rowCount = 204
    /// A phone shows about a dozen of these rows. Thirty is generous headroom for a taller screen and for
    /// the rows a collection view keeps just off each edge; 204 is what a non-lazy stack would report.
    private static let lazyCeiling = 30

    /// The list itself. A SwiftUI `List` is a collection view, so this is what carries the scroll.
    private func shoppingList(in app: XCUIApplication) -> XCUIElement {
        let list = app.collectionViews["shoppingList"]
        XCTAssertTrue(list.waitForExistence(timeout: Self.timeout), "the Shopping list never appeared")
        return list
    }

    private func openLongShoppingList() -> XCUIApplication {
        let app = launch(.shoppingLarge)
        waitForTasks(in: app)
        openList("Shopping", in: app)
        // The header's own count, which is the one thing on screen that proves all 204 rows are in the
        // store. One of them is in the Bought section, hence the 1.
        let header = "\(Self.rowCount) items · 1 already bought"
        XCTAssertTrue(
            app.staticTexts[header].waitForExistence(timeout: Self.timeout),
            "the \(Self.rowCount)-row fixture never appeared"
        )
        return app
    }

    /// The deceleration after one fast flick. Read the numbers in the result bundle
    /// (`xcrun xcresulttool get test-results tests`), or in Xcode's report.
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

    /// The gate: the list draws a screenful, not the whole fixture. This is what fails if the `List` is
    /// ever replaced by a `ScrollView` and a `VStack`, or if `ForEach` is handed a non-lazy container.
    func testShoppingListStaysLazy() {
        let app = openLongShoppingList()
        let cells = shoppingList(in: app).cells.count
        print("scroll: \(cells) of \(Self.rowCount) rows built")
        XCTAssertLessThan(
            cells, Self.lazyCeiling,
            "the Shopping list built \(cells) of \(Self.rowCount) rows — it is not lazy any more"
        )
        XCTAssertGreaterThan(cells, 1, "no rows were built at all")
    }

    /// Eight flicks down the list, each inside a budget set an order of magnitude, not a percent, above
    /// what was observed.
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
            "a flick through the \(Self.rowCount)-row Shopping list took \(String(format: "%.2f", each)) s"
        )

        // And the list really did move: the row that was at the top is not any more.
        XCTAssertFalse(app.staticTexts["Cat litter"].isHittable, "the list did not scroll")
    }
}
