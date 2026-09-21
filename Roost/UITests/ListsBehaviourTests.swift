// Two promises the Lists container makes: a page keeps its state while another page is showing, and
// the page you left on is the page you come back to after a relaunch.
import XCTest

final class ListsBehaviourTests: RoostUITestCase {
    /// Check the rendered input, not just the design system's reference scale. XCTest sometimes
    /// reports custom-font UITextFields as partially unsupported even when SwiftUI scales them.
    func testShoppingComposerScalesAndSubmitsAtLargestTextSize() {
        let app = XCUIApplication()
        var normalHeight: CGFloat = 0
        for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"] {
            app.launchArguments = [
                "-roostUITestState", "paired",
                "-UIPreferredContentSizeCategoryName", category,
            ]
            app.launch()
            openList("Shopping", in: app)
            let field = app.textFields["Add an item…"]
            XCTAssertTrue(field.waitForExistence(timeout: Self.timeout))
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Shopping-\(category)"
            shot.lifetime = .keepAlways
            add(shot)
            if normalHeight == 0 {
                normalHeight = field.frame.height
                XCTAssertGreaterThan(normalHeight, 0)
            } else {
                XCTAssertGreaterThan(field.frame.height, normalHeight * 1.5, "the input must grow with Dynamic Type")
                field.tap()
                field.typeText("Paper towels")
                let typed = expectation(for: NSPredicate(format: "value == %@", "Paper towels"), evaluatedWith: field)
                wait(for: [typed], timeout: Self.timeout)
                field.typeText("\n")
                let cleared = NSPredicate(format: "value == %@ OR value == %@", "", "Add an item…")
                let emptyField = expectation(for: cleared, evaluatedWith: field)
                wait(for: [emptyField], timeout: Self.timeout)
                // Return keeps focus for another item. An empty Return dismisses the keyboard;
                // at accessibility XXXL the new row may be below it and not yet built by List.
                field.tap()
                field.typeText("\n")
                let row = app.buttons["Paper towels"]
                for _ in 0 ..< 4 where !row.exists {
                    app.collectionViews["shoppingList"].swipeUp()
                }
                XCTAssertTrue(
                    row.waitForExistence(timeout: Self.timeout),
                    "Return must still add the item"
                )
            }
            app.terminate()
        }
    }

    func testBoughtHeaderAndClearActionScaleAtLargestTextSize() {
        let app = XCUIApplication()
        var normalHeadingHeight: CGFloat = 0
        var normalActionWidth: CGFloat = 0
        for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"] {
            app.launchArguments = [
                "-roostUITestState", "paired",
                "-UIPreferredContentSizeCategoryName", category,
            ]
            app.launch()
            openList("Shopping", in: app)
            let clear = app.buttons["Clear bought"]
            scrollIntoView(clear, in: app)
            let heading = app.staticTexts["BOUGHT"]
            XCTAssertTrue(heading.waitForExistence(timeout: Self.timeout))
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Shopping-bought-\(category)"
            shot.lifetime = .keepAlways
            add(shot)
            if normalHeadingHeight == 0 {
                normalHeadingHeight = heading.frame.height
                normalActionWidth = clear.frame.width
                XCTAssertGreaterThan(normalHeadingHeight, 0)
                XCTAssertGreaterThan(normalActionWidth, 0)
            } else {
                XCTAssertGreaterThan(heading.frame.height, normalHeadingHeight * 1.5)
                XCTAssertGreaterThan(clear.frame.width, normalActionWidth * 1.5)
                XCTAssertLessThanOrEqual(heading.frame.maxY, clear.frame.minY,
                                         "the action gets its own line at accessibility sizes")
                clear.tap()
                let removed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: clear)
                wait(for: [removed], timeout: Self.timeout)
                let unbought = app.buttons["Cat litter"]
                for _ in 0 ..< 4 where !unbought.exists {
                    app.collectionViews["shoppingList"].swipeDown()
                }
                XCTAssertTrue(unbought.exists, "clearing bought items preserves the running list")
            }
            app.terminate()
        }
    }

    func testMoreVersionAndProjectArchiveScaleAtLargestTextSize() {
        let app = XCUIApplication()
        var normalVersionHeight: CGFloat = 0
        var normalArchiveHeight: CGFloat = 0
        for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"] {
            app.launchArguments = [
                "-roostUITestState", "paired",
                "-UIPreferredContentSizeCategoryName", category,
            ]
            app.launch()
            openTab("More", in: app)
            let version = app.staticTexts["more.version"]
            scrollIntoView(version, in: app)
            XCTAssertTrue(version.waitForExistence(timeout: Self.timeout))
            let versionHeight = version.frame.height
            let moreShot = XCTAttachment(screenshot: app.screenshot())
            moreShot.name = "More-version-\(category)"
            moreShot.lifetime = .keepAlways
            add(moreShot)

            openList("Projects", in: app)
            let archive = app.staticTexts["Archive"].firstMatch
            scrollIntoView(archive, in: app)
            XCTAssertTrue(archive.waitForExistence(timeout: Self.timeout))
            let archiveHeight = archive.frame.height
            let projectShot = XCTAttachment(screenshot: app.screenshot())
            projectShot.name = "Projects-archive-\(category)"
            projectShot.lifetime = .keepAlways
            add(projectShot)
            if normalVersionHeight == 0 {
                normalVersionHeight = versionHeight
                normalArchiveHeight = archiveHeight
                XCTAssertGreaterThan(normalVersionHeight, 0)
                XCTAssertGreaterThan(normalArchiveHeight, 0)
            } else {
                XCTAssertGreaterThan(versionHeight, normalVersionHeight * 1.5,
                                     "the app version must scale with Dynamic Type")
                XCTAssertGreaterThan(archiveHeight, normalArchiveHeight * 1.5,
                                     "the Archive label must scale with Dynamic Type")
            }
            app.terminate()
        }
    }

    func testMealsHeaderScalesAndAddRemainsReachableAtLargestTextSize() {
        let app = XCUIApplication()
        var normalHeights: [CGFloat] = []
        for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"] {
            app.launchArguments = [
                "-roostUITestState", "paired", "-appearance", "dark",
                "-UIPreferredContentSizeCategoryName", category,
            ]
            app.launch()
            waitForTasks(in: app)
            openList("Meals", in: app)
            let list = app.collectionViews["mealsList"]
            let labels = [
                list.staticTexts["Meals"],
                list.staticTexts["4 saved ideas"],
                list.staticTexts["Not paired · More → Settings"],
            ]
            for label in labels {
                XCTAssertTrue(label.waitForExistence(timeout: Self.timeout))
            }
            let heights = labels.map(\.frame.height)
            if normalHeights.isEmpty {
                normalHeights = heights
            } else {
                for (normal, large) in zip(normalHeights, heights) {
                    XCTAssertGreaterThan(large, normal * 1.5)
                }
            }
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Meals-header-\(category)"
            shot.lifetime = .keepAlways
            add(shot)
            let addMeal = app.buttons["meals.add"]
            XCTAssertTrue(addMeal.isHittable)
            addMeal.tap()
            XCTAssertTrue(app.textFields["meals.idea"].waitForExistence(timeout: Self.timeout))
            app.buttons["Cancel"].tap()
            if category == "UICTContentSizeCategoryAccessibilityXXXL" {
                let meal = list.descendants(matching: .any).matching(identifier: "Sheet pan chicken").firstMatch
                scrollIntoView(meal, in: app)
                let rowShot = XCTAttachment(screenshot: app.screenshot())
                rowShot.name = "Meals-largest-row"
                rowShot.lifetime = .keepAlways
                add(rowShot)
            }
            app.terminate()
        }
    }

    func testMealIdeaIsAddedFromASheet() {
        let app = launch(.paired)
        openList("Meals", in: app)
        XCTAssertFalse(app.textFields["Add an idea…"].exists)
        let page = XCTAttachment(screenshot: app.screenshot())
        page.name = "Meals-with-add-button"
        page.lifetime = .keepAlways
        add(page)
        app.buttons["meals.add"].tap()
        let field = app.textFields["meals.idea"]
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        field.tap()
        field.typeText("Sheet-pan tofu")
        let tag = app.textFields["Tag, like Weeknight"]
        tag.tap()
        tag.typeText("Weeknight")
        let sheet = XCTAttachment(screenshot: app.screenshot())
        sheet.name = "Meal-idea-sheet"
        sheet.lifetime = .keepAlways
        add(sheet)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["meals.add"].waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(field.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Sheet-pan tofu").firstMatch.exists)
        app.buttons["meals.add"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        field.tap()
        field.typeText("Discard this meal")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "Discard this meal").firstMatch.exists)
    }

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
        // A long-press on a List row inside the paged TabView is the one gesture the CI runner drops
        // under load (the menu never opens; #77's run), so press again, bounded, before calling it a failure.
        let edit = app.buttons["Edit"]
        var presses = 0
        repeat {
            row.press(forDuration: 1.2)
            presses += 1
        } while !edit.waitForExistence(timeout: 3) && presses < 3
        XCTAssertTrue(edit.exists, "no Edit in the row's menu after \(presses) presses")
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
