// One person's day. The matchup is the overview; this is their full list — buckets, handoffs,
// the same rows as the board column.
import RoostCore
import RoostDesign
import SwiftData
import SwiftUI

struct PersonDayScreen: View {
    let person: Person
    var onOpenMatchup: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(RootNavigation.self) private var navigation

    @Query(filter: #Predicate<ChoreRecord> { !$0.retired }, sort: \ChoreRecord.sortOrder)
    private var choreRecords: [ChoreRecord]
    @Query(filter: #Predicate<CompletionRecord> { !$0.removed })
    private var completionRecords: [CompletionRecord]
    @Query(filter: #Predicate<HandoffRecord> { !$0.removed }, sort: \HandoffRecord.createdAt)
    private var handoffRecords: [HandoffRecord]
    @Query private var syncStates: [SyncState]

    @State private var checkOffs = 0
    @State private var undos = 0
    @State private var celebrations = 0
    @State private var answers = 0
    @State private var celebration = TodayBoard.Celebration()
    @State private var pendingOffer: TodayRow?
    @State private var reviewingOffer: IncomingOffer?

    private let calendar = HouseholdCalendar()

    private var state: SyncState? {
        syncStates.first
    }

    private var me: Person? {
        state?.person.flatMap(Person.init(rawValue:))
    }

    private var isMine: Bool {
        person == me
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(asOf: context.date)
        }
        .navigationTitle(person.displayName)
        .toolbarTitleDisplayMode(.inline)
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
                Button(Strings.Handoffs.confirmAction(other.displayName)) { makeOffer(row) }
            }
            Button(Strings.Settings.cancel, role: .cancel) { pendingOffer = nil }
        }
        .sheet(item: $reviewingOffer) { offer in
            HandoffOfferCard(
                offer: offer,
                accept: { answerOffer(offer, .accept); reviewingOffer = nil },
                decline: { answerOffer(offer, .decline); reviewingOffer = nil }
            )
            .padding(RoostSpacing.screenMargin)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .refreshable { await sync.syncNow() }
    }

    private var other: Person {
        person == .anne ? .wes : .anne
    }

    private var offerPrompt: String {
        guard let row = pendingOffer else { return "" }
        return Strings.Handoffs.confirmTitle(
            other.displayName,
            chore: row.chore.title,
            period: row.chore.cadence.periodPhrase
        )
    }

    private func content(asOf now: Date) -> some View {
        let plan = plan(asOf: now)
        let rows = TodayBoard.ordered(plan.rows(for: person))
        return ScrollView {
            VStack(alignment: .leading, spacing: RoostSpacing.sectionGap) {
                identitySummary(plan)
                if isMine {
                    ForEach(plan.offers(for: person)) { offer in
                        Button { reviewingOffer = offer } label: {
                            HStack(spacing: RoostSpacing.md) {
                                RoostAvatar(person: offer.from.design).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
                                    Text(Strings.Matchup.handoff(from: offer.from.displayName))
                                        .roostType(.callout)
                                        .foregroundStyle(RoostColor.Role.textPrimary.color)
                                    Text(offer.chore.title).roostType(.caption)
                                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                                }
                                Spacer(minLength: 0)
                                Text(Strings.Matchup.review)
                                    .roostType(.headline)
                                    .foregroundStyle(RoostColor.Role.accent.color)
                            }
                            .frame(minHeight: RoostSpacing.minTapTarget)
                            .padding(RoostSpacing.md)
                            .roostCard()
                        }
                        .buttonStyle(.roostPressQuiet)
                    }
                }
                PersonColumnView(
                    person: person,
                    rows: rows,
                    dueCount: plan.dueCount(for: person),
                    isMine: isMine,
                    calendar: calendar,
                    now: now,
                    showsHeader: false,
                    toggle: { row in toggle(row, among: rows) },
                    offer: isMine ? { row in pendingOffer = row } : nil,
                    withdraw: isMine ? withdrawOffer : nil,
                    answer: isMine ? answerOffer : nil,
                    showInAllChores: { navigation.showAllChores() }
                )
                SyncNoticeLine(notice: sync.notice(for: syncStates, now: now))
            }
            .padding(.horizontal, RoostSpacing.screenMargin)
            .padding(.top, RoostSpacing.sm)
            .padding(.bottom, RoostSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(RoostColor.Role.background.color)
    }

    private func identitySummary(_ plan: TodayPlan) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: RoostSpacing.md))
            : AnyLayout(HStackLayout(alignment: .center, spacing: RoostSpacing.md))
        return layout {
            HStack(spacing: RoostSpacing.sm) {
                HouseholdAvatar(person: person)
                VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
                    Text(person.displayName).roostType(.title)
                        .foregroundStyle(RoostColor.Role.textPrimary.color)
                    Text(Strings.Matchup.left(plan.dueCount(for: person)))
                        .roostType(.callout)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
                Text(Strings.Matchup.weekDone(plan.doneThisWeek[person, default: 0]))
                    .roostType(.caption)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
                Button(action: onOpenMatchup) {
                    HStack(spacing: RoostSpacing.xs) {
                        Text(Strings.Matchup.view)
                        Image(systemName: "chevron.right")
                    }
                    .roostType(.callout)
                    .foregroundStyle(RoostColor.Role.accent.color)
                    .frame(minHeight: RoostSpacing.minTapTarget)
                }
                .buttonStyle(.roostPressQuiet)
                .accessibilityIdentifier("person.openMatchup")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(RoostSpacing.md)
        .roostCard()
    }

    private func plan(asOf now: Date) -> TodayPlan {
        let chores = choreRecords.compactMap { try? $0.toChore() }
        let completions = completionRecords.compactMap { try? $0.toCompletion() }
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

    private func rules(asOf now: Date) -> HandoffRules {
        let chores = choreRecords.compactMap { try? $0.toChore() }
        let activeFrom = state?.activeFrom ?? calendar.startOfDay(now)
        let live = HandoffPresentation.live(handoffRecords.compactMap { try? $0.toSnapshot() })
        return HandoffRules(
            scheduler: Scheduler(chores: chores, activeFrom: activeFrom, calendar: calendar),
            handoffs: live
        )
    }

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

    private func makeOffer(_ row: TodayRow) {
        pendingOffer = nil
        let now = Date()
        guard let mine = me, row.person == mine else { return }
        let offered = try? HandoffActions.offer(
            row.chore, from: mine, to: other, rules: rules(asOf: now), on: now, in: context
        )
        guard offered != nil else { return }
        answers += 1
        sync.syncSoon()
    }

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
