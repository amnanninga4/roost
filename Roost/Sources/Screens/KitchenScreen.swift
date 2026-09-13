import RoostCore
import RoostDesign
import SwiftData

// Kitchen mode: the phone propped on the counter. Both people at once, big type, no chrome, screen stays on.
// Read-only; check-off stays on the Tasks tab. Tap anywhere, or Close, to leave.
//
// Refreshes three ways: the @Query rows re-render on any store change (a check-off on the other phone lands
// through sync), the coordinator's last sync is observed for the bottom line, and a 60-second timeline
// moves the date, the days-late counts, and the "Synced …" wording without a store change.
//
// D-6 moved this screen onto the design system, which it had been the last holdout from. Three things came
// out of that, all of them things the accessibility audit was failing on:
//
//   - Type is `RoostType` rungs rather than `RoostFont.<face>(size:)`, so every line here follows the
//     reader's text size. The one literal size left is the due count, which is the point of the screen —
//     a number you can read from the other side of the kitchen — and it scales through `@ScaledMetric`
//     with a ceiling so the largest accessibility size cannot push the two columns off the screen.
//   - A card's colour is now its fill and its border; the words on it are `textPrimary` and
//     `textSecondary`. The old version set the title and the badge in the stage's own colour, and in this
//     palette that is 2.1:1 for the nudge stage against its own soft partner — the one contrast finding on
//     this screen that no amount of squinting excused.
//   - The stage's colour comes from `EscalationStage.role` / `.fillRole` (Tasks/TaskStyle.swift) instead of
//     a second private mapping here, which is what the old comment already claimed. A chore now looks the
//     same on the counter as it does on the phone, because there is one table.
//
// Close holds 44 pt: its padding is inside the button's label, not wrapped around the button, which is the
// difference between a 44-pt target and a 30-pt one that merely looks like a 44-pt one.
import SwiftUI
import UIKit

