// The wishlist's writes; the shape is ListActions'
// shopping section
import Foundation
import SwiftData

extension ListActions {

    // MARK: wishlist

    /// The server's ceiling for a price, in cents ($999,999.99).
    static let priceLimit = 99_999_999

    @discardableResult
    static func addWishlistItem(_ title: String, priceCents: Int?, by person: String?, in context: ModelContext,
                                now: Date = Date()) throws -> WishlistItemRecord?
    {
        guard let title = cleaned(title) else { return nil }
        let item = WishlistItemRecord(
            id: newId(), title: title, priceCents: clampedPrice(priceCents), addedBy: person ?? "", createdAt: now
        )
        context.insert(item)
        try context.save()
        return item
    }

    static func setWishlistBought(
        _ item: WishlistItemRecord,
        _ bought: Bool,
        by person: String?,
        in context: ModelContext,
        now: Date = Date()
    ) throws {
        item.bought = bought
        item.boughtBy = bought ? person : nil
        item.boughtAt = bought ? now : nil
        item.markEdited(.bought, at: now)
        try context.save()
    }

    /// nil clears the price.
    static func setPrice(_ item: WishlistItemRecord, _ priceCents: Int?, in context: ModelContext,
                         now: Date = Date()) throws
    {
        item.priceCents = clampedPrice(priceCents)
        item.markEdited(.price, at: now)
        try context.save()
    }

    static func removeWishlistItem(_ item: WishlistItemRecord, in context: ModelContext, now: Date = Date()) throws {
        item.markRemoved(at: now)
        try context.save()
    }

    /// Everything already bought, removed in one go. Returns the rows so the undo bar can put them back.
    @discardableResult
    static func clearBoughtWishlist(in context: ModelContext, now: Date = Date()) throws -> [WishlistItemRecord] {
        let ticked = try context.fetch(FetchDescriptor<WishlistItemRecord>(
            predicate: #Predicate { $0.bought && !$0.removed }
        ))
        for item in ticked {
            item.markRemoved(at: now)
        }
        try context.save()
        return ticked
    }

    /// Undo of `removeWishlistItem`, with the same two outcomes as a shopping row: the same row when
    /// the DELETE never left the phone, a fresh copy when the server has already been told.
    @discardableResult
    static func restoreWishlistItem(
        _ item: WishlistItemRecord, in context: ModelContext, now: Date = Date()
    ) throws -> WishlistItemRecord {
        guard item.deleteReachedServer else {
            item.unremove(at: now)
            try context.save()
            return item
        }
        let copy = WishlistItemRecord(
            id: newId(),
            title: item.title,
            priceCents: item.priceCents,
            addedBy: item.addedBy,
            bought: item.bought,
            boughtBy: item.boughtBy,
            boughtAt: item.boughtAt,
            createdAt: item.createdAt,
            updatedAt: now
        )
        // The create carries id, title and price; a ticked row needs `bought` sent after it.
        if copy.bought {
            copy.pendingFields = .bought
        }
        context.insert(copy)
        try context.save()
        return copy
    }

    /// nil stays nil; anything else lands inside the server's 0...priceLimit.
    static func clampedPrice(_ cents: Int?) -> Int? {
        cents.map { min(max($0, 0), priceLimit) }
    }

}
