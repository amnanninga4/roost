// Shopping tab: the running list. Add at the top, tick what was bought (it sinks to the bottom, struck
// through), swipe to delete. Every write goes to the store first, then kicks a sync.
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

    private var person: String? {
        syncStates.first?.person
    }

    /// Newest first while still to buy; bought rows follow, most recently bought first.
    private var ordered: [ShoppingItemRecord] {
        let toBuy = items.filter { !$0.bought }
        let bought = items.filter(\.bought).sorted { ($0.boughtAt ?? .distantPast) > ($1.boughtAt ?? .distantPast) }
        return toBuy + bought
    }

    private var boughtCount: Int {
        items.filter(\.bought).count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ListScreenHeader(
                        title: Strings.Tabs.shopping,
                        line: Strings.Shopping.header(items: items.count, bought: boughtCount)
                    )
                    .listHeaderRow()
                }
                Section {
                    AddRow(placeholder: Strings.Shopping.add, text: $draft, focused: $draftFocused, onSubmit: add)
                }
                Section {
                    if items.isEmpty {
                        EmptyLine(text: Strings.Shopping.empty)
                    }
                    ForEach(ordered) { item in
                        ShoppingRow(item: item) { toggle(item) }
                            .listRowBackground(RoostColor.surface)
                            .swipeToDelete { remove(item) }
                    }
                }
            }
            .listTabChrome()
            .animation(.default, value: ordered.map { "\($0.id)|\($0.bought)" })
        }
        .tint(RoostColor.accent)
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
        sync.syncSoon()
        refocus($draftFocused) // keep the keyboard up: groceries come in batches
    }

    private func toggle(_ item: ShoppingItemRecord) {
        try? ListActions.setBought(item, !item.bought, by: person, in: context)
        sync.syncSoon()
    }

    private func remove(_ item: ShoppingItemRecord) {
        try? ListActions.removeShoppingItem(item, in: context)
        sync.syncSoon()
    }
}

private struct ShoppingRow: View {
    let item: ShoppingItemRecord
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                CheckCircle(isOn: item.bought)
                Text(item.title)
                    .font(RoostFont.body(size: RoostFont.Size.body, weight: .semibold))
                    .foregroundStyle(item.bought ? RoostColor.inkSoft : RoostColor.ink)
                    .strikethrough(item.bought, color: RoostColor.inkSoft)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if let person = Person(rawValue: item.addedBy) {
                    PersonAvatar(person: person)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.bought ? Strings.Shopping.bought : Strings.Shopping.stillNeeded)
        .accessibilityHint(item.bought ? Strings.Shopping.markStillNeeded : Strings.Shopping.markBought)
    }
}
