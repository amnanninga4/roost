// Pure: what the paired person's due list for one day turns into as local notifications.
// No UNUserNotificationCenter here; NotificationScheduler turns the plan into requests and submits it.
//
// Per day, for the paired person only:
//   09:00 Chicago  one digest listing everything due that day (skipped when nothing is due)
//   18:00 Chicago  one notification per overdue chore, worded by EscalationStage (the mockup's ladder)
// Identifiers are deterministic per chore + date, so a replan replaces rather than duplicates.
import Foundation
import RoostCore
import UserNotifications

struct PlannedNotification: Hashable, Sendable {
    let id: String
    let title: String
    let body: String
    /// Absolute fire time; the calendar trigger is built from its Chicago components.
    let fireAt: Date
}

enum NotificationPlanner {
    static let identifierPrefix = "roost."
    static let digestHour = 9
    static let overdueHour = 18
    static let threadIdentifier = "roost"

    /// Notifications for `person` on the day containing `date`. `due` is `Scheduler.due(on:)` for that day;
    /// only `due[person]` is read, so the other person's chores can never leak into this phone's notifications.
    /// Anything that would fire at or before `now` is dropped (iOS will not deliver a calendar trigger in the past).
    static func plan(due: [Person: [DueItem]], for person: Person, on date: Date, now: Date,
                     calendar: HouseholdCalendar = HouseholdCalendar()) -> [PlannedNotification]
    {
        let mine = due[person] ?? []
        let day = dayKey(date, calendar: calendar)
        var out: [PlannedNotification] = []

        if !mine.isEmpty {
            out.append(PlannedNotification(
                id: "\(identifierPrefix)digest.\(day)",
                title: "Due today",
                body: digestBody(mine.map(\.chore.title)),
                fireAt: time(digestHour, on: date, calendar: calendar)
            ))
        }

        let overdueAt = time(overdueHour, on: date, calendar: calendar)
        for item in mine where item.stage > .dueToday {
            let copy = overdueCopy(for: item)
            out.append(PlannedNotification(
                id: "\(identifierPrefix)overdue.\(item.chore.id).\(day)",
                title: copy.title,
                body: copy.body,
                fireAt: overdueAt
            ))
        }

        return out.filter { $0.fireAt > now }
    }

    /// The app badge: how many of `person`'s chores are past their period.
    static func badgeCount(due: [Person: [DueItem]], for person: Person) -> Int {
        (due[person] ?? []).filter { $0.daysOverdue > 0 }.count
    }

    /// Mockup ladder: nudge "Still no <title>…", pointed "The cat has feelings about this." (cat care) /
    /// "Getting overdue." (home), alert "<Title> emergency".
    static func overdueCopy(for item: DueItem) -> (title: String, body: String) {
        let title = item.chore.title
        let late = "\(item.daysOverdue) \(item.daysOverdue == 1 ? "day" : "days") late"
        switch item.stage {
        case .dueToday:
            return (title, "Due today")
        case .nudge:
            return ("Still no \(title)…", "\(late). A little nudge, nothing serious yet.")
        case .pointed:
            let head = item.chore.category == .catCare ? "The cat has feelings about this." : "Getting overdue."
            return (head, "\(title) · \(late).")
        case .alert:
            return ("\(title) emergency", "\(late). On both screens until it's done.")
        }
    }

    static func digestBody(_ titles: [String]) -> String {
        let shown = titles.prefix(3)
        let rest = titles.count - shown.count
        var body = shown.joined(separator: ", ")
        if rest > 0 {
            body += " and \(rest) more"
        }
        return body
    }

    /// yyyy-MM-dd in Chicago, for identifiers.
    static func dayKey(_ date: Date, calendar: HouseholdCalendar) -> String {
        let c = calendar.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func time(_ hour: Int, on date: Date, calendar: HouseholdCalendar) -> Date {
        calendar.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.startOfDay(date))!
    }

    /// A one-shot calendar trigger at the plan's Chicago wall-clock time.
    static func request(for planned: PlannedNotification,
                        calendar: HouseholdCalendar = HouseholdCalendar()) -> UNNotificationRequest
    {
        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.body = planned.body
        content.sound = .default
        content.threadIdentifier = threadIdentifier

        var components = calendar.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: planned.fireAt)
        components.timeZone = calendar.calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: planned.id, content: content, trigger: trigger)
    }
}
