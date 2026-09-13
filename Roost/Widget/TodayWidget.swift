// The widget itself: one entry, read from the App Group snapshot, redrawn every half hour.
//
// There is no network here and no store. The provider does one thing — read a file — and if the file is
// missing or unreadable the entry carries nil and the views show their plain state. That is what makes the
// widget instant: nothing it does can block, so the system never has to give up on it.
//
// Refresh: one entry now, and ask the system to come back in thirty minutes. Roost's numbers change when
// somebody checks something off, not on a clock, and the app pushes those through
// `WidgetCenter.reloadAllTimelines()` (see `SnapshotWriter`). The half hour is the floor under that — it is
// what makes the escalation counts roll over on a phone nobody has picked up, inside the ~40-70 reloads a
// day WidgetKit allows.
import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    /// nil when there is no readable snapshot: a fresh install, or a build with no App Group entitlement.
    let snapshot: RoostSnapshot?
}

struct TodayProvider: TimelineProvider {
    /// How long the system waits before asking for a new timeline.
    static let refreshInterval: TimeInterval = 30 * 60

    private let store: SnapshotStore?

    init(store: SnapshotStore? = SnapshotStore.appGroup()) {
        self.store = store
    }

    /// The gallery's skeleton, drawn while the real snapshot loads. Shaped like the real thing so the
    /// layout does not jump, with numbers the reader will not mistake for theirs.
    func placeholder(in _: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: .placeholder)
    }

    /// The widget gallery's preview, and what the system shows in a transient context. The real snapshot
    /// when there is one, so the reader picks the widget already seeing their own day.
    func getSnapshot(in _: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: .now, snapshot: store?.read() ?? .placeholder))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date.now
        let entry = TodayEntry(date: now, snapshot: store?.read())
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(Self.refreshInterval))))
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "xyz.hinescreative.roost.today", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetStrings.displayName)
        .description(WidgetStrings.description)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

// MARK: - the gallery sample

extension RoostSnapshot {
    /// What the widget gallery and the placeholder draw. Anne's side is the reader's, so the small family
    /// has something to be about; the numbers are plainly a sample and not a real day.
    static let placeholder = RoostSnapshot(
        generatedAt: .now,
        me: "anne",
        people: [
            Person(
                id: "anne",
                name: "Anne",
                due: 4,
                overdue: 1,
                streak: 6,
                top: [
                    Item(title: "Scoop litter", stage: .nudge, daysOverdue: 1),
                    Item(title: "Laundry", stage: .dueToday, daysOverdue: 0),
                    Item(title: "Wipe down tables", stage: .dueToday, daysOverdue: 0),
                ]
            ),
            Person(
                id: "wes",
                name: "Wes",
                due: 3,
                overdue: 0,
                streak: 4,
                top: [
                    Item(title: "Garbage can to street", stage: .dueToday, daysOverdue: 0),
                    Item(title: "PM wet cat food", stage: .dueToday, daysOverdue: 0),
                ]
            ),
        ]
    )
}
