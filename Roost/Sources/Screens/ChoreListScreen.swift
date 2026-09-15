// Gear → All chores: every active chore grouped by cadence, so the seed can be checked against
// data/chores.json by eye. Read-only; check-off lives on the Tasks tab.
import RoostCore
import RoostDesign
import SwiftData
import SwiftUI

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
        ScrollView {
            VStack(alignment: .leading, spacing: RoostSpacing.sectionGap) {
                header
                ForEach(grouped, id: \.cadence) { group in
                    VStack(alignment: .leading, spacing: RoostSpacing.sm) {
                        cadenceHeader(group.cadence, count: group.chores.count)
                        VStack(spacing: 0) {
                            ForEach(group.chores) { record in
                                ChoreListRow(record: record)
                            }
                        }
                        .padding(RoostSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .roostCard()
                    }
                }
            }
            .padding(.horizontal, RoostSpacing.screenMargin)
            .padding(.top, RoostSpacing.sm)
            .padding(.bottom, RoostSpacing.xxl)
        }
        .background(RoostColor.Role.background.color)
        .navigationTitle(Strings.Tasks.allChores)
        .toolbarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
            Text(Strings.Chores.eyebrow)
                .roostType(.monoLabel)
                .foregroundStyle(RoostColor.Role.accent.color)
            Text(Strings.Chores.seeded(records.count))
                .roostType(.displayLarge)
                .foregroundStyle(RoostColor.Role.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            if let version = syncStates.first?.choresVersion {
                Text(Strings.Chores.version(version))
                    .roostType(.footnote)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cadenceHeader(_ cadence: Cadence, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(cadence.label)
                .roostType(.title)
                .foregroundStyle(RoostColor.Role.textPrimary.color)
            Spacer(minLength: RoostSpacing.sm)
            Text(Strings.Chores.tasks(count))
                .roostType(.monoTally)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct ChoreListRow: View {
    let record: ChoreRecord

    @Environment(\.dynamicTypeSize) private var typeSize
    /// Grows with the text: at 40-pt type a fixed 8-pt gap makes two rows read as one wrapped sentence.
    @ScaledMetric(relativeTo: .body) private var rowPadding = RoostSpacing.sm

    private var category: RoostCategory {
        record.category == ChoreCategory.catCare.rawValue ? .catCare : .home
    }

    private var pinnedTo: Person? {
        record.fixedAssignee.flatMap(Person.init(rawValue:))
    }

    private var chore: Chore? { try? record.toChore() }
    private var windowLine: String? { chore.flatMap { WindowCopy.line($0) } }
    private var seasonLine: String? { chore?.season.flatMap { SeasonCopy.line($0) } }
    /// Window first, then season, joined when both exist (only mow-lawn has a season and it has no window).
    private var captionLine: String? {
        switch (windowLine, seasonLine) {
        case let (w?, s?): w + Strings.Lists.metaSeparator + s
        case let (w?, nil): w
        case let (nil, s?): s
        case (nil, nil): nil
        }
    }

    var body: some View {
        // One line normally. At accessibility sizes the badge and the pinned chip each take a fixed
        // 40-odd points off a column that is only 300 wide, which breaks "dishwasher" mid-word, so the
        // title gets the whole width and the chip goes under it.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: RoostSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: RoostSpacing.sm))
        var a11yValue = record.together ? Strings.Tasks.togetherValue : (pinnedTo.map { Strings.Tasks.always($0.displayName) } ?? "")
        if let captionLine {
            a11yValue = a11yValue.isEmpty ? captionLine : a11yValue + Strings.Lists.metaSeparator + captionLine
        }
        return layout {
            // The cat/house badge is a tint, not information — it is the first thing to go.
            if !typeSize.isAccessibilitySize {
                Image(systemName: category.symbol)
                    .roostType(.caption)
                    .foregroundStyle(category.color)
                    .padding(RoostSpacing.xs)
                    .background(category.softColor, in: RoostRadius.shape(RoostRadius.sm))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
                Text(record.title)
                    .roostType(.rowTitle)
                    .foregroundStyle(RoostColor.Role.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let captionLine {
                    Text(captionLine)
                        .roostType(.caption)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                }
            }
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: RoostSpacing.sm)
            }
            if record.together {
                chip(Strings.Tasks.together)
            } else if let person = pinnedTo {
                chip(person.displayName.uppercased())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, RoostSpacing.sm)
        .padding(.vertical, rowPadding)
        .frame(minHeight: RoostSpacing.minTapTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(record.title)
        .accessibilityValue(a11yValue)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .roostType(.monoLabel)
            .foregroundStyle(RoostColor.Role.assigned.color)
            .padding(.horizontal, RoostSpacing.sm)
            .padding(.vertical, RoostSpacing.xxs)
            .background(RoostColor.Role.assignedSoft.color, in: RoostRadius.shape(RoostRadius.sm))
            .fixedSize()
    }
}

extension Cadence {
    var label: String {
        switch self {
        case .daily: Strings.Chores.daily
        case .weekly: Strings.Chores.weekly
        case .biweekly: Strings.Chores.biweekly
        case .monthly: Strings.Chores.monthly
        case .bimonthly: Strings.Chores.bimonthly
        case .quarterly: Strings.Chores.quarterly
        }
    }
}

extension Person {
    var displayName: String {
        switch self {
        case .anne: Strings.People.anne
        case .wes: Strings.People.wes
        }
    }
}

#Preview {
    NavigationStack {
        ChoreListScreen().modelContainer(PreviewStore.container)
    }
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
            Chore(id: "garbage", title: "Garbage can to street, Sunday", cadence: .weekly, fixedAssignee: .wes,
                  category: .chore, weekdays: [7]),
            Chore(id: "take-out-garbage", title: "Take out garbage (kitchen)", cadence: .weekly, category: .chore,
                  weekdays: [5, 6]),
            Chore(id: "mow-lawn", title: "Mow lawn", cadence: .weekly, fixedAssignee: .anne, category: .chore,
                  season: Season(months: [4, 5, 6, 7, 8, 9, 10])),
            Chore(id: "change-litter", title: "Change litter", cadence: .monthly, category: .catCare, dueDay: 25),
            Chore(id: "pantry", title: "Clean out fridge and pantry", cadence: .quarterly, category: .chore,
                  together: true, dueDay: 28),
        ])
        try! ChoreSeeder.seed(sample, into: container.mainContext)
        return container
    }()
}
