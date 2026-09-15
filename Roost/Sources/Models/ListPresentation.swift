// The list screens' arithmetic, kept out of the views so it can be tested without a simulator:
//
//   ShoppingSplit   still-to-buy rows first, bought rows after, and the header's two numbers
//   PriceParser     what a typed price becomes, as whole cents
//   PriceFormat     how a price reads on a row and in the header
//   WishlistTotals  open count and the priced open items' sum
//   ProjectProgress done / total / fraction, and the one condition that makes a card finished
//   SubtaskOrder    the sortOrder values a drag implies, changing as few other rows as possible
//   MealDates       "last made today" / "yesterday" / "Tuesday" / "Jul 20"
//   ProjectDates    a project's due day as "Due Sep 20", and whether it has passed
//
// None of it touches SwiftData or SwiftUI; the screens hand in what they already have from `@Query`.
import Foundation
import RoostCore

/// Shopping rows in the order the screen draws them, in two groups.
struct ShoppingSplit<Row> {
    /// Still to buy, newest first (the order the rows come in).
    let toBuy: [Row]
    /// Bought, most recently bought first, so the last tick is the top of the section.
    let bought: [Row]

    var boughtCount: Int {
        bought.count
    }

    var total: Int {
        toBuy.count + bought.count
    }

    /// `rows` arrives newest first (the screen's `@Query` sort).
    init(rows: [Row], isBought: (Row) -> Bool, boughtAt: (Row) -> Date?) {
        toBuy = rows.filter { !isBought($0) }
        let ticked = rows.filter(isBought)
        bought = ticked.sorted { (boughtAt($0) ?? .distantPast) > (boughtAt($1) ?? .distantPast) }
    }
}

/// The wishlist's price field: what a person types, as whole cents.
///
/// "599" is $599, "12.5" is $12.50, "$1,299.99" is $1,299.99. A third decimal, a second point, letters,
/// a sign, a space inside the number, or nothing at all is nil, and so is anything past the server's
/// ceiling. Whole dollars first, because that is how a price is said out loud; the cents are there for
/// the people who type them.
enum PriceParser {
    static func cents(from text: String) -> Int? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.removeAll { $0 == "$" || $0 == "," }
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else { return nil }
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let whole = parts[0]
        let fraction = parts.count == 2 ? parts[1] : ""
        guard !(whole.isEmpty && fraction.isEmpty), fraction.count <= 2 else { return nil }
        guard let dollars = whole.isEmpty ? 0 : Int(whole), dollars <= ListActions.priceLimit / 100 else { return nil }
        let cents = fraction
            .isEmpty ? 0 : (Int(String(fraction).padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0)
        let total = dollars * 100 + cents
        return total <= ListActions.priceLimit ? total : nil
    }
}

/// How a price reads on a row and in the header: whole dollars when the cents are zero ("$599"),
/// dollars and cents otherwise ("$12.50"), grouped by thousands ("$1,850").
enum PriceFormat {
    static func dollars(cents: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let places = cents % 100 == 0 ? 0 : 2
        return (Decimal(cents) / 100)
            .formatted(.currency(code: "USD").precision(.fractionLength(places)).locale(locale))
    }
}

/// The wishlist header's two numbers: how many open items, and what the priced ones add up to.
struct WishlistTotals: Equatable {
    let openCount: Int
    /// Nil when no open item has a price, so the header leaves the total out rather than saying "$0".
    let totalCents: Int?

    init<Row>(rows: [Row], isBought: (Row) -> Bool, priceCents: (Row) -> Int?) {
        let open = rows.filter { !isBought($0) }
        openCount = open.count
        let priced = open.compactMap(priceCents)
        totalCents = priced.isEmpty ? nil : priced.reduce(0, +)
    }
}

/// A project card's progress. `isFinished` is the condition that earns the Done chip: every step
/// done, and at least one step — a project nobody has broken down yet is not finished, it is empty.
struct ProjectProgress: Equatable {
    let done: Int
    let total: Int

    init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }

    init<Row>(steps: [Row], isDone: (Row) -> Bool) {
        total = steps.count
        done = steps.count(where: isDone)
    }

    var fraction: Double {
        total == 0 ? 0 : Double(done) / Double(total)
    }

    var isFinished: Bool {
        total > 0 && done == total
    }
}

/// What a drag does to `sortOrder`.
///
/// The server takes any non-negative integer up to a million (`server/src/app.js`), and a PATCH
/// carries one row, so a move that can be expressed as one new number sends one request and leaves
/// every other row's value — and the other phone's pending edits to them — alone. That works
/// whenever the destination has a gap: the moved row takes the midpoint between its new neighbours.
/// When the neighbours are adjacent integers there is no midpoint to take, so the whole list is
/// renumbered on a stride, which opens gaps for the next few drags. Only the rows whose number
/// actually changed come back.
enum SubtaskOrder {
    /// The gap left between steps when the list has to be renumbered.
    static let stride = 16
    /// The server's ceiling for `sortOrder`.
    static let maximum = 1_000_000

