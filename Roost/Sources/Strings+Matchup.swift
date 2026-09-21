import Foundation
import RoostCore

extension Strings {
    enum Matchup {
        static let title = "Matchup"
        static let review = "Review"
        static let view = "View matchup"
        static let completed = "Chores completed"
        static let left = "Chores left"
        static let streak = "Daily streak"
        static let streakHint = "A streak grows when every daily chore is done."
        static let recent = "Recent completions"
        static let empty = "No completions yet."
        static let unknownChore = "Retired chore"

        static func handoff(from name: String) -> String {
            "Handoff from \(name)"
        }

        static func days(_ count: Int) -> String {
            "\(count) \(count == 1 ? "day" : "days")"
        }

        static func left(_ count: Int) -> String {
            "\(count) \(count == 1 ? "chore" : "chores") left"
        }

        static func weekDone(_ count: Int) -> String {
            "\(count) done this week"
        }

        static func week(start: Date, end: Date) -> String {
            var format = Date.FormatStyle.dateTime.month(.abbreviated).day()
            format.timeZone = TimeZone(identifier: HouseholdCalendar.timeZoneIdentifier)!
            return "This week · \(start.formatted(format)) – \(end.formatted(format))"
        }

        static func activity(person: String, date: Date) -> String {
            "\(person) · \(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
        }
    }
}
