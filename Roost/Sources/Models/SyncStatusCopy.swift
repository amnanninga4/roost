// How the header's "Synced …" line reads. Pure, so the bands can be tested without a clock.
import Foundation

/// The words for how long ago the last pass finished.
///
/// `RelativeDateTimeFormatter` answers "in 0 sec." for a sync that has just landed: the elapsed time
/// rounds to nothing and it falls back to the future phrasing. Under a header that already carries a
/// count, "Synced in 0 sec." reads as a duration — as if the sync were still coming — which is the
/// opposite of what it means. So the bands are spelled out instead.
///
/// A sync that just happened is a moment, not a measurement: it reads "just now". After that a count
/// of seconds is worth having, because it says the list is current. Past a minute the seconds stop
/// mattering and minutes do. Past an hour neither does — what a person wants to know then is *when*,
/// so the clock time takes over.
enum SyncStatusCopy {
    /// Anything fresher than this is a moment rather than a count.
    static let momentWindow: TimeInterval = 5
    /// From here on the clock time says more than a count of minutes.
    static let clockWindow: TimeInterval = 60 * 60

    /// `now` is injectable so the tests can stand still.
    static func synced(at date: Date, now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(date)
        // A negative interval means the phone's clock moved backwards between the sync and this
        // render. There is no sensible count to show, and "just now" is true enough.
        guard elapsed >= momentWindow else { return Strings.Sync.syncedJustNow }
        guard elapsed >= 60 else { return Strings.Sync.syncedSecondsAgo(Int(elapsed)) }
        guard elapsed >= clockWindow else { return Strings.Sync.syncedMinutesAgo(Int(elapsed / 60)) }
        return Strings.Sync.syncedAt(date.formatted(date: .omitted, time: .shortened))
    }
}