    struct Change: Equatable {
        let id: String
        let sortOrder: Int
    }

    /// `rows` is the project's live steps in the order they are drawn. Returns the rows to PATCH.
    static func plan(rows: [(id: String, sortOrder: Int)], move source: IndexSet, to destination: Int) -> [Change] {
        var moved = rows
        moved.move(fromOffsets: source, toOffset: destination)
        guard moved.map(\.id) != rows.map(\.id) else { return [] }

        if source.count == 1, let one = single(in: moved, source: source, destination: destination) {
            return [one]
        }
        return renumber(moved)
    }

    /// The one-row answer: the moved step slots into a gap between its new neighbours.
    private static func single(
        in moved: [(id: String, sortOrder: Int)], source: IndexSet, destination: Int
    ) -> Change? {
        let from = source.first ?? 0
        let index = from < destination ? destination - 1 : destination
        guard moved.indices.contains(index) else { return nil }
        let row = moved[index]
        let before = index > 0 ? moved[index - 1].sortOrder : nil
        let after = index < moved.count - 1 ? moved[index + 1].sortOrder : nil

        switch (before, after) {
        case let (nil, .some(next)):
            guard next >= 2 else { return nil }
            return Change(id: row.id, sortOrder: next / 2)
        case let (.some(previous), nil):
            guard previous + stride <= maximum else { return nil }
            return Change(id: row.id, sortOrder: previous + stride)
        case let (.some(previous), .some(next)):
            guard next - previous >= 2 else { return nil }
            return Change(id: row.id, sortOrder: previous + (next - previous) / 2)
        case (nil, nil):
            return nil
        }
    }

    /// Every step on the stride, from zero. Rows already on their number are left out of the result.
    private static func renumber(_ moved: [(id: String, sortOrder: Int)]) -> [Change] {
        let step = max(1, min(stride, moved.isEmpty ? stride : maximum / max(1, moved.count)))
        var changes: [Change] = []
        for (index, row) in moved.enumerated() {
            let wanted = index * step
            if wanted != row.sortOrder {
                changes.append(Change(id: row.id, sortOrder: wanted))
            }
        }
        return changes
    }
}

/// How a meal's "last made" date reads. Recent days get a word or a weekday, because "last made
/// Tuesday" is what a person says; anything older than a week gets the date.
enum MealDates {
    /// The date part of `Strings.Meals.lastMade`. `calendar` is injectable so the tests can pin a zone.
    static func lastMade(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return Strings.Meals.today
        case 1: return Strings.Meals.yesterday
        case 2 ... 6: return date.formatted(.dateTime.weekday(.wide).locale(.autoupdatingCurrent))
        default: return date.formatted(.dateTime.month(.abbreviated).day().locale(.autoupdatingCurrent))
        }
    }
}

/// A project's due day: the `YYYY-MM-DD` the server stores, read and written through the household
/// calendar so the phone's own time zone never moves the day.
enum ProjectDates {
    /// "2026-09-20" for the Chicago day containing `date`.
    static func dayString(_ date: Date, calendar: HouseholdCalendar = HouseholdCalendar()) -> String {
        NotificationPlanner.dayKey(date, calendar: calendar)
    }

    /// The start of that day in Chicago, or nil for anything that is not a day.
    static func day(from text: String, calendar: HouseholdCalendar = HouseholdCalendar()) -> Date? {
        SyncAPI.parseActiveFrom(text, calendar: calendar)
    }

    /// "Due Sep 20", or "Due Jan 5, 2027" when the day is in another year. Nil for a day that does not parse.
    static func label(
        _ text: String, now: Date = Date(), locale: Locale = .autoupdatingCurrent,
        calendar: HouseholdCalendar = HouseholdCalendar()
    ) -> String? {
        guard let day = day(from: text, calendar: calendar) else { return nil }
        let sameYear = calendar.calendar.component(.year, from: day) == calendar.calendar.component(.year, from: now)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMM d" : "MMM d y")
        return Strings.Projects.due(formatter.string(from: day))
    }

    /// True once the day has ended: the morning after is the first moment it reads as past.
    static func isPast(_ text: String, now: Date, calendar: HouseholdCalendar = HouseholdCalendar()) -> Bool {
        guard let day = day(from: text, calendar: calendar) else { return false }
        return calendar.startOfDay(now) > day
    }
}
