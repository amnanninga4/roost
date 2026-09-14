// The wishlist's arithmetic and its store actions, without a screen or a server: what a typed price
// becomes, how a price reads back, what the header adds up, and the undo paths a wishlist row shares
// with a shopping row.
@testable import Roost
import SwiftData
import XCTest

final class WishlistCraftTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        container = try ModelContainer(
            for: RoostSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    // MARK: the price field

    func testTypedPricesBecomeWholeCents() {
        XCTAssertEqual(PriceParser.cents(from: "599"), 59900)
        XCTAssertEqual(PriceParser.cents(from: "12.5"), 1250)
        XCTAssertEqual(PriceParser.cents(from: "12.50"), 1250)
        XCTAssertEqual(PriceParser.cents(from: "$1,299.99"), 129_999)
        XCTAssertEqual(PriceParser.cents(from: " 0 "), 0)
        XCTAssertEqual(PriceParser.cents(from: ".5"), 50)
        XCTAssertEqual(PriceParser.cents(from: "12."), 1200)
        XCTAssertEqual(PriceParser.cents(from: "999999.99"), 99_999_999, "the server's ceiling")
    }

    func testJunkAndOutOfRangePricesAreNil() {
        for junk in ["", "   ", "abc", "-5", "1.234", "1.2.3", "$", ".", "1,000,000", "1e3", "12 50"] {
            XCTAssertNil(PriceParser.cents(from: junk), junk)
        }
    }

    func testPricesReadAsDollarsAndOnlyShowCentsWhenThereAreSome() {
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(PriceFormat.dollars(cents: 59900, locale: us), "$599")
        XCTAssertEqual(PriceFormat.dollars(cents: 1250, locale: us), "$12.50")
        XCTAssertEqual(PriceFormat.dollars(cents: 185_000, locale: us), "$1,850")
        XCTAssertEqual(PriceFormat.dollars(cents: 0, locale: us), "$0")
        XCTAssertEqual(PriceFormat.dollars(cents: 99_999_999, locale: us), "$999,999.99")
    }

    // MARK: the header

    private struct Row {
        let bought: Bool
        let price: Int?
    }

    func testHeaderCountsOpenItemsAndTotalsOnlyThePricedOnes() {
        let rows = [Row(bought: false, price: 59900), Row(bought: false, price: nil),
                    Row(bought: false, price: 125_100), Row(bought: true, price: 999_900)]
        let totals = WishlistTotals(rows: rows, isBought: \.bought, priceCents: \.price)
        XCTAssertEqual(totals.openCount, 3)
        XCTAssertEqual(totals.totalCents, 185_000, "bought rows do not count")
        XCTAssertEqual(Strings.Wishlist.header(items: 3, total: "$1,850"), "3 items · $1,850 total")
        XCTAssertEqual(Strings.Wishlist.header(items: 1, total: nil), "1 item")
        let unpriced = WishlistTotals(rows: [Row(bought: false, price: nil)], isBought: \.bought, priceCents: \.price)
        XCTAssertNil(unpriced.totalCents, "no priced item, no total")
    }

    // MARK: the actions

    func testAddingKeepsThePriceInsideTheServersRangeAndBlankTitlesAreNotAdded() throws {
        XCTAssertNil(try ListActions.addWishlistItem("   ", priceCents: 100, by: "anne", in: context, now: clock))
        let item = try XCTUnwrap(try ListActions.addWishlistItem(" Bigger TV ", priceCents: 59900, by: nil, in: context, now: clock))
        XCTAssertEqual(item.title, "Bigger TV")
        XCTAssertEqual(item.priceCents, 59900)
        XCTAssertEqual(item.addedBy, "", "blank until the server stamps it")
        XCTAssertTrue(item.needsPost)
        let free = try XCTUnwrap(try ListActions.addWishlistItem("A weekend away", priceCents: nil, by: "wes", in: context, now: clock))
        XCTAssertNil(free.priceCents)
        XCTAssertEqual(ListActions.clampedPrice(-1), 0)
        XCTAssertEqual(ListActions.clampedPrice(100_000_000), ListActions.priceLimit)
        XCTAssertNil(ListActions.clampedPrice(nil))
    }

    func testPriceAndBoughtEditsFlagOnlyTheirOwnField() throws {
        let item = WishlistItemRecord(id: "w-1", title: "Kayak", priceCents: 89900, addedBy: "anne",
                                      createdAt: clock, syncedAt: clock)
        context.insert(item)
        try context.save()
        try ListActions.setPrice(item, nil, in: context, now: clock)
        XCTAssertNil(item.priceCents)
        XCTAssertEqual(item.pendingFields, [.price])
        try ListActions.setWishlistBought(item, true, by: "wes", in: context, now: clock)
        XCTAssertEqual(item.pendingFields, [.price, .bought])
        XCTAssertEqual(item.boughtBy, "wes")
        XCTAssertEqual(item.boughtAt, clock)
        try ListActions.setWishlistBought(item, false, by: "wes", in: context, now: clock)
        XCTAssertNil(item.boughtBy)
        XCTAssertNil(item.boughtAt)
    }


    func testRenameFlagsOnlyWhatChanged() throws {
        let item = WishlistItemRecord(id: "w-9", title: "Kayak", priceCents: 89900, addedBy: "anne",
                                      createdAt: clock, syncedAt: clock)
        context.insert(item)
        try context.save()
        try ListActions.renameWishlistItem(item, to: "Kayak (tandem)", priceCents: 89900, in: context, now: clock)
        XCTAssertEqual(item.title, "Kayak (tandem)")
        XCTAssertEqual(item.pendingFields, [.title], "the price did not change, so it is not flagged")
        try ListActions.renameWishlistItem(item, to: "Kayak (tandem)", priceCents: nil, in: context, now: clock)
        XCTAssertNil(item.priceCents, "nil clears the price")
        XCTAssertEqual(item.pendingFields, [.title, .price])
        try ListActions.renameWishlistItem(item, to: "   ", priceCents: 500, in: context, now: clock)
        XCTAssertEqual(item.title, "Kayak (tandem)", "a blank title keeps the old one, so a price-only edit still lands")
        XCTAssertEqual(item.priceCents, 500)
    }


    func testUndoAfterTheDeleteWentOutCopiesThePriceAndFlagsBought() throws {
        let item = WishlistItemRecord(id: "w-2", title: "Standing desk", priceCents: 45000, addedBy: "wes",
                                      bought: true, boughtBy: "anne", boughtAt: clock, createdAt: clock, syncedAt: clock)
        context.insert(item)
        try context.save()
        try ListActions.removeWishlistItem(item, in: context, now: clock)
        item.deleteSynced = true // the DELETE has been acknowledged
        let copy = try ListActions.restoreWishlistItem(item, in: context, now: clock)
        XCTAssertNotEqual(copy.id, item.id)
        XCTAssertEqual(copy.priceCents, 45000)
        XCTAssertTrue(copy.bought)
        XCTAssertEqual(copy.pendingFields, [.bought], "the create carries the price; bought follows as a PATCH")
        XCTAssertTrue(item.removed, "the tombstone stays")
    }

    func testUndoOfADeleteThatNeverLeftUnremovesTheSameRow() throws {
        let item = try XCTUnwrap(try ListActions.addWishlistItem("Kayak", priceCents: nil, by: "wes", in: context, now: clock))
        try ListActions.removeWishlistItem(item, in: context, now: clock)
        XCTAssertTrue(item.deleteSynced, "never reached the server, so nothing to send")
        let back = try ListActions.restoreWishlistItem(item, in: context, now: clock)
        XCTAssertTrue(back === item)
        XCTAssertFalse(item.removed)
        XCTAssertTrue(item.needsPost)
    }

    func testClearBoughtRemovesEveryTickedRowAndReturnsThem() throws {
        for (index, bought) in [true, false, true].enumerated() {
            context.insert(WishlistItemRecord(id: "w-\(index)", title: "Thing \(index)", addedBy: "anne", bought: bought,
                                              createdAt: clock, syncedAt: clock))
        }
        try context.save()
        let cleared = try ListActions.clearBoughtWishlist(in: context, now: clock)
        XCTAssertEqual(Set(cleared.map(\.id)), ["w-0", "w-2"])
        let live = try context.fetch(FetchDescriptor<WishlistItemRecord>(predicate: #Predicate { !$0.removed }))
        XCTAssertEqual(live.map(\.id), ["w-1"])
    }
}
