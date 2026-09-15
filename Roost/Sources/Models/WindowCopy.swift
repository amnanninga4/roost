// How a chore's due window reads on the All chores screen. Pure, so the wording is tested without a screen.
import Foundation
import RoostCore

enum WindowCopy {
    /// "Fri–Sat" for weekdays [5, 6], "Sun" for [7], "by the 25th" for a due day; nil without a window or
    /// with a weekday outside 1...7. `shortWeekdaySymbols` is Sunday-first, as `Calendar` lays it out; the
    /// default follows the reader's locale and the tests pass English.
    static func line(
        _ chore: Chore,
        shortWeekdaySymbols: [String] = Calendar.autoupdatingCurrent.shortWeekdaySymbols
    ) -> String? {
        if let days = chore.weekdays, let first = days.min(), let last = days.max() {
            guard (1 ... 7).contains(first), (1 ... 7).contains(last),
                  shortWeekdaySymbols.count == 7 else { return nil }
            let from = shortWeekdaySymbols[first % 7] // ISO Monday = 1 → index 1; Sunday = 7 → index 0
            let to = shortWeekdaySymbols[last % 7]
            return first == last ? from : Strings.Chores.window(from: from, to: to)
        }
        if let dueDay = chore.dueDay {
            let formatter = NumberFormatter()
            formatter.numberStyle = .ordinal
            guard let ordinal = formatter.string(from: NSNumber(value: dueDay)) else { return nil }
            return Strings.Chores.windowBy(ordinal)
        }
        return nil
    }
}
