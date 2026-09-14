// The Wishlist page: things to buy some day, with a price when there is one. Shopping's shape — type at
// the top, tick what was bought and it sinks into the Bought section, clear that section, swipe a row
// away with five seconds to take it back — plus a second field for the price. Every write goes to the
// store first, then kicks a sync. The Lists container applies NavigationStack and listTabChrome.
import RoostCore
import RoostDesign
import SwiftData
import SwiftUI

struct WishlistScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    @Query(filter: #Predicate<WishlistItemRecord> { !$0.removed }, sort: \WishlistItemRecord.createdAt, order: .reverse)
    private var items: [WishlistItemRecord]
    @Query private var syncStates: [SyncState]

    @State private var draft = ""
    @State private var priceDraft = ""
    @FocusState private var draftFocused: Bool
    @State private var undo = ListUndo()
    /// Counters the taps bump, so the haptics fire on what the reader did and never on a delta.
    @State private var added = 0
    @State private var checkedOff = 0
    @State private var uncheckedOff = 0
    @State private var editing: WishlistItemRecord?
    @State private var editDraft = ""
    @State private var editPriceDraft: String?

    private var person: String? {
        syncStates.first?.person
    }

    private var split: ShoppingSplit<WishlistItemRecord> {
        ShoppingSplit(rows: items, isBought: \.bought, boughtAt: \.boughtAt)
    }

    private var headerLine: String {
        let totals = WishlistTotals(rows: items, isBought: \.bought, priceCents: \.priceCents)
        return Strings.Wishlist.header(items: totals.openCount, total: totals.totalCents.map { PriceFormat.dollars(cents: $0) })
    }

    var body: some View {
        let rows = split
        List {
            Section {
                ListScreenHeader(title: Strings.Tabs.wishlist, line: headerLine, status: sync.statusLine)
                    .listHeaderRow()
            }
            Section {
                ListComposer(placeholder: Strings.Wishlist.add, text: $draft, focused: $draftFocused, onSubmit: add) {
                    if !draft.isEmpty {
                        TextField(Strings.Wishlist.price, text: $priceDraft)
                            .roostType(.subheadline)
                            .foregroundStyle(RoostColor.Role.textSecondary.color)
                            .keyboardType(.decimalPad)
                            .submitLabel(.done)
                            .onSubmit(add)
                            .padding(.leading, RoostSpacing.xl + RoostSpacing.md)
                            .accessibilityLabel(Strings.Wishlist.price)
                    }
                }
            }
            Section {
                if items.isEmpty {
                    ListEmptyState(symbol: "gift", line: Strings.Wishlist.empty, hint: Strings.Wishlist.emptyHint)
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
        .accessibilityIdentifier("wishlistList")
        .roostAnimation(.standard, value: items.map(\.bought))
        .roostHaptic(.selection, trigger: added)
        .roostHaptic(.checkOff, trigger: checkedOff)
        .roostHaptic(.undo, trigger: uncheckedOff)
        .undoBar(undo)
        .sheet(item: $editing) { item in
            ListEditSheet(
                title: Strings.Wishlist.editItem,
                fieldPlaceholder: Strings.Wishlist.add,
                draft: $editDraft,
                priceDraft: $editPriceDraft,
                onSave: { saveEdit(item) },
                onCancel: { editing = nil }
            )
        }
    }

    private var boughtHeader: some View {
        HStack {
            Text(Strings.Wishlist.boughtSection.uppercased())
                .roostType(.monoLabel)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
            Spacer(minLength: RoostSpacing.sm)
            Button(Strings.Wishlist.clearBought, action: clearBought)
                .roostType(.footnote)
                .foregroundStyle(RoostColor.Role.accent.color)
                .buttonStyle(.roostTrailingTextAction)
        }
        .textCase(nil)
    }

    private func row(_ item: WishlistItemRecord) -> some View {
        WishlistRow(
            item: item,
            onEdit: {
                editDraft = item.title
                editPriceDraft = item.priceCents.map { PriceFormat.dollars(cents: $0) }
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
        // A price that does not parse is not a reason to lose the title: the row goes in without one.
        let price = PriceParser.cents(from: priceDraft)
        do {
            guard try ListActions.addWishlistItem(draft, priceCents: price, by: person, in: context) != nil else {
                draft = "" // blank: let Return put the keyboard away
                priceDraft = ""
                return
            }
        } catch {
            return // the store refused; the fields keep what was typed
        }
        draft = ""
        priceDraft = ""
        added += 1
        sync.syncSoon()
        refocus($draftFocused)
    }

    private func toggle(_ item: WishlistItemRecord) {
        let bought = !item.bought
        try? ListActions.setWishlistBought(item, bought, by: person, in: context)
        if bought {
            checkedOff += 1
        } else {
            uncheckedOff += 1
        }
        sync.syncSoon()
    }

    /// The removal is in the store at once; its sync waits for the undo window (see `ListUndo`).
    private func remove(_ item: WishlistItemRecord) {
        let title = item.title
        try? ListActions.removeWishlistItem(item, in: context)
        undo.offer(Strings.Lists.removed(title), restore: { [context] in
            _ = try? ListActions.restoreWishlistItem(item, in: context)
            sync.syncSoon()
        }, commit: {
            sync.syncSoon()
        })
    }

    private func clearBought() {
        guard let cleared = try? ListActions.clearBoughtWishlist(in: context), !cleared.isEmpty else { return }
        undo.offer(Strings.Lists.removedCount(cleared.count), restore: { [context] in
            for item in cleared {
                _ = try? ListActions.restoreWishlistItem(item, in: context)
            }
            sync.syncSoon()
        }, commit: {
            sync.syncSoon()
        })
    }

    private func saveEdit(_ item: WishlistItemRecord) {
        try? ListActions.renameWishlistItem(
            item, to: editDraft, priceCents: PriceParser.cents(from: editPriceDraft ?? ""), in: context
        )
        editing = nil
        sync.syncSoon()
    }
}

private struct WishlistRow: View {
    let item: WishlistItemRecord
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var price: String? {
        item.priceCents.map { PriceFormat.dollars(cents: $0) }
    }

    /// Bought reads as done; the price and a refusal join the value so they are spoken, not just drawn.
    private var value: String {
        var parts = [item.bought ? Strings.Wishlist.bought : Strings.Wishlist.stillWanted]
        if let price {
            parts.append(Strings.Wishlist.priced(price))
        }
        if item.rejected {
            parts.append(Strings.Lists.didNotSyncValue)
        }
        return parts.joined(separator: Strings.Lists.metaSeparator)
    }

    private var title: some View {
        Text(item.title)
            .roostType(.rowTitle)
            .foregroundStyle(item.bought ? RoostColor.Role.textSecondary.color : RoostColor.Role.textPrimary.color)
            .strikethrough(item.bought, color: RoostColor.Role.textSecondary.color)
            .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var chips: some View {
        if let price {
            MetaChip(text: price, role: .accent)
        }
        if item.rejected {
            NotSyncedMarker()
        }
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
                // At an accessibility size the chips drop under the title rather than squeezing it.
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: RoostSpacing.sm) {
                        HStack(spacing: RoostSpacing.sm) {
                            title
                            Spacer(minLength: RoostSpacing.sm)
                            avatar
                        }
                        HStack(spacing: RoostSpacing.sm) {
                            chips
                        }
                    }
                } else {
                    title
                    Spacer(minLength: RoostSpacing.sm)
                    chips
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
        .accessibilityHint(item.bought ? Strings.Wishlist.markStillWanted : Strings.Wishlist.markBought)
        .contextMenu {
            Button(Strings.Lists.edit, systemImage: "pencil", action: onEdit)
            Button(Strings.Lists.delete, systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityAction(named: Text(Strings.Lists.edit), onEdit)
    }
}
