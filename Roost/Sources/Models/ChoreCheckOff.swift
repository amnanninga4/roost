// What a check-off means, in one place. This used to live privately inside TodayScreen, which was
// fine while the board was the only screen with rows on it. Home has rows too, and two copies of
// this is how the two screens would begin disagreeing about what ticking a box does.
//
// The store write is shared. The *feel* is not: the haptic counters and the once-a-day celebration
// are @State on each screen, because they are about that screen's frame rather than about the
// household's data. So this performs the write and reports what happened, and the caller decides
// what that feels like.
import RoostCore
import SwiftData

enum ChoreCheckOff {
    enum Outcome {
        /// `celebrates` is true only on the tap that clears this phone's own column, once a day.
        case checked(celebrates: Bool)
        case unchecked
    }

    @discardableResult
    static func toggle(
        _ row: TodayRow,
        among rows: [TodayRow],
        me: Person?,
        completions: [CompletionRecord],
        celebration: inout TodayBoard.Celebration,
        calendar: HouseholdCalendar,
        context: ModelContext,
        sync: SyncCoordinator?,
        now: Date = .now
    ) -> Outcome {
        let outcome: Outcome
        switch row.kind {
        case .due:
            let record = CompletionRecord(
                id: UUID().uuidString, choreId: row.chore.id, person: row.person.rawValue, completedAt: now
            )
            context.insert(record)
            let celebrates = celebration.fires(
                when: rows, checking: row, as: me, on: calendar.startOfDay(now)
            )
            outcome = .checked(celebrates: celebrates)
        case let .done(completionId):
            if let record = completions.first(where: { $0.id == completionId }) {
                record.removed = true
                if record.syncedAt == nil, !record.rejected {
                    record.deleteSynced = true // never reached the server; nothing to replay
                }
            }
            outcome = .unchecked
        }
        try? context.save()
        if case .due = row.kind {
            // "Wes said no" has been read by the time you are checking things off again.
            try? HandoffActions.clearNotices(for: row.person, in: context)
        }
        sync?.syncSoon()
        return outcome
    }
}
