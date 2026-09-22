// Meals page: the bank of ideas. Hosted by ListsScreen, which owns the NavigationStack and chrome. Add a title and, if
// you like, a tag; mark one NEXT UP so the badge
// moves to it; say "Made it" and the row remembers when. Swipe a row away with five seconds to take
// it back. Writes go to the store first, then kick a sync.
import RoostCore
import RoostDesign
import SwiftData
import SwiftUI

struct MealsScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    @Query(filter: #Predicate<MealRecord> { !$0.removed }, sort: \MealRecord.createdAt, order: .reverse)
    private var meals: [MealRecord]

    @State private var showingAdd = false
    @State private var title = ""
    @State private var tag = ""
    @FocusState private var titleFocused: Bool
    @State private var undo = ListUndo()
    /// Counters the taps bump, so nothing buzzes for a row the other phone changed.
    @State private var added = 0
    @State private var marked = 0

    /// The next-up meal first, then newest ideas first.
    private var ordered: [MealRecord] {
        let upNext = meals.filter(\.nextUp)
        let rest = meals.filter { !$0.nextUp }
        return upNext + rest
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: RoostSpacing.md) {
                    ListScreenHeader(
                        title: Strings.Tabs.meals,
                        line: Strings.Meals.header(count: meals.count),
                        status: sync.statusLine
                    )
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .roostType(.title)
                            .foregroundStyle(RoostColor.Role.accent.color)
                            .frame(minWidth: RoostSpacing.minTapTarget, minHeight: RoostSpacing.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.roostPressQuiet)
                    .accessibilityLabel(Strings.Meals.newIdea)
                    .accessibilityIdentifier("meals.add")
                }
                .listHeaderRow()
            }
            Section {
                if meals.isEmpty {
                    ListEmptyState(
                        symbol: "fork.knife", line: Strings.Meals.empty, hint: Strings.Meals.emptyHint
                    )
                }
                ForEach(ordered) { meal in
                    row(meal)
                }
            }
        }
        .accessibilityIdentifier("mealsList")
        .roostAnimation(.standard, value: ordered.map(\.id))
        .roostHaptic(.selection, trigger: added)
        .roostHaptic(.checkOff, trigger: marked)
        .undoBar(undo)
        .sheet(isPresented: $showingAdd) { addSheet }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                TextField(Strings.Meals.add, text: $title)
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .accessibilityIdentifier("meals.idea")
                    .listRowBackground(RoostColor.Role.surface.color)
                TextField(Strings.Meals.tag, text: $tag)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .listRowBackground(RoostColor.Role.surface.color)
            }
            .scrollContentBackground(.hidden)
            .background(RoostColor.Role.background.color)
            .navigationTitle(Strings.Meals.newIdea)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Settings.cancel) {
                        title = ""
                        tag = ""
                        showingAdd = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.Lists.save, action: add)
                        .disabled(ListActions.cleaned(title) == nil)
                }
            }
            .task { titleFocused = true }
        }
        .tint(RoostColor.Role.accent.color)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ meal: MealRecord) -> some View {
        MealRow(meal: meal)
            .listRowBackground(RoostColor.Role.surface.color)
            .roostTransition(.row)
            .swipeActions(edge: .leading) {
                Button { setNextUp(meal, !meal.nextUp) } label: {
                    Label(meal.nextUp ? Strings.Meals.clearNextUp : Strings.Meals.nextUp, systemImage: "flame")
                }
                .tint(RoostColor.Role.bonus.color)
                Button { madeToday(meal) } label: {
                    Label(Strings.Meals.madeIt, systemImage: "checkmark.circle")
                }
                .tint(RoostColor.Role.meals.color)
            }
            .swipeToDelete(rejected: meal.rejected) { remove(meal) }
            .contextMenu {
                Button { setNextUp(meal, !meal.nextUp) } label: {
                    Label(meal.nextUp ? Strings.Meals.clearNextUp : Strings.Meals.nextUp, systemImage: "flame")
                }
                Button { madeToday(meal) } label: {
                    Label(Strings.Meals.madeIt, systemImage: "checkmark.circle")
                }
                Button(role: .destructive) { remove(meal) } label: {
                    Label(meal.rejected ? Strings.Lists.remove : Strings.Lists.delete, systemImage: "trash")
                }
            }
    }

    // MARK: actions

    private func add() {
        do {
            guard try ListActions.addMeal(title, tag: tag, in: context) != nil else {
                return
            }
        } catch {
            return // the store refused; the fields keep what was typed
        }
        title = ""
        tag = ""
        added += 1
        sync.syncSoon()
        showingAdd = false
    }

    private func setNextUp(_ meal: MealRecord, _ isOn: Bool) {
        try? ListActions.setNextUp(meal, isOn, in: context)
        sync.syncSoon()
    }

    private func madeToday(_ meal: MealRecord) {
        try? ListActions.madeToday(meal, in: context)
        marked += 1
        sync.syncSoon()
    }

    /// The removal is in the store at once; its sync waits for the undo window (see `ListUndo`).
    private func remove(_ meal: MealRecord) {
        let title = meal.title
        try? ListActions.removeMeal(meal, in: context)
        undo.offer(Strings.Lists.removed(title), restore: { [context] in
            _ = try? ListActions.restoreMeal(meal, in: context)
            sync.syncSoon()
        }, commit: {
            sync.syncSoon()
        })
    }
}

