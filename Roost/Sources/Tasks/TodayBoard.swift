// What the Tasks tab shows, on top of what TodayPlanner already worked out: the row order inside a
// person's card, the week bar's split, whether a check-off was the day's last one, and the one status
// line under the header.
//
// No SwiftUI and no store here, so every rule is tested directly (see Tests/TodayBoardTests.swift).
import Foundation
import RoostCore

enum TodayBoard {
    // MARK: - Row order

    /// One person's rows in the order the card draws them:
    ///
    /// 1. **By escalation stage, loudest first** — alert (5+ days), then pointed, then nudge, then what
    ///    is merely due today. The colour going down the card only ever gets calmer, so the state of
    ///    the list is legible without reading a word of it, and the five-day row cannot be scrolled
    ///    past. Within one stage the planner's order stands: cat care first, then most days late.
    /// 2. Then what was checked off today, so a finished row sinks under the work that is left but is
    ///    still there to un-check.
    ///
    /// This is the order Kitchen mode already uses for its overdue cards, so the two screens agree.
    static func ordered(_ rows: [TodayRow]) -> [TodayRow] {
        let due = rows.filter { !$0.isDone }
        // enumerated(), so rows at the same stage keep the order the planner put them in.
        let byStage = due.enumerated().sorted { left, right in
            left.element.stage == right.element.stage
                ? left.offset < right.offset
                : left.element.stage > right.element.stage
        }
        return byStage.map(\.element) + rows.filter(\.isDone)
    }

    // MARK: - Week bar

    /// Anne's share of the week's completions, 0...1, for the two-colour bar under the streaks.
    ///
    /// `nil` when neither of them has finished anything this week: the bar then draws an empty track,
    /// because a 50/50 split of nothing would read as a tie that has not happened.
    static func anneShare(doneThisWeek: [Person: Int]) -> Double? {
        let anne = doneThisWeek[.anne] ?? 0
        let total = anne + (doneThisWeek[.wes] ?? 0)
        guard total > 0 else { return nil }
        return Double(anne) / Double(total)
    }

    // MARK: - Celebration

    /// Whether checking `row` off empties the list it came from. Un-checking never does.
    ///
    /// Worked out from the rows already on screen rather than from a fresh plan, because the store's
    /// query has not caught up at the moment of the tap.
    static func clearsTheList(_ rows: [TodayRow], checking row: TodayRow) -> Bool {
        guard !row.isDone else { return false }
        return !rows.contains { !$0.isDone && $0.id != row.id }
    }

    /// The gate in front of the day's one celebration.
    ///
    /// It fires when the phone's own person checks off the last thing they owed today — not for the
    /// other person's column, not on an un-check, and at most once a day, so un-checking a row and
    /// checking it again does not set the confetti off twice.
    struct Celebration: Equatable {
        /// The day already celebrated, as a start-of-day date.
        private(set) var celebratedDay: Date?

        init(celebratedDay: Date? = nil) {
            self.celebratedDay = celebratedDay
        }

        mutating func fires(when rows: [TodayRow], checking row: TodayRow, as me: Person?, on day: Date) -> Bool {
            guard let me, row.person == me else { return false }
            guard TodayBoard.clearsTheList(rows, checking: row) else { return false }
            guard celebratedDay != day else { return false }
            celebratedDay = day
            return true
        }
    }

    // MARK: - Status line

    /// The one line under the header. Offline is a notice, never a modal: two phones on a home tunnel
    /// are out of touch often, and the queue replays on its own.
    struct Notice: Equatable {
        /// `quiet` is secondary text; `notice` is the info role, for something worth reading.
        enum Tone: Equatable {
            case quiet, notice
        }

        let tone: Tone
        let text: String
    }

    static func notice(isPaired: Bool, isSyncing: Bool, outcome: SyncOutcome?, lastSyncAt: Date?,
                       now: Date = Date()) -> Notice
    {
        if isSyncing || outcome == .coalesced {
            return Notice(tone: .quiet, text: Strings.Tasks.syncing)
        }
        if !isPaired || outcome == .unpaired {
            return Notice(tone: .notice, text: Strings.Tasks.notPaired)
        }
        if case .failed = outcome {
            return Notice(tone: .notice, text: Strings.Tasks.offline(lastSynced(lastSyncAt, now: now)))
        }
        guard lastSyncAt != nil else {
            return Notice(tone: .quiet, text: Strings.Tasks.neverSynced)
        }
        return Notice(tone: .quiet, text: Strings.Tasks.synced(lastSynced(lastSyncAt, now: now)))
    }

    /// "never", "just now" inside a minute, else the system's relative wording ("5 minutes ago").
    static func lastSynced(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return Strings.Tasks.never }
        if now.timeIntervalSince(date) < 60 {
            return Strings.Tasks.justNow
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
