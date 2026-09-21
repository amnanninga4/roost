// The front door. Both people, side by side, compact enough to tick a chore from the kitchen.
// The streak card and week bar stay on the board segment.
//
// What is deliberately NOT here: the Anne-vs-Wes streak card and the week bar. They are a
// scoreboard, they cost ~200 pt at the top of the old screen, and the household already collapsed
// them by default. They live on the board segment now.
//
// Each section is its own extracted subview. This screen re-renders every 60 seconds under the
// same TimelineView the board uses, so a minute tick must not rebuild the whole body.
import RoostCore
import RoostDesign
import SwiftData
import SwiftUI

struct HomeScreen: View {
    var onOpenPerson: (Person) -> Void = { _ in }
    var onOpenMatchup: () -> Void = {}
    @State private var showsAll = false

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

    @Query(filter: #Predicate<ShoppingItemRecord> { !$0.removed })
    private var shoppingRecords: [ShoppingItemRecord]
    @Query(filter: #Predicate<MealRecord> { !$0.removed })
    private var mealRecords: [MealRecord]
    @Query(filter: #Predicate<ProjectRecord> { !$0.removed })
    private var projectRecords: [ProjectRecord]
    @Query(filter: #Predicate<WishlistItemRecord> { !$0.removed })
    private var wishlistRecords: [WishlistItemRecord]

    /// Counters, so a tap's feel is decided under a finger and never on a cold launch: each haptic
    /// fires on a change. They are this screen's own — `ChoreCheckOff` performs the write and reports
    /// what happened, and the board keeps its own set of these for its own frame.
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
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(asOf: context.date)
        }
        .background(RoostColor.Role.background.color)
        .refreshable { await sync.syncNow() }
        .roostHaptic(.checkOff, trigger: checkOffs)
        .roostHaptic(.undo, trigger: undos)
        .roostHaptic(.milestone, trigger: celebrations)
    }

    private func content(asOf now: Date) -> some View {
        let summary = summary(asOf: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: RoostSpacing.sectionGap) {
                Text(dateLine(now))
                    .roostType(.caption)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
                    .accessibilityIdentifier("dateEyebrow")

                HomeMatchupView(columns: summary.columns, onOpenPerson: onOpenPerson, onOpenMatchup: onOpenMatchup)
                choreList(summary)

                HomeDoorsView(doors: summary.doors) { id in
                    navigation.selected = .lists
                    UserDefaults.standard.set(id, forKey: ListPage.storageKey)
                }

                // Last, per the spec. The same line the board draws, from the same wiring, so the
                // screen the app opens on is not the one that stays quiet about being offline.
                SyncNoticeLine(notice: sync.notice(for: syncStates, now: now))
                    .accessibilityIdentifier("home.syncNotice")
            }
            .padding(.horizontal, RoostSpacing.screenMargin)
            .padding(.top, RoostSpacing.sm)
            .padding(.bottom, RoostSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func choreList(_ summary: HomeSummary) -> some View {
        let rows = summary.openRows
        return VStack(alignment: .leading, spacing: RoostSpacing.sm) {
            HStack {
                Text(Strings.Home.chores).roostType(.title)
                Spacer()
                Text(Strings.Home.left(rows.count)).roostType(.subheadline)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
            }
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                if rows.isEmpty {
                    Text(Strings.Home.allCaught)
                        .roostType(.body)
                        .padding(RoostSpacing.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array((showsAll ? rows : Array(rows.prefix(5))).enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider()
                    }
                    HomeChoreRow(row: row, date: summary.date) { toggle(row, among: summary.allRows) }
                }
                if rows.count > 5 {
                    Divider()
                    Button {
                        showsAll.toggle()
                    } label: {
                        HStack {
                            Text(showsAll ? Strings.Home.showLess : Strings.Home.showAll(rows.count))
                            Spacer()
                            Image(systemName: showsAll ? "chevron.up" : "chevron.down")
                        }
                        .roostType(.subheadline)
                        .frame(minHeight: RoostSpacing.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.roostPressQuiet)
                    .foregroundStyle(RoostColor.Role.accent.color)
                    .accessibilityIdentifier("home.showAll")
                }
            }
            .padding(.horizontal, RoostSpacing.cardPadding)
            .roostCard()
        }
    }

    private func dateLine(_ date: Date) -> String {
        date
            .formatted(.dateTime.weekday(.wide).month(.wide).day().locale(.autoupdatingCurrent))
    }

    /// Check off, or un-check, with the same meaning the board's rows have — one function, so the two
    /// screens cannot start disagreeing about what ticking a box does. `rows` is the list as it was
    /// drawn a moment ago, because the store's query has not caught up yet and the celebration rule is
    /// decided from what the finger saw.
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

    private func summary(asOf now: Date) -> HomeSummary {
        let chores = choreRecords.compactMap { try? $0.toChore() }
        let completions = completionRecords.compactMap { try? $0.toCompletion() }
        let activeFrom = state?.activeFrom ?? calendar.startOfDay(now)
        let plan = TodayPlanner.plan(
            chores: chores,
            completions: completions,
            handoffs: handoffRecords.compactMap { try? $0.toSnapshot() },
            asOf: now,
            activeFrom: activeFrom,
            calendar: calendar
        )
        return HomeSummary(
            plan: plan,
            me: me,
            doorCounts: .init(
                shopping: shoppingRecords.count,
                meals: mealRecords.count,
                projects: projectRecords.count,
                wishlist: wishlistRecords.count
            )
        )
    }
}
