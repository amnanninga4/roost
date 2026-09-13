// Root screen: what each person owes today, with check-off, escalation color, and the weekly tally.
import SwiftUI
import SwiftData
import RoostCore
import RoostDesign

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
    @State private var now = Date()

    private let calendar = HouseholdCalendar()

    private var state: SyncState? { syncStates.first }
    private var me: Person? { state?.person.flatMap(Person.init(rawValue:)) }

    private var plan: TodayPlan {
        let chores = choreRecords.compactMap { try? $0.toChore() }
        let completions = completionRecords.compactMap { try? $0.toCompletion() }
        let activeFrom = state?.activeFrom ?? calendar.startOfDay(now)
        return TodayPlanner.plan(chores: chores, completions: completions, asOf: now, activeFrom: activeFrom, calendar: calendar)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
                }
                let plan = self.plan
                ForEach(Person.allCases, id: \.self) { person in
                    Section {
                        let rows = plan.rows(for: person)
                        if rows.isEmpty {
                            Text("Nothing due. Nice.")
                                .font(RoostFont.body(size: RoostFont.Size.meta))
                                .foregroundStyle(RoostColor.inkSoft)
                                .listRowBackground(RoostColor.surface)
                        }
                        ForEach(rows) { row in
                            TodayRowView(row: row) { toggle(row) }
                                .listRowBackground(RoostColor.surface)
                        }
                    } header: {
                        personHeader(person, plan: plan)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(RoostColor.bg)
            .navigationTitle("Roost")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(Strings.Kitchen.menuEntry) { showKitchen = true }
                        NavigationLink("All chores") { ChoreListScreen() }
                        Button(Strings.Settings.title) { showSettings = true }
                        Button("Sync now") { sync.syncSoon() }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsScreen() }
            .fullScreenCover(isPresented: $showKitchen) { KitchenScreen() }
        }
        .tint(RoostColor.accent)
        .task {
            ensureActiveFrom()
            await sync.syncNow()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                now = Date()
                sync.syncSoon()
            }
        }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(.autoupdatingCurrent)).uppercased())
                .font(RoostFont.mono(size: RoostFont.Size.eyebrow, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(RoostColor.accent)
            Text("Today")
                .font(RoostFont.display(size: RoostFont.Size.title, weight: .bold))
                .foregroundStyle(RoostColor.ink)
            StreakHeaderView(model: StreakHeaderModel(plan: plan))
                .padding(.top, 6)
            Text(sync.statusLine)
                .font(RoostFont.body(size: RoostFont.Size.caption))
                .foregroundStyle(RoostColor.inkSoft)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func personHeader(_ person: Person, plan: TodayPlan) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(person.displayName)
                .font(RoostFont.display(size: RoostFont.Size.sectionTitle, weight: .semibold))
                .foregroundStyle(RoostColor.ink)
            if person == me {
                Text("YOU")
                    .font(RoostFont.mono(size: RoostFont.Size.badge, weight: .semibold))
                    .foregroundStyle(RoostColor.accent)
            }
            Spacer()
            Text("\(plan.dueCount(for: person)) DUE")
                .font(RoostFont.mono(size: RoostFont.Size.eyebrow, weight: .semibold))
                .kerning(1)
                .foregroundStyle(RoostColor.inkSoft)
        }
        .textCase(nil)
    }

    // MARK: actions

    private func toggle(_ row: TodayRow) {
        switch row.kind {
        case .due:
            let record = CompletionRecord(id: UUID().uuidString, choreId: row.chore.id, person: row.person.rawValue, completedAt: Date())
            context.insert(record)
        case .done(let completionId):
            if let record = completionRecords.first(where: { $0.id == completionId }) {
                record.removed = true
                if record.syncedAt == nil && !record.rejected {
                    record.deleteSynced = true // never reached the server; nothing to replay
                }
            }
        }
        try? context.save()
        now = Date()
        sync.syncSoon()
    }

    /// The household start date, fixed the first time the screen renders (or the earliest completion, if any).
    private func ensureActiveFrom() {
        guard let state, state.activeFrom == nil else { return }
        let earliest = completionRecords.map(\.completedAt).min() ?? now
        state.activeFrom = calendar.startOfDay(min(earliest, now))
        try? context.save()
    }
}

private struct TodayRowView: View {
    let row: TodayRow
    let onToggle: () -> Void

    private var isCatCare: Bool { row.chore.category == .catCare }

    private var stageColor: Color {
        switch row.stage {
        case .dueToday: return RoostColor.ink
        case .nudge: return RoostColor.gold
        case .pointed: return RoostColor.tease
        case .alert: return RoostColor.alert
        }
    }

    private var stageSoft: Color {
        switch row.stage {
        case .dueToday: return RoostColor.surface2
        case .nudge: return RoostColor.goldSoft
        case .pointed: return RoostColor.teaseSoft
        case .alert: return RoostColor.alertSoft
        }
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: row.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(row.isDone ? RoostColor.accent : RoostColor.line)

                Image(systemName: isCatCare ? "cat.fill" : "house.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isCatCare ? RoostColor.tease : RoostColor.accent)
                    .frame(width: 26, height: 26)
                    .background(isCatCare ? RoostColor.teaseSoft : RoostColor.accentSoft, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.chore.title)
                        .font(RoostFont.body(size: RoostFont.Size.body, weight: .semibold))
                        .foregroundStyle(row.isDone ? RoostColor.inkSoft : stageColor)
                        .strikethrough(row.isDone, color: RoostColor.inkSoft)
                    if let subtitle = EscalationCopy.subtitle(for: row) {
                        Text(subtitle)
                            .font(RoostFont.body(size: RoostFont.Size.caption))
                            .foregroundStyle(stageColor)
                    }
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                if row.daysOverdue > 0 {
                    Text("\(row.daysOverdue)D LATE")
                        .font(RoostFont.mono(size: RoostFont.Size.badge, weight: .bold))
                        .kerning(0.4)
                        .foregroundStyle(stageColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(stageSoft, in: RoundedRectangle(cornerRadius: 5))
                }

                if let pinned = row.chore.fixedAssignee {
                    Text(pinned.displayName.uppercased())
                        .font(RoostFont.mono(size: RoostFont.Size.badge, weight: .semibold))
                        .kerning(0.5)
                        .foregroundStyle(RoostColor.assign)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(RoostColor.assignSoft, in: RoundedRectangle(cornerRadius: 5))
                        .accessibilityLabel("Always \(pinned.displayName)")
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.isDone ? "Undo \(row.chore.title)" : "Mark \(row.chore.title) done")
    }
}
