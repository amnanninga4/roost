// Meals tab: the bank of ideas. Add a title and an optional tag, mark one NEXT UP (swipe or long press),
// note "Made it today", swipe to delete. Writes go to the store first, then kick a sync.
import RoostCore
import RoostDesign
import SwiftData
import SwiftUI

struct MealsScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    @Query(filter: #Predicate<MealRecord> { !$0.removed }, sort: \MealRecord.createdAt, order: .reverse)
    private var meals: [MealRecord]

    @State private var title = ""
    @State private var tag = ""
    @FocusState private var titleFocused: Bool

    /// The next-up meal first, then newest ideas first.
    private var ordered: [MealRecord] {
        meals.filter(\.nextUp) + meals.filter { !$0.nextUp }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ListScreenHeader(title: Strings.Tabs.meals, line: Strings.Meals.header(count: meals.count))
                        .listHeaderRow()
                }
                Section {
                    AddRow(placeholder: Strings.Meals.add, text: $title, focused: $titleFocused, onSubmit: add) {
                        if !title.isEmpty {
                            TextField(Strings.Meals.tag, text: $tag)
                                .font(RoostFont.body(size: RoostFont.Size.caption, weight: .semibold))
                                .foregroundStyle(RoostColor.inkSoft)
                                .submitLabel(.done)
                                .onSubmit(add)
                                .padding(.leading, 32)
                        }
                    }
                }
                Section {
                    if meals.isEmpty {
                        EmptyLine(text: Strings.Meals.empty)
                    }
                    ForEach(ordered) { meal in
                        MealRow(meal: meal)
                            .listRowBackground(RoostColor.surface)
                            .swipeActions(edge: .leading) {
                                Button { setNextUp(meal, !meal.nextUp) } label: {
                                    Label(
                                        meal.nextUp ? Strings.Meals.clearNextUp : Strings.Meals.nextUp,
                                        systemImage: "flame"
                                    )
                                }
                                .tint(RoostColor.meal)
                            }
                            .swipeToDelete { remove(meal) }
                            .contextMenu {
                                Button { setNextUp(meal, !meal.nextUp) } label: {
                                    Label(
                                        meal.nextUp ? Strings.Meals.clearNextUp : Strings.Meals.nextUp,
                                        systemImage: "flame"
                                    )
                                }
                                Button { madeToday(meal) } label: {
                                    Label(Strings.Meals.madeToday, systemImage: "checkmark.circle")
                                }
                                Button(role: .destructive) { remove(meal) } label: {
                                    Label(Strings.Lists.delete, systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .listTabChrome()
            .animation(.default, value: ordered.map(\.id))
        }
        .tint(RoostColor.accent)
    }

    // MARK: actions

    private func add() {
        defer { refocus($titleFocused) }
        guard (try? ListActions.addMeal(title, tag: tag, in: context)) != nil else { return }
        title = ""
        tag = ""
        sync.syncSoon()
    }

    private func setNextUp(_ meal: MealRecord, _ isOn: Bool) {
        try? ListActions.setNextUp(meal, isOn, in: context)
        sync.syncSoon()
    }

    private func madeToday(_ meal: MealRecord) {
        try? ListActions.madeToday(meal, in: context)
        sync.syncSoon()
    }

    private func remove(_ meal: MealRecord) {
        try? ListActions.removeMeal(meal, in: context)
        sync.syncSoon()
    }
}

private struct MealRow: View {
    let meal: MealRecord

    /// "Weeknight · last made Jul 20"; nil when there is nothing to say.
    private var meta: String? {
        var parts: [String] = []
        if !meal.tag.isEmpty {
            parts.append(meal.tag)
        }
        if let made = meal.lastMadeAt {
            parts.append(Strings.Meals.lastMade(made.formatted(.dateTime.month(.abbreviated).day())))
        }
        return parts.isEmpty ? nil : parts.joined(separator: Strings.Lists.metaSeparator)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RoostColor.meal)
                .frame(width: 26, height: 26)
                .background(RoostColor.mealSoft, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.title)
                    .font(RoostFont.display(size: RoostFont.Size.body, weight: .semibold))
                    .foregroundStyle(RoostColor.ink)
                if let meta {
                    Text(meta)
                        .font(RoostFont.body(size: RoostFont.Size.caption))
                        .foregroundStyle(RoostColor.inkSoft)
                }
            }
            .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            if meal.nextUp {
                TagBadge(text: Strings.Meals.nextUpBadge, color: RoostColor.meal, soft: RoostColor.mealSoft)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
