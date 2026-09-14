// Shopping row rename craft test (task 15). Split out of ListCraftTests so swiftlint type_body_length
// stays under the limit.
@testable import Roost
import RoostCore
import SwiftData
import XCTest

@MainActor
final class ListRenameCraftTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext {
        container.mainContext
    }

    private let clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: RoostSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func testRenameFlagsOnlyTheTitleAndBlankIsRefused() throws {
        let item = ShoppingItemRecord(id: "s-1", title: "Oat milk", addedBy: "anne", createdAt: clock, syncedAt: clock)
        context.insert(item)
        try context.save()
        try ListActions.renameShoppingItem(item, to: "  Oat milk, barista  ", in: context, now: clock)
        XCTAssertEqual(item.title, "Oat milk, barista")
        XCTAssertEqual(item.pendingFields, [.title])
        try ListActions.renameShoppingItem(item, to: "   ", in: context, now: clock)
        XCTAssertEqual(item.title, "Oat milk, barista", "a blank edit is refused; the row keeps its name")
        try ListActions.renameShoppingItem(item, to: "Oat milk, barista", in: context, now: clock)
        XCTAssertEqual(item.pendingFields, [.title], "a no-op edit flags nothing new")
    }
}
