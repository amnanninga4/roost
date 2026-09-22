// Arrival, shared household navigation, and Home shortcuts.
//
// The launch goes through `RoostUITestCase.launch(_:)` like every other suite here, so these tests
// get the same no-server fixture the rest of the app's UI tests stand on.
import XCTest

final class HomeScreenUITests: RoostUITestCase {
    func testCheckingOffFromHomeRemovesTheOpenRow() {
        let app = launch(.paired)
        let row = app.buttons["home.chore.uitest-litter"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(row.label.contains("Anne"), "the chore's responsible person is part of its accessible name")
        XCTAssertTrue(row.label.contains("Scoop the litter box"))
        scrollIntoView(row, in: app)
        row.tap()
        let removed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: row)
        wait(for: [removed], timeout: Self.timeout)
    }

    func testPersonHeadersHaveFullWidthAtLargestTextSize() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-roostUITestState", "paired",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        let anne = app.buttons["home.open.anne"]
        XCTAssertTrue(anne.waitForExistence(timeout: Self.timeout))
        XCTAssertGreaterThan(
            anne.frame.width, app.frame.width * 0.75,
            "large-text person headers need their own full-width section"
        )
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Home-largest-text"
        shot.lifetime = .keepAlways
        add(shot)
        let wes = app.buttons["home.open.wes"]
        scrollIntoView(wes, in: app)
        XCTAssertTrue(wes.isHittable, "Wes's summary remains reachable")
        XCTAssertGreaterThan(wes.frame.width, app.frame.width * 0.75)
    }

    func testTheAppOpensOnHomeNotTheBoard() {
        let app = launch(.paired)
        XCTAssertTrue(
            app.staticTexts["dateEyebrow"].waitForExistence(timeout: Self.timeout),
            "the app never reached Home"
        )
        XCTAssertFalse(app.staticTexts["board.title"].exists, "the board was already showing on launch")
    }

    func testMatchupAndPersonPagesReturnToHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-roostUITestState", "paired", "-appearance", "dark"]
        app.launch()
        let matchup = app.buttons["home.open.matchup"]
        XCTAssertTrue(matchup.waitForExistence(timeout: Self.timeout))
        attachScreenshot("Home-dark", of: app)
        scrollIntoView(matchup, in: app)
        matchup.tap()
        XCTAssertTrue(app.navigationBars["Matchup"].waitForExistence(timeout: Self.timeout))
        attachScreenshot("Matchup-dark", of: app)

        let matchupAnne = app.buttons["matchup.open.anne"]
        XCTAssertTrue(matchupAnne.waitForExistence(timeout: Self.timeout))
        matchupAnne.tap()
        XCTAssertTrue(app.navigationBars["Anne"].waitForExistence(timeout: Self.timeout))
        attachScreenshot("Anne-dark", of: app)
        app.navigationBars["Anne"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Matchup"].waitForExistence(timeout: Self.timeout))
        app.navigationBars["Matchup"].buttons.firstMatch.tap()

        let anne = app.buttons["home.open.anne"]
        XCTAssertTrue(anne.waitForExistence(timeout: Self.timeout))
        anne.tap()
        XCTAssertTrue(app.navigationBars["Anne"].waitForExistence(timeout: Self.timeout))
        let personMatchup = app.buttons["person.openMatchup"]
        XCTAssertTrue(personMatchup.waitForExistence(timeout: Self.timeout))
        scrollIntoView(personMatchup, in: app)
        personMatchup.tap()
        XCTAssertTrue(app.navigationBars["Matchup"].waitForExistence(timeout: Self.timeout))
        app.navigationBars["Matchup"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Anne"].waitForExistence(timeout: Self.timeout))
        app.navigationBars["Anne"].buttons.firstMatch.tap()
        XCTAssertTrue(matchup.waitForExistence(timeout: Self.timeout))

        openList("Shopping", in: app)
        attachScreenshot("Shopping-dark", of: app)
    }

    func testHomeInLightAppearance() {
        let app = XCUIApplication()
        app.launchArguments = ["-roostUITestState", "paired", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["home.open.anne"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.buttons["home.open.wes"].exists)
        XCTAssertTrue(app.buttons["home.open.matchup"].exists)
        attachScreenshot("Home-light", of: app)
    }

    private func attachScreenshot(_ name: String, of app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Home keeps the two everyday list shortcuts visible.
    func testShoppingAndMealsHaveHomeShortcuts() {
        let app = launch(.paired)
        XCTAssertTrue(
            app.staticTexts["dateEyebrow"].waitForExistence(timeout: Self.timeout),
            "the app never reached Home"
        )
        for room in ["shopping", "meals"] {
            XCTAssertTrue(app.buttons["home.door.\(room)"].exists, "missing door: \(room)")
        }
    }

    func testEmptyListsRemainReachableFromHomeAndLists() {
        let app = launch(.pairedEmptyRooms)
        XCTAssertTrue(app.staticTexts["dateEyebrow"].waitForExistence(timeout: Self.timeout))
        let rooms = [
            ("shopping", "Shopping", "Nothing on the list."),
            ("meals", "Meals", "No ideas saved yet."),
            ("projects", "Projects", "No projects yet."),
            ("wishlist", "Wishlist", "Nothing on the wishlist."),
        ]
        for (id, title, _) in rooms.prefix(2) {
            let door = app.buttons["home.door.\(id)"]
            XCTAssertTrue(door.exists, "missing empty-room door: \(title)")
            XCTAssertEqual(door.label, title, "an empty room must not announce a count")
        }
        for (id, title, emptyState) in rooms {
            if id == "shopping" || id == "meals" {
                let door = app.buttons["home.door.\(id)"]
                scrollIntoView(door, in: app)
                door.tap()
            } else {
                openList(title, in: app)
            }
            XCTAssertTrue(
                app.staticTexts[emptyState].waitForExistence(timeout: Self.timeout),
                "\(title)'s door did not reach its empty state"
            )
            app.tabBars.buttons["Home"].tap()
            XCTAssertTrue(app.staticTexts["dateEyebrow"].waitForExistence(timeout: Self.timeout))
        }
    }

    /// Home's last section. The fixture's `SyncState` has no `baseURL`, so this phone is unpaired and the
    /// line is the notice wording — which is the point of building it: the screen the app opens on says so
    /// itself instead of leaving it to the board.
    func testHomeDrawsTheSyncNoticeLast() {
        let app = launch(.paired)
        XCTAssertTrue(
            app.staticTexts["dateEyebrow"].waitForExistence(timeout: Self.timeout),
            "the app never reached Home"
        )
        let notice = app.staticTexts["home.syncNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: Self.timeout), "Home draws no sync notice")
        XCTAssertEqual(notice.label, Self.unpairedLine)
        // Last: below the door strip, which is the section the spec puts above it.
        let lastDoor = app.buttons["home.door.meals"]
        XCTAssertTrue(lastDoor.exists, "the door strip was never built")
        XCTAssertGreaterThan(
            notice.frame.minY, lastDoor.frame.maxY,
            "the notice is not last: it sits at or above the door strip"
        )
    }

    /// The same line, from the same wiring, on the chore board — so neither screen can start saying
    /// something different about being offline.
    func testTheBoardSaysTheSameThingAboutSync() {
        let app = launch(.paired)
        XCTAssertTrue(
            app.staticTexts["home.syncNotice"].waitForExistence(timeout: Self.timeout),
            "Home draws no sync notice"
        )
        let onHome = app.staticTexts["home.syncNotice"].label
        waitForTasks(in: app)
        XCTAssertTrue(
            app.staticTexts[onHome].waitForExistence(timeout: Self.timeout),
            "the board says something else about sync; Home said '\(onHome)'"
        )
    }

    func testHomeShowsBothPeople() {
        let app = launch(.paired)
        XCTAssertTrue(app.staticTexts["dateEyebrow"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.buttons["home.open.anne"].exists, "Anne's side missing")
        XCTAssertTrue(app.buttons["home.open.wes"].exists, "Wes's side missing")
    }

    func testOpeningAPersonPage() {
        let app = launch(.paired)
        XCTAssertTrue(app.buttons["home.open.wes"].waitForExistence(timeout: Self.timeout))
        app.buttons["home.open.wes"].tap()
        XCTAssertTrue(app.navigationBars["Wes"].waitForExistence(timeout: Self.timeout), "Wes's page did not open")
    }

    /// Spelled out rather than assembled, because it is what the reader sees. `Strings.Tasks.notPaired`.
    private static let unpairedLine = "Not paired yet · More → Settings"
}
