// The wishlist through a sync pass: the create with and without a price, the price and bought
// patches, the delete, a refusal, and the delta. Same stub server as the other list suites.
@testable import Roost
import SwiftData
import XCTest

final class WishlistSyncTests: ListSyncTestCase {
    func testAddWithAPriceIsPostedOnceWithThePriceAndMarkedSynced() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let item = try XCTUnwrap(try ListActions.addWishlistItem("Bigger TV", priceCents: 59900, by: nil, in: ctx, now: listClock))
        let id = item.id
        StubURLProtocol.reset { req in
            let row = wishlistJSON(id: id, title: "Bigger TV", priceCents: 59900, seq: 8)
            if req.httpMethod == "POST" {
                return (201, json(row))
            }
            return (200, listsSyncJSON(cursor: 8, wishlist: [row]))
        }
        let outcome = await client.syncNow()
        XCTAssertEqual(outcome, .synced(posted: 1, deleted: 0, received: 1))
        let post = try XCTUnwrap(StubURLProtocol.requests("POST").first)
        XCTAssertEqual(post.path, "/wishlist")
        XCTAssertEqual(post.body?["id"] as? String, id)
        XCTAssertEqual(post.body?["title"] as? String, "Bigger TV")
        XCTAssertEqual(post.body?["priceCents"] as? Int, 59900)
        XCTAssertEqual(StubURLProtocol.requests("PATCH").count, 0, "a 201 took the price; nothing follows")
        let synced = try XCTUnwrap(try wishlistRow(id))
        XCTAssertNotNil(synced.syncedAt)
        XCTAssertEqual(synced.seq, 8)
        XCTAssertEqual(synced.addedBy, "anne", "the server's stamp replaces the blank")
        XCTAssertEqual(synced.pendingPatch, 0)

        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 8)) }
        _ = await client.syncNow()
        XCTAssertEqual(StubURLProtocol.requests("POST").count, 0, "already synced rows are not re-posted")
    }

    func testAddWithoutAPriceSendsNullAndABoughtBeforeTheCreateFollowsAsAPatch() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let item = try XCTUnwrap(try ListActions.addWishlistItem("A weekend away", priceCents: nil, by: nil, in: ctx, now: listClock))
        try ListActions.setWishlistBought(item, true, by: "anne", in: ctx, now: listClock)
        let id = item.id
        StubURLProtocol.reset { req in
            switch req.httpMethod {
            case "POST": return (201, json(wishlistJSON(id: id, title: "A weekend away", seq: 3)))
            case "PATCH": return (200, json(wishlistJSON(id: id, title: "A weekend away", bought: true, boughtBy: "anne", boughtAt: listStamp, seq: 4)))
            default: return (200, listsSyncJSON(cursor: 4))
            }
        }
        _ = await client.syncNow()
        let post = try XCTUnwrap(StubURLProtocol.requests("POST").first)
        XCTAssertTrue(post.body?["priceCents"] is NSNull, "no price is sent as null, not left out")
        let patch = try XCTUnwrap(StubURLProtocol.requests("PATCH").first)
        XCTAssertEqual(patch.path, "/wishlist/\(id)")
        XCTAssertEqual(patch.body?["bought"] as? Bool, true)
        XCTAssertNil(patch.body?["priceCents"], "the create carried the price; only bought is left")
        XCTAssertEqual(try wishlistRow(id)?.seq, 4)
    }

    func testPricePatchSendsOnlyThePriceAndClearingSendsNull() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let item = WishlistItemRecord(id: "w-1", title: "Kayak", priceCents: 89900, addedBy: "wes", createdAt: listClock, syncedAt: listClock)
        item.seq = 5
        ctx.insert(item)
        try ctx.save()
        try ListActions.setPrice(item, 79900, in: ctx, now: listClock)
        StubURLProtocol.reset { req in
            let row = wishlistJSON(id: "w-1", title: "Kayak", priceCents: 79900, addedBy: "wes", seq: 9)
            if req.httpMethod == "PATCH" {
                return (200, json(row))
            }
            return (200, listsSyncJSON(cursor: 9, wishlist: [row]))
        }
        _ = await client.syncNow()
        let patch = try XCTUnwrap(StubURLProtocol.requests("PATCH").first)
        XCTAssertEqual(patch.body?["priceCents"] as? Int, 79900)
        XCTAssertNil(patch.body?["title"])
        XCTAssertNil(patch.body?["bought"])
        XCTAssertEqual(try wishlistRow("w-1")?.pendingPatch, 0)

        let again = fresh()
        try ListActions.setPrice(XCTUnwrap(try wishlistRow("w-1", in: again)), nil, in: again, now: listClock)
        StubURLProtocol.reset { req in
            if req.httpMethod == "PATCH" {
                return (200, json(wishlistJSON(id: "w-1", title: "Kayak", addedBy: "wes", seq: 10)))
            }
            return (200, listsSyncJSON(cursor: 10))
        }
        _ = await client.syncNow()
        XCTAssertTrue(StubURLProtocol.requests("PATCH").first?.body?["priceCents"] is NSNull, "clearing sends null")
        XCTAssertNil(try wishlistRow("w-1")?.priceCents)
    }

    func testDeleteReplaysAsDELETEAndARefusedCreateIsKeptAndNeverRetried() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let synced = WishlistItemRecord(id: "w-2", title: "Standing desk", priceCents: 45000, addedBy: "anne", createdAt: listClock, syncedAt: listClock)
        synced.seq = 6
        ctx.insert(synced)
        try ctx.save()
        try ListActions.removeWishlistItem(synced, in: ctx, now: listClock)
        let refused = try XCTUnwrap(try ListActions.addWishlistItem("x", priceCents: nil, by: nil, in: ctx, now: listClock))
        StubURLProtocol.reset { req in
            switch req.httpMethod {
            case "DELETE": return (200, json(wishlistJSON(id: "w-2", title: "Standing desk", priceCents: 45000, seq: 11, deleted: true)))
            case "POST": return (400, json(["error": "title required: 1-200 chars"]))
            default: return (200, listsSyncJSON(cursor: 11))
            }
        }
        let outcome = await client.syncNow()
        XCTAssertEqual(outcome, .synced(posted: 0, deleted: 1, received: 0))
        XCTAssertEqual(StubURLProtocol.requests("DELETE").map(\.path), ["/wishlist/w-2"])
        XCTAssertEqual(try wishlistRow("w-2")?.deleteSynced, true)
        let kept = try XCTUnwrap(try wishlistRow(refused.id))
        XCTAssertTrue(kept.rejected)
        XCTAssertFalse(kept.removed, "kept locally with the marker")

        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 11)) }
        _ = await client.syncNow()
        XCTAssertEqual(StubURLProtocol.requests("POST").count, 0, "a rejected row is never retried")
    }

    func testDeltaUpsertsByIdAndADeletedRowGoesAway() async throws {
        try await pairAsAnne()
        StubURLProtocol.reset { _ in
            (200, listsSyncJSON(cursor: 20, wishlist: [
                wishlistJSON(id: "w-a", title: "Bigger TV", priceCents: 59900, seq: 19),
                wishlistJSON(id: "w-b", title: "Gone", addedBy: "wes", seq: 20, deleted: true),
            ]))
        }
        let first = await client.syncNow()
        XCTAssertEqual(first, .synced(posted: 0, deleted: 0, received: 2))
        let a = try XCTUnwrap(try wishlistRow("w-a"))
        XCTAssertEqual(a.priceCents, 59900)
        XCTAssertEqual(a.addedBy, "anne")
        XCTAssertNotNil(a.syncedAt)
        let b = try XCTUnwrap(try wishlistRow("w-b"))
        XCTAssertTrue(b.removed)
        XCTAssertTrue(b.deleteSynced)
        XCTAssertEqual(try state().cursor, 20)

        StubURLProtocol.reset { _ in
            (200, listsSyncJSON(cursor: 21, wishlist: [
                wishlistJSON(id: "w-a", title: "Bigger TV", priceCents: 54999, bought: true, boughtBy: "wes", boughtAt: listStamp, seq: 21),
            ]))
        }
        _ = await client.syncNow()
        let updated = try XCTUnwrap(try wishlistRow("w-a"))
        XCTAssertEqual(updated.priceCents, 54999)
        XCTAssertTrue(updated.bought)
        XCTAssertEqual(updated.boughtBy, "wes")
        XCTAssertEqual(StubURLProtocol.requests("DELETE").count, 0, "a delta never echoes a DELETE")
    }
}
