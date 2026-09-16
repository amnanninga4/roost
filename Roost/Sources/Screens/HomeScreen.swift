// The front door. The date, one sentence, this phone's chores — checkable right here, so the
// standing-in-the-kitchen tick still happens on the first screen — the other person as a single
// line, and four doors into the rest of the house.
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
        .refreshable { await sync.syncNow() }
    }

    private func content(asOf now: Date) -> some View {
        let summary = summary(asOf: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: RoostSpacing.sectionGap) {
                VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
                    Text(dateLine(now))
                        .roostType(.monoLabel)
                        .foregroundStyle(RoostColor.Role.accent.color)
                        .accessibilityIdentifier("dateEyebrow")
                    Text(summary.sentence)
                        .roostType(.displayLarge)
                        .foregroundStyle(RoostColor.Role.textPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("home.sentence")
                }

                HomeRowsView(rows: summary.myRows)

                if summary.showsOtherLine {
                    Button {
                        navigation.showBoard()
                    } label: {
                        HStack {
                            Text(Strings.Home.otherStillHas(summary.otherCount, other: summary.otherName))
                                .roostType(.rowTitle)
                                .foregroundStyle(RoostColor.Role.textPrimary.color)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(RoostColor.Role.textSecondary.color)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.roostPressQuiet)
                    .accessibilityIdentifier("home.otherLine")
                }

                HomeDoorsView(doors: summary.doors) { id in
                    navigation.selected = .lists
                    UserDefaults.standard.set(id, forKey: ListPage.storageKey)
                }
            }
            .padding(.horizontal, RoostSpacing.screenMargin)
            .padding(.top, RoostSpacing.sm)
            .padding(.bottom, RoostSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func dateLine(_ date: Date) -> String {
        date
            .formatted(.dateTime.weekday(.wide).month(.wide).day().locale(.autoupdatingCurrent))
            .uppercased()
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
