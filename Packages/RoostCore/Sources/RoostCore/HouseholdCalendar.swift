import Foundation

/// All day / week / month arithmetic for Roost happens in America/Chicago with weeks starting Monday.
/// Period indexes count from an anchor Monday (2026-01-05) so every cadence has a stable integer period
/// that both phones compute identically.
public struct HouseholdCalendar: Sendable {
    public static let timeZoneIdentifier = "America/Chicago"

    public let calendar: Calendar

    public init(timeZone: TimeZone = TimeZone(identifier: HouseholdCalendar.timeZoneIdentifier)!) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = 2 // Monday
        cal.minimumDaysInFirstWeek = 4
        calendar = cal
    }

    /// 2026-01-05 00:00 local, a Monday. Period 0 for every cadence.
    public var anchor: Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!
    }

    public func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Start of the next local day (exclusive end of `date`'s day).
    public func endOfDay(_ date: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: startOfDay(date))!
    }

    public func date(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    public func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)!
    }

    /// Whole local days from the anchor day to the day containing `date`. Negative before the anchor.
    public func dayIndex(_ date: Date) -> Int {
        calendar.dateComponents([.day], from: anchor, to: startOfDay(date)).day!
    }

    /// The start of the day `index` days after the anchor.
    public func day(at index: Int) -> Date {
        calendar.date(byAdding: .day, value: index, to: anchor)!
    }

    public func periodIndex(_ cadence: Cadence, containing date: Date) -> Int {
        switch cadence {
        case .daily:
            return dayIndex(date)
        case .weekly:
            return floorDiv(dayIndex(date), 7)
        case .biweekly:
            return floorDiv(dayIndex(date), 14)
        case .monthly:
            let c = calendar.dateComponents([.year, .month], from: date)
            return (c.year! - 2026) * 12 + (c.month! - 1)
        }
    }

    /// Start of the first day and start of the last day of a period.
    public func periodBounds(_ cadence: Cadence, index: Int) -> (firstDay: Date, lastDay: Date) {
        switch cadence {
        case .daily:
            let d = day(at: index)
            return (d, d)
        case .weekly:
            return (day(at: index * 7), day(at: index * 7 + 6))
        case .biweekly:
            return (day(at: index * 14), day(at: index * 14 + 13))
        case .monthly:
            let year = 2026 + floorDiv(index, 12)
            let month = mod(index, 12) + 1
            let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
            let nextFirst = calendar.date(byAdding: .month, value: 1, to: first)!
            return (first, calendar.date(byAdding: .day, value: -1, to: nextFirst)!)
        }
    }

    /// Monday 00:00 of the week containing `date`, and the following Monday 00:00 (exclusive).
    public func weekBounds(containing date: Date) -> (start: Date, end: Date) {
        let index = periodIndex(.weekly, containing: date)
        return (day(at: index * 7), day(at: index * 7 + 7))
    }

    func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    func mod(_ a: Int, _ b: Int) -> Int {
        let r = a % b
        return r < 0 ? r + b : r
    }
}
