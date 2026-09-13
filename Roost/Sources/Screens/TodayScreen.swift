// The Tasks tab: what each of them owes today, and the one control the app is really about — checking
// a chore off.
//
// Both columns are always on screen, each on its own card, so nobody has to switch a filter to see
// whether the other person is keeping up. Order, the celebration rule, and the status line come from
// TodayBoard; the row is ChoreRowView; colours, type, spacing, motion, and haptics are RoostDesign's.
//
// A minute-by-minute TimelineView re-renders the screen, so the date line, the days-late counts, and
// the "synced 5 minutes ago" wording stay honest without the store changing.
import RoostCore
import RoostDesign
import SwiftData
import SwiftUI

struct TodayScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SyncCoordinator.self) private var sync

    @Query(filter: #Predicate<ChoreRecord> { !$0.retired }, sort: \ChoreRecord.sortOrder)
    private var choreRecords: [ChoreRecord]
    @Query(filter: #Predicate<CompletionRecord> { !$0.removed })
    private var completionRecords: [CompletionRecord]
    @Query private var syncStates: [SyncState]

    @State private var showSettings = false
    @State private var showKitchen = false
    /// Two counters and a gate, so the feel of a tap is decided once and never on a cold launch:
    /// a haptic fires when one of these changes, and they only change under a finger.
    @State private var checkOffs = 0
    @State private var undos = 0
    @State private var celebrations = 0
    @State private var celebration = TodayBoard.Celebration()

    private let calendar = HouseholdCalendar()

    private var state: SyncState? {
        syncStates.first
    }

    private var me: Person? {
        state?.person.flatMap(Person.init(rawValue:))
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                content(asOf: context.date)
            }
            .background(RoostColor.Role.background.color)
            .navigationTitle(Strings.appTitle)
            .toolbarTitleDisplayMode(.inline)
            .toolbar { gear }
            .sheet(isPresented: $showSettings) { SettingsScreen() }
            .fullScreenCover(isPresented: $showKitchen) { KitchenScreen() }
        }
        .tint(RoostColor.Role.accent.color)
        .overlay { CelebrationView(trigger: $celebrations) }
        .roostHaptic(.checkOff, trigger: checkOffs)
        .roostHaptic(.undo, trigger: undos)
        .roostHaptic(.milestone, trigger: celebrations)
        .task {
            ensureActiveFrom()
            await sync.syncNow()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                sync.syncSoon()
            }
        }
    }

    private func content(asOf now: Date) -> some View {
        let plan = plan(asOf: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: RoostSpacing.sectionGap) {
                TodayHeaderView(date: now, streaks: StreakHeaderModel(plan: plan), notice: notice(asOf: now))
                ForEach(Person.allCases, id: \.self) { person in
                    let rows = TodayBoard.ordered(plan.rows(for: person))
                    PersonColumnView(
                        person: person,
                        rows: rows,
                        dueCount: plan.dueCount(for: person),
                        isMine: person == me,
                        toggle: { row in toggle(row, among: rows) }
                    )
                }
            }
            .padding(.horizontal, RoostSpacing.screenMargin)
            .padding(.top, RoostSpacing.sm)
            .padding(.bottom, RoostSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await sync.syncNow() }
    }

    private var gear: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(Strings.Kitchen.menuEntry, systemImage: "rectangle.on.rectangle") { showKitchen = true }
                NavigationLink {
                    ChoreListScreen()
                } label: {
                    Label(Strings.Tasks.allChores, systemImage: "list.bullet")
                }
                Button(Strings.Settings.title, systemImage: "iphone.and.arrow.forward") { showSettings = true }
                Button(Strings.Tasks.syncNow, systemImage: "arrow.triangle.2.circlepath") { sync.syncSoon() }
            } label: {
                Label(Strings.Tasks.gear, systemImage: "gearshape")
            }
        }
    }

    // MARK: - Derived state

    private func plan(asOf now: Date) -> TodayPlan {
        let chores = choreRecords.compactMap { try? $0.toChore() }
        let completions = completionRecords.compactMap { try? $0.toCompletion() }
        let activeFrom = state?.activeFrom ?? calendar.startOfDay(now)
        return TodayPlanner.plan(
            chores: chores, completions: completions, asOf: now, activeFrom: activeFrom, calendar: calendar
        )
    }

    private func notice(asOf now: Date) -> TodayBoard.Notice {
        TodayBoard.notice(
            isPaired: state?.isPaired ?? false,
            outcome: sync.lastOutcome,
            lastSyncAt: sync.lastSyncAt,
            // The same line the list tabs print, so the two never disagree about the last pass.
            statusLine: sync.statusLine,
            now: now
        )
    }

    // MARK: - Actions

    /// Check off, or un-check. `rows` is the column the row was tapped in, as it stood a moment ago:
    /// the store's query has not caught up yet, so the celebration rule is decided from what was drawn.
    private func toggle(_ row: TodayRow, among rows: [TodayRow]) {
        let now = Date()
        switch row.kind {
        case .due:
            let record = CompletionRecord(
                id: UUID().uuidString, choreId: row.chore.id, person: row.person.rawValue, completedAt: now
            )
            context.insert(record)
            checkOffs += 1
            if celebration.fires(when: rows, checking: row, as: me, on: calendar.startOfDay(now)) {
                celebrations += 1
            }
        case let .done(completionId):
            if let record = completionRecords.first(where: { $0.id == completionId }) {
                record.removed = true
                if record.syncedAt == nil, !record.rejected {
                    record.deleteSynced = true // never reached the server; nothing to replay
                }
            }
            undos += 1
        }
        try? context.save()
        sync.syncSoon()
    }

    /// The household start date, fixed the first time the screen renders (or the earliest completion, if any).
    private func ensureActiveFrom() {
        guard let state, state.activeFrom == nil else { return }
        let now = Date()
        let earliest = completionRecords.map(\.completedAt).min() ?? now
        state.activeFrom = calendar.startOfDay(min(earliest, now))
        try? context.save()
    }
}
