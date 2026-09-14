// Shopping page: the running list. Hosted by ListsScreen, which owns the NavigationStack and chrome. Type at the top, tick what was bought and it sinks into the Bought
// section, clear that section when the trip is over, swipe a row away with five seconds to take it
// back. Every write goes to the store first, then kicks a sync, so a tap is on screen before the
// network is involved and works the same offline.
import RoostCore
import RoostDesign
import SwiftData
import SwiftUI

struct ShoppingScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    @Query(filter: #Predicate<ShoppingItemRecord> { !$0.removed }, sort: \ShoppingItemRecord.createdAt, order: .reverse)
    private var items: [ShoppingItemRecord]
    @Query private var syncStates: [SyncState]

    @State private var draft = ""
    @FocusState private var draftFocused: Bool
    @State private var undo = ListUndo()
    /// Counters the taps bump, so the haptics fire on what the reader did and not on a row the other
    /// phone ticked: a delta arriving mid-list must never buzz.
    @State private var added = 0
    @State private var checkedOff = 0
    @State private var uncheckedOff = 0
    @State private var editing: ShoppingItemRecord?
    @State private var editDraft = ""

    private var person: String? {
        syncStates.first?.person
    }

    private var split: ShoppingSplit<ShoppingItemRecord> {
        ShoppingSplit(rows: items, isBought: \.bought, boughtAt: \.boughtAt)
    }

    var body: some View {
        let rows = split
        List {
                Section {
                    ListScreenHeader(
                        title: Strings.Tabs.shopping,
                        line: Strings.Shopping.header(items: rows.total, bought: rows.boughtCount),
                        status: sync.statusLine
                    )
                    .listHeaderRow()
                }
                Section {
                    ListComposer(
                        placeholder: Strings.Shopping.add, text: $draft, focused: $draftFocused, onSubmit: add
                    )
                }
                Section {
                    if items.isEmpty {
                        ListEmptyState(
                            symbol: "cart", line: Strings.Shopping.empty, hint: Strings.Shopping.emptyHint
                        )
                    }
                    ForEach(rows.toBuy) { item in
                        row(item)
                    }
                }
                if !rows.bought.isEmpty {
                    Section {
                        ForEach(rows.bought) { item in
                            row(item)
                        }
                    } header: {
                        boughtHeader
                    }
                }
        }
        .accessibilityIdentifier("shoppingList")
        .roostAnimation(.standard, value: items.map(\.bought))
        .roostHaptic(.selection, trigger: added)
        .roostHaptic(.checkOff, trigger: checkedOff)
        .roostHaptic(.undo, trigger: uncheckedOff)
        .undoBar(undo)
        .sheet(item: $editing) { item in
            ListEditSheet(
                title: Strings.Shopping.editItem,
                fieldPlaceholder: Strings.Shopping.add,
                draft: $editDraft,
                priceDraft: nil,
                onSave: { saveEdit(item) },
                onCancel: { editing = nil }
            )
        }
    }

    /// "Bought" over the action that empties it. The button is the only chrome in a section header,
    /// so it carries the accent and its own tap target.
    private var boughtHeader: some View {
        HStack {
            Text(Strings.Shopping.boughtSection.uppercased())
                .roostType(.monoLabel)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
            Spacer(minLength: RoostSpacing.sm)
            Button(Strings.Shopping.clearBought, action: clearBought)
                .roostType(.footnote)
                .foregroundStyle(RoostColor.Role.accent.color)
                .buttonStyle(.roostTrailingTextAction)
        }
        .textCase(nil)
    }

    private func row(_ item: ShoppingItemRecord) -> some View {
        ShoppingRow(
            item: item,
            onEdit: {
                editDraft = item.title
                editing = item
            },
            onDelete: { remove(item) }
        ) { toggle(item) }
            .listRowBackground(RoostColor.Role.surface.color)
            .roostTransition(.checkOff)
            .swipeToDelete(rejected: item.rejected) { remove(item) }
    }

    // MARK: actions

    private func add() {
        do {
            guard try ListActions.addShoppingItem(draft, by: person, in: context) != nil else {
                draft = "" // blank: let Return put the keyboard away, and take the stray spaces with it
                return
            }
        } catch {
            return // the store refused; the line stays in the field
        }
        draft = ""
        added += 1
        sync.syncSoon()
        refocus($draftFocused) // keep the keyboard up: groceries come in batches
    }

    private func toggle(_ item: ShoppingItemRecord) {
        let bought = !item.bought
        try? ListActions.setBought(item, bought, by: person, in: context)
        if bought {
            checkedOff += 1
        } else {
            uncheckedOff += 1
        }
        sync.syncSoon()
    }

    /// The removal is in the store at once; its sync waits for the undo window (see `ListUndo`).
    private func remove(_ item: ShoppingItemRecord) {
        let title = item.title
        try? ListActions.removeShoppingItem(item, in: context)
        undo.offer(Strings.Lists.removed(title), restore: { [context] in
            _ = try? ListActions.restoreShoppingItem(item, in: context)
            sync.syncSoon()
        }, commit: {
            sync.syncSoon()
        })
    }

    private func clearBought() {
        guard let cleared = try? ListActions.clearBought(in: context), !cleared.isEmpty else { return }
        undo.offer(Strings.Lists.removedCount(cleared.count), restore: { [context] in
            for item in cleared {
                _ = try? ListActions.restoreShoppingItem(item, in: context)
            }
            sync.syncSoon()
        }, commit: {
            sync.syncSoon()
        })
    }

    private func saveEdit(_ item: ShoppingItemRecord) {
        try? ListActions.renameShoppingItem(item, to: editDraft, in: context)
        editing = nil
        sync.syncSoon()
    }
}