private struct MealRow: View {
    let meal: MealRecord
    @Environment(\.dynamicTypeSize) private var typeSize

    /// "last made Tuesday"; nil until it has been made once.
    private var lastMade: String? {
        meal.lastMadeAt.map { Strings.Meals.lastMade(MealDates.lastMade($0)) }
    }

    private var hasMeta: Bool {
        !meal.tag.isEmpty || lastMade != nil || meal.rejected || (meal.nextUp && typeSize.isAccessibilitySize)
    }

    private var nextUpBadge: some View {
        TagBadge(text: Strings.Meals.nextUpBadge, role: .bonus, symbol: "flame.fill")
            .roostTransition(.badge)
    }

    /// The row as one sentence, for VoiceOver: the title, the tag, when it was last made, and the
    /// two flags that are drawn rather than written.
    private var value: String {
        var parts: [String] = []
        if meal.nextUp {
            parts.append(Strings.Meals.nextUp)
        }
        if !meal.tag.isEmpty {
            parts.append(meal.tag)
        }
        if let lastMade {
            parts.append(lastMade)
        }
        if meal.rejected {
            parts.append(Strings.Lists.didNotSyncValue)
        }
        return parts.joined(separator: Strings.Lists.metaSeparator)
    }

    var body: some View {
        HStack(spacing: RoostSpacing.md) {
            if !typeSize.isAccessibilitySize {
                MealGlyph()
            }

            VStack(alignment: .leading, spacing: RoostSpacing.xs) {
                Text(meal.title)
                    .roostType(.rowTitle)
                    .foregroundStyle(RoostColor.Role.textPrimary.color)
                if hasMeta {
                    // At an accessibility size the badge cannot sit beside the title without
                    // crushing it, so it joins the meta line under it.
                    let metadataLayout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: RoostSpacing.xs))
                        : AnyLayout(HStackLayout(spacing: RoostSpacing.sm))
                    metadataLayout {
                        if meal.nextUp, typeSize.isAccessibilitySize {
                            nextUpBadge
                        }
                        if !meal.tag.isEmpty {
                            MetaChip(text: meal.tag, role: .meals)
                        }
                        if let lastMade {
                            Text(lastMade)
                                .roostType(.caption)
                                .foregroundStyle(RoostColor.Role.textSecondary.color)
                        }
                        if meal.rejected {
                            NotSyncedMarker()
                        }
                    }
                }
            }
            .multilineTextAlignment(.leading)

            Spacer(minLength: RoostSpacing.sm)

            if meal.nextUp, !typeSize.isAccessibilitySize {
                nextUpBadge
            }
        }
        .padding(.vertical, RoostSpacing.xs)
        .frame(minHeight: RoostSpacing.minTapTarget)
        .contentShape(Rectangle())
        .roostAnimation(.standard, value: meal.nextUp)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(meal.title)
        .accessibilityValue(value)
    }
}

/// The meal icon from the mockup: a flame on its soft ground.
private struct MealGlyph: View {
    @ScaledMetric(relativeTo: .body) private var scaled: CGFloat = RoostSpacing.xl

    private var side: CGFloat {
        min(scaled, RoostAvatar.glyphCeiling)
    }

    var body: some View {
        Image(systemName: "flame.fill")
            .roostType(.caption)
            .foregroundStyle(RoostColor.Role.meals.color)
            .frame(width: side, height: side)
            .background(RoostColor.Role.mealsSoft.color, in: RoostRadius.shape(RoostRadius.md))
            .accessibilityHidden(true)
    }
}
