import RoostCore
import RoostDesign
import SwiftData
import SwiftUI

struct MatchupScreen: View {
    var onOpenPerson: (Person) -> Void = { _ in }

    @Query private var chores: [ChoreRecord]
    @Query(filter: #Predicate<CompletionRecord> { !$0.removed }) private var completions: [CompletionRecord]
    @Query(filter: #Predicate<HandoffRecord> { !$0.removed }) private var handoffs: [HandoffRecord]
    @Query private var states: [SyncState]
    @Environment(\.dynamicTypeSize) private var typeSize
    private let calendar = HouseholdCalendar()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            let summary = MatchupSummary(
                chores: chores, completions: completions,
                handoffs: handoffs.compactMap { try? $0.toSnapshot() }, asOf: now,
                activeFrom: states.first?.activeFrom ?? calendar.startOfDay(now), calendar: calendar
            )
            let week = calendar.weekBounds(containing: now)
            ScrollView {
                VStack(alignment: .leading, spacing: RoostSpacing.sectionGap) {
                    Text(Strings.Matchup.week(start: week.start, end: calendar.adding(days: -1, to: week.end)))
                        .roostType(.headline)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                    scoreboard(summary.plan)
                    Text(Strings.Matchup.recent)
                        .roostType(.title)
                        .accessibilityAddTraits(.isHeader)
                    activity(summary.recent)
                }
                .padding(.horizontal, RoostSpacing.screenMargin)
                .padding(.vertical, RoostSpacing.md)
                .padding(.bottom, RoostSpacing.xxl)
            }
        }
        .background(RoostColor.Role.background.color)
        .foregroundStyle(RoostColor.Role.textPrimary.color)
        .navigationTitle(Strings.Matchup.title)
        .toolbarTitleDisplayMode(.inline)
    }

    private func scoreboard(_ plan: TodayPlan) -> some View {
        VStack(spacing: RoostSpacing.md) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: RoostSpacing.md))
                : AnyLayout(HStackLayout(alignment: .top, spacing: RoostSpacing.md))
            layout {
                person(.anne, plan: plan)
                person(.wes, plan: plan)
            }
            Text(Strings.Matchup.completed)
                .roostType(.callout)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
            Divider()
            comparison(Strings.Matchup.left,
                       anne: String(plan.dueCount(for: .anne)), wes: String(plan.dueCount(for: .wes)))
            Divider()
            comparison(Strings.Matchup.streak,
                       anne: Strings.Matchup.days(plan.streak[.anne, default: 0]),
                       wes: Strings.Matchup.days(plan.streak[.wes, default: 0]))
            Divider()
            Text(Strings.Matchup.streakHint)
                .roostType(.caption)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(RoostSpacing.md)
        .roostCard()
    }

    private func person(_ person: Person, plan: TodayPlan) -> some View {
        Button { onOpenPerson(person) } label: {
            VStack(spacing: RoostSpacing.sm) {
                HStack {
                    HouseholdAvatar(person: person)
                    Text(person.displayName).roostType(.headline)
                    Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
                }
                Text(String(plan.doneThisWeek[person, default: 0]))
                    .roostType(.displayLarge).monospacedDigit()
            }
            .frame(maxWidth: .infinity, minHeight: RoostSpacing.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.roostPressQuiet)
        .accessibilityLabel(person.displayName)
        .accessibilityValue(Strings.Matchup.weekDone(plan.doneThisWeek[person, default: 0]))
        .accessibilityHint(Strings.Home.openPerson)
        .accessibilityIdentifier("matchup.open.\(person.rawValue)")
    }

    @ViewBuilder
    private func comparison(_ title: String, anne: String, wes: String) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: RoostSpacing.sm) {
                Text(title).roostType(.headline)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
                LabeledContent(Person.anne.displayName, value: anne)
                LabeledContent(Person.wes.displayName, value: wes)
            }
            .roostType(.body)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: RoostSpacing.sm) {
                Text(anne).roostType(.title).monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Person.anne.displayName).accessibilityValue(anne)
                Text(title).roostType(.caption)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
                    .frame(maxWidth: .infinity)
                Text(wes).roostType(.title).monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Person.wes.displayName).accessibilityValue(wes)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func activity(_ items: [MatchupSummary.Activity]) -> some View {
        VStack(alignment: .leading, spacing: RoostSpacing.md) {
            if items.isEmpty {
                Text(Strings.Matchup.empty).roostType(.body)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider()
                }
                HStack(alignment: .top, spacing: RoostSpacing.sm) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(RoostColor.Role.textSecondary.color).accessibilityHidden(true)
                    RoostAvatar(person: item.person.design).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
                        Text(item.title).roostType(.rowTitle)
                        Text(Strings.Matchup.activity(person: item.person.displayName, date: item.completedAt))
                            .roostType(.caption).foregroundStyle(RoostColor.Role.textSecondary.color)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("matchup.activity.\(item.id)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RoostSpacing.md)
        .roostCard()
    }
}
