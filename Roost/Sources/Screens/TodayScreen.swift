// The Tasks tab: what each of them owes today, and the one control the app is really about — checking
// a chore off.
//
// Both columns are always on screen, each on its own card, so nobody has to switch a filter to see
// whether the other person is keeping up. The paired person's own column comes first
// (`TodayBoard.columnPeople`). Order, the celebration rule, and the status line come from
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
    @Environment(RootNavigation.self) private var navigation

    @Query(filter: #Predicate<ChoreRecord> { !$0.retired }, sort: \ChoreRecord.sortOrder)
    private var choreRecords: [ChoreRecord]
    @Query(filter: #Predicate<CompletionRecord> { !$0.removed })
    private var completionRecords: [CompletionRecord]
    @Query(filter: #Predicate<HandoffRecord> { !$0.removed }, sort: \HandoffRecord.createdAt)
    private var handoffRecords: [HandoffRecord]
    @Query private var syncStates: [SyncState]

    /// Three counters and a gate, so the feel of a tap is decided once and never on a cold launch:
    /// a haptic fires when one of these changes, and they only change under a finger.
    @State private var checkOffs = 0
    @State private var undos = 0
    @State private var celebrations = 0
    @State private var answers = 0
    @State private var celebration = TodayBoard.Celebration()
    /// The row waiting on the one confirmation before an offer is made. Nil the rest of the time.
    @State private var pendingOffer: TodayRow?
    /// Ruling 2026-09-14, carried over from the header: expand state persists; default collapsed
    /// on a fresh install. The key is unchanged so a phone that had it open keeps it open.
    @AppStorage("roost.today.streakExpanded") private var streaksExpanded = false

    private let calendar = HouseholdCalendar()

    private var state: SyncState? {
        syncStates.first
    }

    private var me: Person? {
        state?.person.flatMap(Person.init(rawValue:))
    }

    /// The other half of the household, from this phone's own person.
    private func other(than person: Person) -> Person {
        person == .anne ? .wes : .anne
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                content(asOf: context.date)
            }
            .background(RoostColor.Role.background.color)
            .navigationTitle(Strings.appTitle)
            .toolbarTitleDisplayMode(.inline)
        }
        .tint(RoostColor.Role.accent.color)
        .overlay { CelebrationView(trigger: $celebrations) }
        .roostHaptic(.checkOff, trigger: checkOffs)
        .roostHaptic(.undo, trigger: undos)
        .roostHaptic(.milestone, trigger: celebrations)
        .roostHaptic(.selection, trigger: answers)
        .confirmationDialog(
            offerPrompt,
            isPresented: .init(get: { pendingOffer != nil }, set: {
                if !$0 {
                    pendingOffer = nil
                }
            }),
            titleVisibility: .visible
        ) {
            if let row = pendingOffer {
                Button(Strings.Handoffs.confirmAction(other(than: row.person).displayName)) { makeOffer(row) }
            }
            Button(Strings.Settings.cancel, role: .cancel) { pendingOffer = nil }
        }
        .task { await sync.syncNow() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                sync.syncSoon()
            }
        }
    }

    /// The one question asked before a turn changes hands: who, what, and which period.
    private var offerPrompt: String {
        guard let row = pendingOffer else { return "" }
        return Strings.Handoffs.confirmTitle(
            other(than: row.person).displayName,
            chore: row.chore.title,
            period: row.chore.cadence.periodPhrase
        )
    }

    private func content(asOf now: Date) -> some View {
        let plan = plan(asOf: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: RoostSpacing.sectionGap) {
                TodayHeaderView(date: now, notice: notice(asOf: now))
                StreakSummaryView(model: StreakHeaderModel(plan: plan), me: me, expanded: $streaksExpanded)
                ForEach(TodayBoard.columnPeople(me: me), id: \.self) { person in
                    let rows = TodayBoard.ordered(plan.rows(for: person))
                    let isMine = person == me
                    PersonColumnView(
                        person: person,
                        rows: rows,
                        dueCount: plan.dueCount(for: person),
                        isMine: isMine,
                        offers: isMine ? plan.offers(for: person) : [],
                        toggle: { row in toggle(row, among: rows) },
                        offer: { row in pendingOffer = row },
                        withdraw: withdrawOffer,
                        answer: answerOffer,
                        showInAllChores: { navigation.showAllChores() }
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

    // MARK: - Derived state

    private func plan(asOf now: Date) -> TodayPlan {
        let chores = choreRecords.compactMap { try? $0.toChore() }
        let completions = completionRecords.compactMap { try? $0.toCompletion() }
        // The household start comes from the server on every /sync; today until the first one lands, so
        // a phone that has never synced shows no backlog rather than a guess at one.
        let activeFrom = state?.activeFrom ?? calendar.startOfDay(now)
        return TodayPlanner.plan(
            chores: chores,
            completions: completions,
            handoffs: handoffRecords.compactMap { try? $0.toSnapshot() },
            asOf: now,
            activeFrom: activeFrom,
            calendar: calendar
        )
    }

    /// The rules object the actions ask about eligibility. Built from the same inputs as the plan, so
    /// `canOffer` cannot answer one thing on the row and another under the finger.
    private func rules(asOf now: Date) -> HandoffRules {
        let chores = choreRecords.compactMap { try? $0.toChore() }
        let activeFrom = state?.activeFrom ?? calendar.startOfDay(now)
        let live = HandoffPresentation.live(handoffRecords.compactMap { try? $0.toSnapshot() })
        return HandoffRules(
            scheduler: Scheduler(chores: chores, activeFrom: activeFrom, calendar: calendar),
            handoffs: live
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
        switch ChoreCheckOff.toggle(
            row, among: rows, me: me, completions: completionRecords,
            celebration: &celebration, calendar: calendar, context: context, sync: sync
        ) {
        case let .checked(celebrates):
            checkOffs += 1
            if celebrates {
                celebrations += 1
            }
        case .unchecked:
            undos += 1
        }
    }

    // MARK: - Handoffs

    /// The offer itself, after the one confirmation. `HandoffActions.offer` asks `HandoffRules` again and
    /// returns nil if the answer changed between the long press and the tap — a sync landing in between
    /// can settle the period — so nothing is queued that the server would only refuse.
    private func makeOffer(_ row: TodayRow) {
        pendingOffer = nil
        let now = Date()
        guard let mine = me, row.person == mine else { return }
        let offered = try? HandoffActions.offer(
            row.chore, from: mine, to: other(than: mine), rules: rules(asOf: now), on: now, in: context
        )
        guard offered != nil else { return }
        answers += 1
        sync.syncSoon()
    }

    /// Takes back an offer that never left the phone. Not reachable once it has synced: the server has no
    /// withdraw route, so `PersonColumnView` stops offering the action.
    private func withdrawOffer(_ id: String) {
        try? HandoffActions.withdraw(id, in: context)
        answers += 1
    }

    private func answerOffer(_ offer: IncomingOffer, _ decision: HandoffRules.Decision) {
        try? HandoffActions.answer(offer.id, as: decision, in: context)
        answers += 1
        sync.syncSoon()
    }
}
