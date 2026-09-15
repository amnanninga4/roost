@testable import Roost
import RoostCore
import XCTest

final class SeasonCopyTests: XCTestCase {
    private let english = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    func testSeasonReadsFirstMonthToLastMonth() {
        XCTAssertEqual(
            SeasonCopy.line(Season(months: [4, 5, 6, 7, 8, 9, 10]), monthSymbols: english),
            "April to October"
        )
        XCTAssertEqual(SeasonCopy.line(Season(months: [11, 12, 1]), monthSymbols: english), "January to December",
                       "a set has no wrap-around; the line is the span the months cover")
        XCTAssertEqual(SeasonCopy.line(Season(months: [6]), monthSymbols: english), "June")
        XCTAssertNil(SeasonCopy.line(Season(months: []), monthSymbols: english))
        XCTAssertNil(SeasonCopy.line(Season(months: [0, 13]), monthSymbols: english), "out of range is not drawn")
    }

    func testCadenceLabelsCoverEveryCase() {
        XCTAssertEqual(Cadence.allCases.map(\.label), [
            "Daily", "Weekly", "Biweekly", "Monthly", "Every two months", "Every three months",
        ])
    }
}