struct KitchenScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var sync

    @Query(filter: #Predicate<ChoreRecord> { !$0.retired }, sort: \ChoreRecord.sortOrder)
    private var choreRecords: [ChoreRecord]
    @Query(filter: #Predicate<CompletionRecord> { !$0.removed })
    private var completionRecords: [CompletionRecord]
    @Query(filter: #Predicate<HandoffRecord> { !$0.removed }, sort: \HandoffRecord.createdAt)
    private var handoffRecords: [HandoffRecord]
    @Query private var syncStates: [SyncState]

    /// What the idle timer was before this screen disabled it, put back on dismiss.
    @State private var idleTimerWasDisabled = false
    /// The due count's point size at the reader's text size. 52 at the default, which is the size the
    /// counter was drawn at before it scaled at all.
    @ScaledMetric(relativeTo: .largeTitle) private var scaledCount: CGFloat = 52

    private let calendar = HouseholdCalendar()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(asOf: context.date)
        }
        .background(RoostColor.Role.background.color.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .onAppear {
            idleTimerWasDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = idleTimerWasDisabled
        }
    }

    private func content(asOf now: Date) -> some View {
        let model = KitchenModel(chores: choreRecords, completions: completionRecords,
                                 handoffs: handoffRecords,
                                 activeFrom: syncStates.first?.activeFrom, asOf: now, calendar: calendar)
        return ScrollView {
            VStack(alignment: .leading, spacing: RoostSpacing.xl) {
                topBar(now: now)
                if !model.alerts.isEmpty {
                    AlertBanner(items: model.alerts)
                }
                columns(model)
                if model.isCaughtUp {
                    Text(Strings.Kitchen.caughtUp)
                        .roostType(.display)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                        .frame(maxWidth: .infinity)
                        .padding(.top, RoostSpacing.xxl)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .padding(.horizontal, RoostSpacing.screenMargin)
            .padding(.top, RoostSpacing.sm)
            // Room for the "Synced …" pill below the last card rather than over it.
            .padding(.bottom, RoostSpacing.xxxl + RoostSpacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .overlay(alignment: .bottom) {
            Text(KitchenModel.syncedLine(lastSyncAt: sync.lastSyncAt, now: now))
                .roostType(.monoTally)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
                .padding(.horizontal, RoostSpacing.md)
                .padding(.vertical, RoostSpacing.sm)
                .background(RoostColor.Role.background.color, in: RoostRadius.pillShape)
                .padding(.bottom, RoostSpacing.sm)
                .allowsHitTesting(false)
        }
    }

    // MARK: pieces

    private func topBar(now: Date) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(.autoupdatingCurrent)).uppercased())
                .roostType(.monoLabel)
                .foregroundStyle(RoostColor.Role.accent.color)
                // The same identifier the Tasks tab's date line carries, for the same reason: its label is
                // today's date. See Roost/UITests/AccessibilityAuditTests.swift.
                .accessibilityIdentifier("dateEyebrow")
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: RoostSpacing.sm)
            closeButton
        }
    }

    /// The one control on the screen. The padding and the 44 pt live on the label, so the target is the
    /// whole pill rather than the two words inside it.
    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Text(Strings.Kitchen.close)
                .roostType(.monoLabel)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
                .padding(.horizontal, RoostSpacing.md)
                .frame(minHeight: RoostSpacing.minTapTarget)
                .background(RoostColor.Role.surfaceElevated.color, in: RoostRadius.pillShape)
                .overlay(RoostRadius.pillShape.stroke(RoostColor.Role.separator.color, lineWidth: 1))
                .contentShape(RoostRadius.pillShape)
        }
        .buttonStyle(.plain)
    }

    private func columns(_ model: KitchenModel) -> some View {
        HStack(alignment: .top, spacing: RoostSpacing.md) {
            ForEach(model.columns, id: \.person) { column in
                VStack(alignment: .leading, spacing: RoostSpacing.md) {
                    columnHead(column)
                    if column.overdue.isEmpty {
                        if !model.isCaughtUp {
                            Text(Strings.Kitchen.columnClear)
                                .roostType(.callout)
                                .foregroundStyle(RoostColor.Role.textSecondary.color)
                        }
                    } else {
                        ForEach(column.overdue) { item in
                            OverdueCard(item: item)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func columnHead(_ column: KitchenModel.Column) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(column.person.displayName)
                .roostType(.display)
                .foregroundStyle(RoostColor.Role.textPrimary.color)
            Text("\(column.dueCount)")
                .font(RoostFont.mono(size: countSize, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(RoostColor.Role.textPrimary.color)
                .padding(.top, RoostSpacing.xxs)
            Text(Strings.Kitchen.dueTodayLabel)
                .roostType(.monoLabel)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(column.person.displayName), \(Strings.Kitchen.dueToday(column.dueCount))")
    }

    /// The due count, the one number on the screen that is meant to be read from a distance. It grows with
    /// the reader's text size and stops at `Self.countCeiling`, past which two three-digit columns would
    /// not fit side by side on any phone.
    private var countSize: CGFloat {
        min(scaledCount, Self.countCeiling)
    }

    private static let countCeiling: CGFloat = 76
}

/// The shared shout: every alert-stage chore from either person, named, until it is done.
private struct AlertBanner: View {
    let items: [KitchenModel.Item]

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.md) {
            Label {
                Text(Strings.Kitchen.alertHeading)
                    .roostType(.monoLabel)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .roostType(.caption)
            }
            .foregroundStyle(RoostColor.Role.danger.color)
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
                    // The shout is the size of the type and the red around it; the words themselves are
                    // ink, because `danger` on `dangerSoft` is 3.6:1 and this is the line that matters most.
                    Text(item.copy)
                        .roostType(.display)
                        .foregroundStyle(RoostColor.Role.textPrimary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(item.person.displayName.uppercased()) · \(Strings.Kitchen.daysLate(item.daysOverdue))")
                        .roostType(.monoTally)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RoostSpacing.lg)
        .background(RoostColor.Role.dangerSoft.color, in: RoostRadius.cardShape)
        .overlay(RoostRadius.cardShape.stroke(RoostColor.Role.danger.color, lineWidth: 2))
    }
}

/// One overdue chore in a person's column: how late it is, the chore, and the escalation line.
///
/// The stage is the card — its fill and its border — and the words on it are ink. That is the other way
/// round from the first version of this screen, which set the title and the badge in the stage's own
/// colour; in this palette that reads at 2.1:1 for a nudge and 3.6:1 for an alert, and a counter display
/// is read from further away than anything else in the app, not closer.
private struct OverdueCard: View {
    let item: KitchenModel.Item

    /// The stage's fill, from `Tasks/TaskStyle.swift`. `dueToday` never reaches this card — the column
    /// only lists what is overdue — but the inset panel is the right answer if it ever does.
    private var fill: Color {
        (item.stage.fillRole ?? .surfaceElevated).color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.xs) {
            Text(Strings.Kitchen.daysLate(item.daysOverdue))
                .roostType(.monoLabel)
                .foregroundStyle(RoostColor.Role.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.chore.title)
                .roostType(.title)
                .foregroundStyle(RoostColor.Role.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.copy)
                .roostType(.subheadline)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
            // The same chip the Tasks tab puts on a row somebody handed over: an overdue chore on the
            // counter should say whose turn it actually was this period.
            if let giver = item.handedOverBy {
                Text(Strings.Handoffs.from(giver.displayName))
                    .roostType(.monoLabel)
                    .foregroundStyle(RoostColor.Role.textPrimary.color)
                    .padding(.horizontal, RoostSpacing.sm)
                    .padding(.vertical, RoostSpacing.xxs)
                    .background(RoostColor.Role.accentSoft.color, in: RoostRadius.pillShape)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RoostSpacing.md)
        .background(fill, in: RoostRadius.rowShape)
        .overlay(
            RoostRadius.rowShape
                .stroke(item.stage.role.color, lineWidth: item.stage == .alert ? 2 : 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - previews

#Preview("Overdue, one alert each") {
    KitchenScreen()
        .modelContainer(KitchenPreview.container)
        .environment(KitchenPreview.sync)
}

#Preview("Caught up") {
    KitchenScreen()
        .modelContainer(KitchenPreview.freshContainer)
        .environment(KitchenPreview.freshSync)
}

@MainActor
private enum KitchenPreview {
    static let cal = HouseholdCalendar()

    /// Household started six days ago: Anne owes a nudge and a pointed, Wes an alert and a nudge.
    static let container: ModelContainer = {
        let container = try! ModelContainer(
            for: RoostSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let list = ChoreList(version: 1, chores: [
            Chore(id: "scoop-litter", title: "Scoop litter", cadence: .daily, fixedAssignee: .wes, category: .catCare),
            Chore(id: "water-plants", title: "Water plants", cadence: .daily, fixedAssignee: .wes, category: .chore),
            Chore(
                id: "wipe-tables",
                title: "Wipe down tables",
                cadence: .daily,
                fixedAssignee: .anne,
                category: .chore
            ),
            Chore(
                id: "refill-cat-water",
                title: "Refill cat water",
                cadence: .daily,
                fixedAssignee: .anne,
                category: .catCare
            ),
            Chore(id: "laundry", title: "Laundry", cadence: .weekly, fixedAssignee: .anne, category: .chore),
        ])
        try! ChoreSeeder.seed(list, into: ctx)
        let start = cal.startOfDay(cal.adding(days: -6, to: Date()))
        try! ChoreSeeder.syncState(in: ctx).activeFrom = start
        ctx.insert(CompletionRecord(
            id: "p1",
            choreId: "water-plants",
            person: "wes",
            completedAt: cal.adding(days: 4, to: start)
        ))
        ctx.insert(CompletionRecord(
            id: "p2",
            choreId: "wipe-tables",
            person: "anne",
            completedAt: cal.adding(days: 2, to: start)
        ))
        ctx.insert(CompletionRecord(
            id: "p3",
            choreId: "refill-cat-water",
            person: "anne",
            completedAt: cal.adding(days: 4, to: start)
        ))
        try! ctx.save()
        return container
    }()

    static let sync = SyncCoordinator(container: container)

    static let freshContainer: ModelContainer = {
        let container = try! ModelContainer(
            for: RoostSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        try! ChoreSeeder.seedIfNeeded(into: container.mainContext, from: ChoreSeeder.bundledChoresURL())
        return container
    }()

    static let freshSync = SyncCoordinator(container: freshContainer)
}
