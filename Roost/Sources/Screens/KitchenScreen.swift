// Kitchen mode: the phone propped on the counter. Both people at once, big type, no chrome, screen stays on.
// Read-only; check-off stays on the Tasks tab. Tap anywhere, or Close, to leave.
//
// Refreshes three ways: the @Query rows re-render on any store change (a check-off on the other phone lands
// through sync), the coordinator's last sync is observed for the bottom line, and a 60-second timeline
// moves the date, the days-late counts, and the "Synced …" wording without a store change.
import SwiftUI
import SwiftData
import UIKit
import RoostCore
import RoostDesign

struct KitchenScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var sync

    @Query(filter: #Predicate<ChoreRecord> { !$0.retired }, sort: \ChoreRecord.sortOrder)
    private var choreRecords: [ChoreRecord]
    @Query(filter: #Predicate<CompletionRecord> { !$0.removed })
    private var completionRecords: [CompletionRecord]
    @Query private var syncStates: [SyncState]

    /// What the idle timer was before this screen disabled it, put back on dismiss.
    @State private var idleTimerWasDisabled = false

    private let calendar = HouseholdCalendar()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(asOf: context.date)
        }
        .background(RoostColor.bg.ignoresSafeArea())
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
                                 activeFrom: syncStates.first?.activeFrom, asOf: now, calendar: calendar)
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                topBar(now: now)
                if !model.alerts.isEmpty {
                    AlertBanner(items: model.alerts)
                }
                columns(model)
                if model.isCaughtUp {
                    Text(Strings.Kitchen.caughtUp)
                        .font(RoostFont.display(size: RoostFont.Size.title, weight: .semibold))
                        .foregroundStyle(RoostColor.inkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 36)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 72)
        }
        .scrollBounceBehavior(.basedOnSize)
        .overlay(alignment: .bottom) {
            Text(KitchenModel.syncedLine(lastSyncAt: sync.lastSyncAt, now: now))
                .font(RoostFont.mono(size: RoostFont.Size.caption, weight: .medium))
                .foregroundStyle(RoostColor.inkSoft)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(RoostColor.bg.opacity(0.92), in: Capsule())
                .padding(.bottom, 10)
                .allowsHitTesting(false)
        }
    }

    // MARK: pieces

    private func topBar(now: Date) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(.autoupdatingCurrent)).uppercased())
                .font(RoostFont.mono(size: 15, weight: .semibold))
                .kerning(1.4)
                .foregroundStyle(RoostColor.accent)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(Strings.Kitchen.close) { dismiss() }
                .font(RoostFont.mono(size: RoostFont.Size.meta, weight: .semibold))
                .foregroundStyle(RoostColor.inkSoft)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoostColor.surface2, in: Capsule())
                .overlay(Capsule().stroke(RoostColor.line, lineWidth: 1))
                .buttonStyle(.plain)
        }
    }

    private func columns(_ model: KitchenModel) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(model.columns, id: \.person) { column in
                VStack(alignment: .leading, spacing: 12) {
                    columnHead(column)
                    if column.overdue.isEmpty {
                        if !model.isCaughtUp {
                            Text(Strings.Kitchen.columnClear)
                                .font(RoostFont.body(size: RoostFont.Size.body))
                                .foregroundStyle(RoostColor.inkSoft)
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
                .font(RoostFont.display(size: RoostFont.Size.title, weight: .bold))
                .foregroundStyle(RoostColor.ink)
            Text("\(column.dueCount)")
                .font(RoostFont.mono(size: 52, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(RoostColor.ink)
                .padding(.top, 2)
            Text(Strings.Kitchen.dueTodayLabel)
                .font(RoostFont.mono(size: RoostFont.Size.eyebrow, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(RoostColor.inkSoft)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(column.person.displayName), \(Strings.Kitchen.dueToday(column.dueCount))")
    }
}

/// The shared shout: every alert-stage chore from either person, named, until it is done.
private struct AlertBanner: View {
    let items: [KitchenModel.Item]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(Strings.Kitchen.alertHeading)
                    .font(RoostFont.mono(size: RoostFont.Size.eyebrow, weight: .semibold))
                    .kerning(1.2)
            }
            .foregroundStyle(RoostColor.alert)
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.copy)
                        .font(RoostFont.display(size: 26, weight: .bold))
                        .foregroundStyle(RoostColor.alert)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(item.person.displayName.uppercased()) · \(Strings.Kitchen.daysLate(item.daysOverdue))")
                        .font(RoostFont.mono(size: RoostFont.Size.caption, weight: .semibold))
                        .kerning(0.8)
                        .foregroundStyle(RoostColor.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoostColor.alertSoft, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(RoostColor.alert, lineWidth: 2))
    }
}

/// One overdue chore in a person's column: stage label, title, and the escalation line, in the stage's color.
private struct OverdueCard: View {
    let item: KitchenModel.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(Strings.Kitchen.daysLate(item.daysOverdue))
                .font(RoostFont.mono(size: RoostFont.Size.badge, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(item.stage.tint)
            Text(item.chore.title)
                .font(RoostFont.display(size: RoostFont.Size.sectionTitle, weight: .bold))
                .foregroundStyle(item.stage.tint)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.copy)
                .font(RoostFont.body(size: RoostFont.Size.meta))
                .foregroundStyle(RoostColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(item.stage.softTint, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(item.stage.tint, lineWidth: item.stage == .alert ? 2 : 1))
        .accessibilityElement(children: .combine)
    }
}

/// The Tasks tab's stage colors (TodayRowView), so a chore looks the same on the counter as on the phone.
private extension EscalationStage {
    var tint: Color {
        switch self {
        case .dueToday: RoostColor.ink
        case .nudge: RoostColor.gold
        case .pointed: RoostColor.tease
        case .alert: RoostColor.alert
        }
    }

    var softTint: Color {
        switch self {
        case .dueToday: RoostColor.surface2
        case .nudge: RoostColor.goldSoft
        case .pointed: RoostColor.teaseSoft
        case .alert: RoostColor.alertSoft
        }
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
        let container = try! ModelContainer(for: RoostSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        let list = ChoreList(version: 1, chores: [
            Chore(id: "scoop-litter", title: "Scoop litter", cadence: .daily, fixedAssignee: .wes, category: .catCare),
            Chore(id: "water-plants", title: "Water plants", cadence: .daily, fixedAssignee: .wes, category: .chore),
            Chore(id: "wipe-tables", title: "Wipe down tables", cadence: .daily, fixedAssignee: .anne, category: .chore),
            Chore(id: "refill-cat-water", title: "Refill cat water", cadence: .daily, fixedAssignee: .anne, category: .catCare),
            Chore(id: "laundry", title: "Laundry", cadence: .weekly, fixedAssignee: .anne, category: .chore),
        ])
        try! ChoreSeeder.seed(list, into: ctx)
        let start = cal.startOfDay(cal.adding(days: -6, to: Date()))
        try! ChoreSeeder.syncState(in: ctx).activeFrom = start
        ctx.insert(CompletionRecord(id: "p1", choreId: "water-plants", person: "wes", completedAt: cal.adding(days: 4, to: start)))
        ctx.insert(CompletionRecord(id: "p2", choreId: "wipe-tables", person: "anne", completedAt: cal.adding(days: 2, to: start)))
        ctx.insert(CompletionRecord(id: "p3", choreId: "refill-cat-water", person: "anne", completedAt: cal.adding(days: 4, to: start)))
        try! ctx.save()
        return container
    }()
    static let sync = SyncCoordinator(container: container)

    static let freshContainer: ModelContainer = {
        let container = try! ModelContainer(for: RoostSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        try! ChoreSeeder.seedIfNeeded(into: container.mainContext, from: ChoreSeeder.bundledChoresURL())
        return container
    }()
    static let freshSync = SyncCoordinator(container: freshContainer)
}
