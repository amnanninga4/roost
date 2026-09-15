@testable import Roost
import RoostCore
import XCTest

final class WindowCopyTests: XCTestCase {
    /// Sunday-first, the way Calendar.shortWeekdaySymbols is laid out.
    let symbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    func testWeekdayWindows() {
        let garbage = Chore(id: "g", title: "G", cadence: .weekly, category: .chore, weekdays: [5, 6])
        XCTAssertEqual(WindowCopy.line(garbage, shortWeekdaySymbols: symbols), "Fri–Sat")
        let can = Chore(id: "c", title: "C", cadence: .weekly, category: .chore, weekdays: [7])
        XCTAssertEqual(WindowCopy.line(can, shortWeekdaySymbols: symbols), "Sun")
        let span = Chore(id: "s", title: "S", cadence: .weekly, category: .chore, weekdays: [1, 3])
        XCTAssertEqual(WindowCopy.line(span, shortWeekdaySymbols: symbols), "Mon–Wed")
    }

    func testDueDayWindows() {
        XCTAssertEqual(
            WindowCopy.line(Chore(id: "l", title: "L", cadence: .monthly, category: .catCare, dueDay: 25)),
            "by the 25th"
        )
        XCTAssertEqual(
            WindowCopy.line(Chore(id: "u", title: "U", cadence: .monthly, category: .chore, dueDay: 1)),
            "by the 1st"
        )
        XCTAssertEqual(
            WindowCopy.line(Chore(id: "d", title: "D", cadence: .quarterly, category: .chore, dueDay: 22)),
            "by the 22nd"
        )
        XCTAssertEqual(
            WindowCopy.line(Chore(id: "t", title: "T", cadence: .bimonthly, category: .chore, dueDay: 3)),
            "by the 3rd"
        )
    }

    func testNoWindowNoLine() {
        XCTAssertNil(WindowCopy.line(Chore(id: "w", title: "W", cadence: .weekly, category: .chore)))
        XCTAssertNil(WindowCopy.line(
            Chore(id: "x", title: "X", cadence: .weekly, category: .chore, weekdays: [9]),
            shortWeekdaySymbols: symbols
        ))
    }
}
