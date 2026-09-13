// Reads the store, plans the day, and writes the snapshot the widget draws. Then tells WidgetKit.
//
// Called by `SyncCoordinator` after every pass, whatever the pass returned. That is on purpose: the plan
// comes from the local store, so it succeeds offline, and the app is offline-first — a chore checked off
// with no signal should change the Home Screen immediately, not when the tunnel comes back.
//
// The same code path runs on launch, on foreground, after a check-off, after a list write, and after an
// unpair. There is no second way to write this file.
import Foundation
import RoostCore
import SwiftData
import WidgetKit

@MainActor
final class SnapshotWriter {
    private let container: ModelContainer
    /// nil when this build has no App Group entitlement (an unsigned simulator build). Then `write()` plans
    /// and throws the result away, which is cheap and keeps the call sites free of conditionals.
    private let store: SnapshotStore?
    private let now: () -> Date
    private let reload: @MainActor () -> Void
    private let calendar = HouseholdCalendar()
    /// So a missing container is explained once per launch rather than on every sync.
    private var warned = false

    init(
        container: ModelContainer,
        store: SnapshotStore? = SnapshotStore.appGroup(),
        now: @escaping () -> Date = { Date() },
        reload: @MainActor @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.container = container
        self.store = store
        self.now = now
        self.reload = reload
    }

    /// Plans the day and writes it. Returns what it wrote, for tests; nil when the plan could not be built.
    @discardableResult
    func write() -> RoostSnapshot? {
        guard let snapshot = try? plan() else { return nil }
        guard let store else {
            if !warned {
                warned = true
                print("Roost: no App Group container, so the widget has nothing to read")
            }
            return snapshot
        }
        do {
            try store.write(snapshot)
            reload()
        } catch {
            print("Roost: could not write the widget snapshot (\(error))")
        }
        return snapshot
    }

    /// The same plan the Tasks tab makes, from the same records and the same `activeFrom`.
    private func plan() throws -> RoostSnapshot {
        let context = ModelContext(container)
        let state = try context.fetch(FetchDescriptor<SyncState>()).first
        let me = state?.person.flatMap(Person.init(rawValue:))

        let chores = try context.fetch(FetchDescriptor<ChoreRecord>(
            predicate: #Predicate { !$0.retired }, sortBy: [SortDescriptor(\.sortOrder)]
        )).compactMap { try? $0.toChore() }
        let completions = try context.fetch(FetchDescriptor<CompletionRecord>(
            predicate: #Predicate { !$0.removed }
        )).compactMap { try? $0.toCompletion() }

        let date = now()
        let plan = TodayPlanner.plan(
            chores: chores,
            completions: completions,
            asOf: date,
            activeFrom: state?.activeFrom ?? calendar.startOfDay(date),
            calendar: calendar
        )
        return SnapshotBuilder.snapshot(from: plan, me: me, generatedAt: date)
    }
}