private struct ShoppingRow: View {
    let item: ShoppingItemRecord
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Bought reads as done, and a row the server refused says so.
    private var value: String {
        let state = item.bought ? Strings.Shopping.bought : Strings.Shopping.stillNeeded
        guard item.rejected else { return state }
        return state + Strings.Lists.metaSeparator + Strings.Lists.didNotSyncValue
    }

    private var title: some View {
        Text(item.title)
            .roostType(.rowTitle)
            .foregroundStyle(item.bought ? RoostColor.Role.textSecondary.color : RoostColor.Role.textPrimary.color)
            .strikethrough(item.bought, color: RoostColor.Role.textSecondary.color)
            .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var avatar: some View {
        if let person = Person(rawValue: item.addedBy) {
            RoostAvatar(person: person.design, label: Strings.Lists.addedBy(person.displayName))
        }
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: RoostSpacing.md) {
                CheckCircle(isOn: item.bought)
                // At an accessibility size there is no room for a marker beside the words, so it
                // drops to its own line rather than squeezing the title down to two letters.
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: RoostSpacing.sm) {
                        HStack(spacing: RoostSpacing.sm) {
                            title
                            Spacer(minLength: RoostSpacing.sm)
                            avatar
                        }
                        if item.rejected {
                            NotSyncedMarker()
                        }
                    }
                } else {
                    title
                    Spacer(minLength: RoostSpacing.sm)
                    if item.rejected {
                        NotSyncedMarker()
                    }
                    avatar
                }
            }
            .padding(.vertical, RoostSpacing.xs)
            .frame(minHeight: RoostSpacing.minTapTarget)
            .contentShape(Rectangle())
        }
        // Quiet: the toggle already fires .checkOff / .undo on the same touch.
        .buttonStyle(.roostPressQuiet)
        .accessibilityLabel(item.title)
        .accessibilityValue(value)
        .accessibilityHint(item.bought ? Strings.Shopping.markStillNeeded : Strings.Shopping.markBought)
        .contextMenu {
            Button(Strings.Lists.edit, systemImage: "pencil", action: onEdit)
            Button(Strings.Lists.delete, systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityAction(named: Text(Strings.Lists.edit), onEdit)
    }
}
