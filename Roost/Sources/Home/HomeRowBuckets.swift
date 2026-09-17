import Foundation
import RoostCore

enum HomeRowBucket: Equatable {
    case overdue, today, later
}

struct HomeRowGroups: Equatable {
    var overdue: [TodayRow] = []
    var today: [TodayRow] = []
    var later: [TodayRow] = []
}

enum HomeRowBuckets {
    static func bucket(for row: TodayRow, calendar: HouseholdCalendar, on date: Date) -> HomeRowBucket {
        if row.isDone {
            return .today
        }
        if row.daysOverdue > 0 {
            return .overdue
        }
        if case let .due(item) = row.kind, calendar.dayIndex(item.dueLastDay) > calendar.dayIndex(date) {
            return .later
        }
        return .today
    }

    static func group(_ rows: [TodayRow], calendar: HouseholdCalendar, on date: Date) -> HomeRowGroups {
        var groups = HomeRowGroups()
        for row in rows {
            switch bucket(for: row, calendar: calendar, on: date) {
            case .overdue: groups.overdue.append(row)
            case .today: groups.today.append(row)
            case .later: groups.later.append(row)
            }
        }
        return groups
    }
}
