// How a chore's season reads on the All chores screen. Pure, so the wording is tested without a screen.
import Foundation
import RoostCore

enum SeasonCopy {
    /// "April to October" for months 4...10; a single month is its name alone; nil when there is nothing
    /// sensible to say (an empty set, or a month outside 1...12). `monthSymbols` defaults to the reader's
    /// calendar so the names follow their locale; the tests pass English.
    static func line(_ season: Season, monthSymbols: [String] = Calendar.autoupdatingCurrent.monthSymbols) -> String? {
        guard let first = season.months.min(), let last = season.months.max(),
              (1 ... 12).contains(first), (1 ... 12).contains(last), monthSymbols.count == 12
        else { return nil }
        let from = monthSymbols[first - 1]
        let to = monthSymbols[last - 1]
        return first == last ? from : Strings.Chores.season(from: from, to: to)
    }
}
