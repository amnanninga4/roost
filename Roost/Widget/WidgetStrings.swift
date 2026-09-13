// Every user-facing string in the widget, in one place — the same rule `Roost/Sources/Strings.swift`
// follows for the app, and a separate file because the extension is a separate binary and cannot import
// the app's.
//
// Kept deliberately short. A widget is read in half a second at arm's length, so the words here are labels,
// not sentences; the two states that do need a sentence (no snapshot, not paired) get one line each.
import Foundation

enum WidgetStrings {
    /// The name in the widget gallery, and its one-line description under it.
    static let displayName = "Today"
    static let description = "What each of you still owes today."

    /// The eyebrow over the two columns on the medium family. Not a logo — it says which day this is about.
    static let today = "TODAY"

    /// Under the hero number. Uppercase because it is set in the mono eyebrow rung.
    static let dueLabel = "DUE"
    /// The hero line when a person owes nothing: the number would be a zero, and a zero reads as broken.
    static let allDone = "All done"
    /// "1 late" / "4 late" — how many of the due rows are already past their day.
    static func late(_ count: Int) -> String {
        "\(count) late"
    }

    /// "9 day streak", under a person's count. "day streak" does not pluralize here — the app's own
    /// streak header words it the same way (`Strings.Streak.dayStreak`).
    static func streak(_ days: Int) -> String {
        "\(days) day streak"
    }

    /// The accessory families have one line to work with, so the count and the word share it: "9 due".
    static func due(_ count: Int) -> String {
        "\(count) due"
    }

    /// No snapshot on disk yet: a fresh install that has not opened the app, or an unsigned build.
    static let noData = "Open Roost"
    /// There is a snapshot, but the phone is not paired, so there is no "you" to count for.
    static let notPaired = "Not paired yet"

    /// VoiceOver reads the whole widget as one sentence.
    /// "Anne, 9 due today, 2 late, 4 day streak"
    static func summary(name: String, due: Int, overdue: Int, streak days: Int) -> String {
        var parts = ["\(name), \(due) due today"]
        if overdue > 0 {
            parts.append(late(overdue))
        }
        parts.append(streak(days))
        return parts.joined(separator: ", ")
    }

    /// The one accessibility label for the empty states.
    static let noDataSummary = "Roost has nothing to show yet. Open the app."
}
