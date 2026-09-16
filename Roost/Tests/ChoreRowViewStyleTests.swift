@testable import Roost
import RoostCore
import RoostDesign
import XCTest

final class ChoreRowViewStyleTests: XCTestCase {
    func testOverdueTitleIsNotDangerUntilAlert() {
        XCTAssertEqual(
            ChoreRowPresentation.titleRole(isDone: false, stage: .nudge, style: .standard),
            .textPrimary
        )
        XCTAssertEqual(
            ChoreRowPresentation.titleRole(isDone: false, stage: .alert, style: .standard),
            .danger
        )
    }

    func testQuietIsAlwaysSecondary() {
        XCTAssertEqual(
            ChoreRowPresentation.titleRole(isDone: false, stage: .alert, style: .quiet),
            .textSecondary
        )
    }

    func testHomeDropsTheEmergencySubtitle() {
        XCTAssertFalse(
            ChoreRowPresentation.showsSubtitle(
                "Scoop litter emergency", title: "Scoop litter", allowed: false
            )
        )
        XCTAssertFalse(
            ChoreRowPresentation.showsSubtitle(
                "Scoop litter emergency", title: "Scoop litter", allowed: true
            )
        )
        XCTAssertTrue(
            ChoreRowPresentation.showsSubtitle("Getting overdue.", title: "Vacuum", allowed: true)
        )
    }
}
