// The one screen in R-2: every active chore grouped by cadence, proving the seed loaded.
// No check-off, no tabs, no streaks yet.
import SwiftUI
import SwiftData
import RoostCore
import RoostDesign

struct ChoreListScreen: View {
    @Query(filter: #Predicate<ChoreRecord> { !$0.retired }, sort: \ChoreRecord.sortOrder)
    private var records: [ChoreRecord]

    @Query private var syncStates: [SyncState]

    private var grouped: [(cadence: Cadence, chores: [ChoreRecord])] {
        Cadence.allCases.compactMap { cadence in
            let rows = records.filter { $0.cadence == cadence.rawValue }
            return rows.isEmpty ? nil : (cadence, rows)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 12, trailing: 20))
                }
                ForEach(grouped, id: \.cadence) { group in
                    Section {
                        ForEach(group.chores) { record in
                            ChoreRow(record: record)
                                .listRowBackground(RoostColor.surface)
                        }
                    } header: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(group.cadence.label)
                                .font(RoostFont.display(size: RoostFont.Size.sectionTitle, weight: .semibold))
                                .foregroundStyle(RoostColor.ink)
                            Spacer()
                            Text("\(group.chores.count) TASKS")
                                .font(RoostFont.mono(size: RoostFont.Size.eyebrow, weight: .semibold))
                                .kerning(1)
                                .foregroundStyle(RoostColor.inkSoft)
                        }
                        .textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(RoostColor.bg)
            .navigationTitle("Roost")
            .toolbarTitleDisplayMode(.inline)
        }
        .tint(RoostColor.accent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HOUSEHOLD TASKS")
                .font(RoostFont.mono(size: RoostFont.Size.eyebrow, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(RoostColor.accent)
            Text("\(records.count) chores seeded")
                .font(RoostFont.display(size: RoostFont.Size.title, weight: .bold))
                .foregroundStyle(RoostColor.ink)
            if let version = syncStates.first?.choresVersion {
                Text("list version \(version) · local store only")
                    .font(RoostFont.body(size: RoostFont.Size.meta))
                    .foregroundStyle(RoostColor.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChoreRow: View {
    let record: ChoreRecord

    private var isCatCare: Bool { record.category == ChoreCategory.catCare.rawValue }
    private var pinnedTo: Person? { record.fixedAssignee.flatMap(Person.init(rawValue:)) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCatCare ? "cat.fill" : "house.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isCatCare ? RoostColor.tease : RoostColor.accent)
                .frame(width: 30, height: 30)
                .background(isCatCare ? RoostColor.teaseSoft : RoostColor.accentSoft, in: RoundedRectangle(cornerRadius: 9))

            Text(record.title)
                .font(RoostFont.body(size: RoostFont.Size.body, weight: .semibold))
                .foregroundStyle(RoostColor.ink)

            Spacer(minLength: 8)

            if let person = pinnedTo {
                Text(person.displayName.uppercased())
                    .font(RoostFont.mono(size: RoostFont.Size.badge, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(RoostColor.assign)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoostColor.assignSoft, in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityLabel("Always \(person.displayName)")
            }
        }
        .padding(.vertical, 4)
    }
}

extension Cadence {
    var label: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .biweekly: "Biweekly"
        case .monthly: "Monthly"
        }
    }
}

extension Person {
    var displayName: String {
        switch self {
        case .anne: "Anne"
        case .wes: "Wes"
        }
    }
}

#Preview {
    ChoreListScreen().modelContainer(PreviewStore.container)
}

@MainActor
private enum PreviewStore {
    static let container: ModelContainer = {
        let container = try! ModelContainer(
            for: RoostSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let sample = ChoreList(version: 1, chores: [
            Chore(id: "scoop-litter", title: "Scoop litter", cadence: .daily, category: .catCare),
            Chore(id: "laundry", title: "Laundry", cadence: .weekly, fixedAssignee: .anne, category: .chore),
            Chore(id: "garbage", title: "Garbage can to street, Sunday", cadence: .weekly, fixedAssignee: .wes, category: .chore),
        ])
        try! ChoreSeeder.seed(sample, into: container.mainContext)
        return container
    }()
}
