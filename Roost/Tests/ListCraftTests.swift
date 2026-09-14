// The logic D-3 added to the three list tabs, without a simulator: the bought split, the undo window
// (and what it leaves in the sync queue), the sortOrder a drag implies, the finished-project
// condition, and how a "last made" date reads. The sync-queue half is in ListUndoSyncTests below,
// which drives real passes against the stub server.
@testable import Roost
import RoostCore
import SwiftData
import XCTest

@MainActor
final class ListCraftTests: XCTestCase {
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

    // MARK: the bought split

    func testUnboughtRowsComeFirstAndBoughtSinkMostRecentFirst() {
        let bread = ShoppingItemRecord(id: "a", title: "Bread", addedBy: "anne", createdAt: clock)
        let milk = ShoppingItemRecord(id: "b", title: "Milk", addedBy: "anne", createdAt: clock)
        let eggs = ShoppingItemRecord(id: "c", title: "Eggs", addedBy: "wes", createdAt: clock)
        milk.bought = true
        milk.boughtAt = clock
        eggs.bought = true
        eggs.boughtAt = clock.addingTimeInterval(60) // ticked later, so it sits on top of the section

        // The screen's @Query hands them over newest first; the split keeps that order in `toBuy`.
        let split = ShoppingSplit(rows: [bread, milk, eggs], isBought: \.bought, boughtAt: \.boughtAt)
        XCTAssertEqual(split.toBuy.map(\.title), ["Bread"])
        XCTAssertEqual(split.bought.map(\.title), ["Eggs", "Milk"])
        XCTAssertEqual(split.boughtCount, 2)
        XCTAssertEqual(split.total, 3)
    }

    func testABoughtRowWithNoStampStillSortsIntoTheBoughtSection() {
        let noStamp = ShoppingItemRecord(id: "a", title: "Rice", addedBy: "", bought: true, createdAt: clock)
        let stamped = ShoppingItemRecord(id: "b", title: "Beans", addedBy: "", bought: true, createdAt: clock)
        stamped.boughtAt = clock
        let split = ShoppingSplit(rows: [noStamp, stamped], isBought: \.bought, boughtAt: \.boughtAt)
        XCTAssertEqual(split.toBuy.count, 0)
        XCTAssertEqual(split.bought.map(\.title), ["Beans", "Rice"], "a missing stamp sorts oldest")
    }

    // MARK: undo — what the store looks like afterwards

    func testUndoOfARowTheServerNeverSawPutsBackTheSameRowAsAPendingCreate() throws {
        let item = try XCTUnwrap(try ListActions.addShoppingItem("Bread", by: "anne", in: context, now: clock))
        try ListActions.removeShoppingItem(item, in: context, now: clock)
        XCTAssertTrue(item.removed)
        XCTAssertTrue(item.deleteSynced, "nothing to tell the server: it never had the row")
        XCTAssertFalse(item.needsDelete)

        let back = try ListActions.restoreShoppingItem(item, in: context, now: clock)
        XCTAssertIdentical(back, item, "the same row, not a copy")
        XCTAssertFalse(back.removed)
        XCTAssertFalse(back.deleteSynced)
        XCTAssertTrue(back.needsPost)
        XCTAssertFalse(back.needsDelete)
        XCTAssertEqual(try liveItems().count, 1)
    }

    func testUndoOfAQueuedDeleteLeavesASyncedRowWithItsPendingEditIntact() throws {
        let item = ShoppingItemRecord(id: "sh-1", title: "Milk", addedBy: "anne", createdAt: clock, syncedAt: clock)
        context.insert(item)
        try ListActions.setBought(item, true, by: "anne", in: context, now: clock)
        try ListActions.removeShoppingItem(item, in: context, now: clock)
        XCTAssertTrue(item.needsDelete, "the DELETE is queued and has not gone out")

        let back = try ListActions.restoreShoppingItem(item, in: context, now: clock)
        XCTAssertIdentical(back, item)
        XCTAssertFalse(back.needsDelete)
        XCTAssertTrue(back.needsPatch, "the bought edit still has to reach the server")
        XCTAssertEqual(back.pendingFields, .bought)
        XCTAssertEqual(try liveItems().count, 1)
    }

    func testUndoAfterTheDeleteWentOutCreatesAFreshRowAndKeepsTheTombstone() throws {
        let item = ShoppingItemRecord(
            id: "sh-1", title: "Eggs", addedBy: "wes", bought: true, boughtBy: "wes", boughtAt: clock,
            createdAt: clock, syncedAt: clock
        )
        context.insert(item)
        try ListActions.removeShoppingItem(item, in: context, now: clock)
        item.deleteSynced = true // the pass ran: the server has soft-deleted its row for good

        let copy = try ListActions.restoreShoppingItem(item, in: context, now: clock)
        XCTAssertFalse(copy === item, "a new row, because the server will not un-delete the old one")
        XCTAssertNotEqual(copy.id, item.id)
        XCTAssertEqual(copy.title, "Eggs")
        XCTAssertEqual(copy.createdAt, item.createdAt, "it goes back where it was in the list")
        XCTAssertTrue(copy.needsPost)
        XCTAssertEqual(copy.pendingFields, .bought, "a create carries no bought flag, so it follows as a PATCH")
        XCTAssertTrue(item.removed, "the old row stays removed and acknowledged")
        XCTAssertTrue(item.deleteSynced)
        XCTAssertFalse(item.needsDelete, "no second DELETE for a row already gone")
        XCTAssertEqual(try liveItems().map(\.title), ["Eggs"], "one row on the list, not two")
    }

    func testUndoOfAnUnboughtRowNeedsNoFollowUpPatch() throws {
        let item = ShoppingItemRecord(id: "sh-1", title: "Rice", addedBy: "wes", createdAt: clock, syncedAt: clock)
        context.insert(item)
        try ListActions.removeShoppingItem(item, in: context, now: clock)
        item.deleteSynced = true

        let copy = try ListActions.restoreShoppingItem(item, in: context, now: clock)
        XCTAssertEqual(copy.pendingPatch, 0)
        XCTAssertTrue(copy.needsPost)
    }

    func testClearBoughtRemovesEveryTickedRowAndUndoBringsThemAllBack() throws {
        let bread = try XCTUnwrap(try ListActions.addShoppingItem("Bread", by: "anne", in: context, now: clock))
        let milk = try XCTUnwrap(try ListActions.addShoppingItem("Milk", by: "anne", in: context, now: clock))
        let eggs = try XCTUnwrap(try ListActions.addShoppingItem("Eggs", by: "wes", in: context, now: clock))
        try ListActions.setBought(milk, true, by: "anne", in: context, now: clock)
        try ListActions.setBought(eggs, true, by: "wes", in: context, now: clock)

        let cleared = try ListActions.clearBought(in: context, now: clock)
        XCTAssertEqual(Set(cleared.map(\.title)), ["Milk", "Eggs"])
        XCTAssertEqual(try liveItems().map(\.title), ["Bread"])
        XCTAssertFalse(bread.removed, "what is still needed is left alone")

        for item in cleared {
            _ = try ListActions.restoreShoppingItem(item, in: context, now: clock)
        }
        XCTAssertEqual(try Set(liveItems().map(\.title)), ["Bread", "Milk", "Eggs"])
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


    func testUndoOfAMealCarriesEveryFieldSoNothingFollowsTheCreate() throws {
        let meal = MealRecord(
            id: "me-1", title: "Tacos", tag: "Weeknight", lastMadeAt: clock, nextUp: true,
            createdAt: clock, syncedAt: clock
        )
        context.insert(meal)
        try ListActions.removeMeal(meal, in: context, now: clock)
        meal.deleteSynced = true

        let copy = try ListActions.restoreMeal(meal, in: context, now: clock)
        XCTAssertNotEqual(copy.id, meal.id)
        XCTAssertEqual(copy.tag, "Weeknight")
        XCTAssertEqual(copy.lastMadeAt, clock)
        XCTAssertTrue(copy.nextUp)
        XCTAssertEqual(copy.pendingPatch, 0, "a meal's create carries the lot")
        XCTAssertTrue(copy.needsPost)
    }

    func testUndoOfATickedStepFlagsDoneForThePatchThatFollows() throws {
        let project = try XCTUnwrap(try ListActions.startProject("Garage", steps: ["Sort"], in: context, now: clock))
        project.syncedAt = clock
        let step = try XCTUnwrap(try ListActions.liveSubtasks(of: project.id, in: context).first)
        step.syncedAt = clock
        try ListActions.setDone(step, true, by: "wes", in: context, now: clock)
        step.pendingPatch = 0 // the tick has already been acknowledged
        try ListActions.removeSubtask(step, in: context, now: clock)
        step.deleteSynced = true

        let copy = try ListActions.restoreSubtask(step, in: context, now: clock)
        XCTAssertNotEqual(copy.id, step.id)
        XCTAssertEqual(copy.projectId, project.id)
        XCTAssertEqual(copy.sortOrder, step.sortOrder)
        XCTAssertTrue(copy.done)
        XCTAssertEqual(copy.pendingFields, .done)
        XCTAssertTrue(copy.needsPost)
    }

    func testUndoOfAProjectPutsBackOnlyTheStepsThatCallRemoved() throws {
        let project = try XCTUnwrap(
            try ListActions.startProject("Garage", steps: ["Sort", "Shelves"], in: context, now: clock)
        )
        let steps = try ListActions.liveSubtasks(of: project.id, in: context)
        let alreadyGone = try XCTUnwrap(steps.first)
        try ListActions.removeSubtask(alreadyGone, in: context, now: clock)

        let cascaded = try ListActions.removeProject(project, in: context, now: clock)
        XCTAssertEqual(cascaded.map(\.title), ["Shelves"], "the step that was already deleted is not cascaded")

        _ = try ListActions.restoreProject(project, steps: cascaded, in: context, now: clock)
        XCTAssertFalse(project.removed)
        XCTAssertEqual(try ListActions.liveSubtasks(of: project.id, in: context).map(\.title), ["Shelves"])
    }

    func testUndoOfAProjectTheServerAlreadyDeletedRebuildsItWithNewIds() throws {
        let project = try XCTUnwrap(
            try ListActions.startProject("Garage", steps: ["Sort", "Shelves"], in: context, now: clock)
        )
        project.syncedAt = clock
        let steps = try ListActions.liveSubtasks(of: project.id, in: context)
        for step in steps {
            step.syncedAt = clock
        }
        let cascaded = try ListActions.removeProject(project, in: context, now: clock)
        project.deleteSynced = true // the pass ran: the server cascaded the project and its steps

        let copy = try ListActions.restoreProject(project, steps: cascaded, in: context, now: clock)
        XCTAssertNotEqual(copy.id, project.id)
        XCTAssertTrue(copy.needsPost)
        let rebuilt = try ListActions.liveSubtasks(of: copy.id, in: context)
        XCTAssertEqual(rebuilt.map(\.title), ["Sort", "Shelves"], "in order")
        XCTAssertTrue(rebuilt.allSatisfy(\.needsPost))
        XCTAssertTrue(try ListActions.liveSubtasks(of: project.id, in: context).isEmpty)
    }

    // MARK: sortOrder

    func testAMoveIntoAGapChangesOnlyTheRowThatMoved() {
        let rows = [(id: "a", sortOrder: 0), (id: "b", sortOrder: 32), (id: "c", sortOrder: 64)]
        // Drag "c" between "a" and "b": there is room at 16, so nothing else is touched.
        let changes = SubtaskOrder.plan(rows: rows, move: [2], to: 1)
        XCTAssertEqual(changes, [SubtaskOrder.Change(id: "c", sortOrder: 16)])
    }

    func testAMoveToTheEndTakesTheNextStride() {
        let rows = [(id: "a", sortOrder: 0), (id: "b", sortOrder: 1), (id: "c", sortOrder: 2)]
        let changes = SubtaskOrder.plan(rows: rows, move: [0], to: 3)
        XCTAssertEqual(changes, [SubtaskOrder.Change(id: "a", sortOrder: 2 + SubtaskOrder.stride)])
    }

    func testAMoveToTheFrontHalvesTheFirstNumberWhenThereIsRoom() {
        let rows = [(id: "a", sortOrder: 16), (id: "b", sortOrder: 32)]
        let changes = SubtaskOrder.plan(rows: rows, move: [1], to: 0)
        XCTAssertEqual(changes, [SubtaskOrder.Change(id: "b", sortOrder: 8)])
    }

    func testAMoveWithNoRoomRenumbersOnTheStrideAndLeavesTheRowsThatAlreadyFit() {
        let rows = [(id: "a", sortOrder: 0), (id: "b", sortOrder: 1), (id: "c", sortOrder: 2)]
        // Drag "c" to the front: 0 has nothing under it, so the whole list is renumbered.
        let changes = SubtaskOrder.plan(rows: rows, move: [2], to: 0)
        XCTAssertEqual(changes, [
            SubtaskOrder.Change(id: "c", sortOrder: 0),
            SubtaskOrder.Change(id: "a", sortOrder: SubtaskOrder.stride),
            SubtaskOrder.Change(id: "b", sortOrder: SubtaskOrder.stride * 2),
        ])
        XCTAssertFalse(changes.contains { $0.id == "c" && $0.sortOrder != 0 })
    }

    func testARenumberedListIsStrictlyIncreasingAndInsideTheServersRange() {
        let rows = (0 ..< 8).map { (id: "s\($0)", sortOrder: $0) }
        let changes = SubtaskOrder.plan(rows: rows, move: [7], to: 0)
        var applied = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.sortOrder) })
        for change in changes {
            applied[change.id] = change.sortOrder
        }
        var expected = rows
        expected.move(fromOffsets: [7], toOffset: 0)
        let values = expected.map { applied[$0.id] ?? -1 }
        XCTAssertEqual(values, values.sorted(), "the new numbers put the rows in the dragged order")
        XCTAssertEqual(Set(values).count, values.count, "no two steps share a number")
        XCTAssertTrue(values.allSatisfy { $0 >= 0 && $0 <= SubtaskOrder.maximum })
    }

    func testAMoveThatChangesNothingSendsNothing() {
        let rows = [(id: "a", sortOrder: 0), (id: "b", sortOrder: 16)]
        XCTAssertEqual(SubtaskOrder.plan(rows: rows, move: [0], to: 0), [])
        XCTAssertEqual(SubtaskOrder.plan(rows: rows, move: [1], to: 2), [])
    }

    func testReorderWritesTheNewNumbersAndFlagsOnlyTheRowsThatMoved() throws {
        let project = try XCTUnwrap(
            try ListActions.startProject("Garage", steps: ["Sort", "Shelves", "Paint"], in: context, now: clock)
        )
        let before = try ListActions.liveSubtasks(of: project.id, in: context)
        for step in before {
            step.syncedAt = clock
            step.pendingPatch = 0
        }
        try context.save()

        // Drag "Paint" to the front. 0, 1, 2 has no gaps, so all three are renumbered.
        let changed = try ListActions.reorderSubtasks(of: project, move: [2], to: 0, in: context, now: clock)
        XCTAssertEqual(changed, 3)
        let after = try ListActions.liveSubtasks(of: project.id, in: context)
        XCTAssertEqual(after.map(\.title), ["Paint", "Sort", "Shelves"])
        XCTAssertTrue(after.allSatisfy { $0.pendingFields == .sortOrder })
        XCTAssertTrue(after.allSatisfy(\.needsPatch))

        // Now there are gaps, so the next drag is one row and one request.
        let again = try ListActions.reorderSubtasks(of: project, move: [2], to: 1, in: context, now: clock)
        XCTAssertEqual(again, 1)
        XCTAssertEqual(
            try ListActions.liveSubtasks(of: project.id, in: context).map(\.title), ["Paint", "Shelves", "Sort"]
        )
    }

    // MARK: the finished card

    func testAProjectIsFinishedOnlyWhenItHasStepsAndEveryOneIsDone() {
        XCTAssertFalse(ProjectProgress(done: 0, total: 0).isFinished, "a project with no steps is empty, not done")
        XCTAssertFalse(ProjectProgress(done: 1, total: 2).isFinished)
        XCTAssertTrue(ProjectProgress(done: 2, total: 2).isFinished)
        XCTAssertTrue(ProjectProgress(done: 1, total: 1).isFinished)
    }

    func testProgressFractionIsSafeWithNoSteps() {
        XCTAssertEqual(ProjectProgress(done: 0, total: 0).fraction, 0)
        XCTAssertEqual(ProjectProgress(done: 1, total: 4).fraction, 0.25)
        XCTAssertEqual(ProjectProgress(done: 4, total: 4).fraction, 1)
    }

    func testTickingTheLastStepFinishesTheCard() throws {
        let project = try XCTUnwrap(
            try ListActions.startProject("Garage", steps: ["Sort", "Shelves"], in: context, now: clock)
        )
        let steps = try ListActions.liveSubtasks(of: project.id, in: context)
        try ListActions.setDone(steps[0], true, by: "anne", in: context, now: clock)
        var progress = try ProjectProgress(
            steps: ListActions.liveSubtasks(of: project.id, in: context), isDone: \.done
        )
        XCTAssertFalse(progress.isFinished)

        try ListActions.setDone(steps[1], true, by: "wes", in: context, now: clock)
        progress = try ProjectProgress(steps: ListActions.liveSubtasks(of: project.id, in: context), isDone: \.done)
        XCTAssertTrue(progress.isFinished)
        XCTAssertEqual(progress.done, 2)

        // Deleting the last undone step also finishes it: the condition is about what is left.
        let third = try XCTUnwrap(try ListActions.addSubtask("Paint", to: project, in: context, now: clock))
        XCTAssertFalse(
            try ProjectProgress(steps: ListActions.liveSubtasks(of: project.id, in: context), isDone: \.done)
                .isFinished
        )
        try ListActions.removeSubtask(third, in: context, now: clock)
        XCTAssertTrue(
            try ProjectProgress(steps: ListActions.liveSubtasks(of: project.id, in: context), isDone: \.done)
                .isFinished
        )
    }

    // MARK: "last made"

    func testLastMadeReadsAsAWordThenAWeekdayThenADate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        // Wednesday 2026-09-16, 18:00 Chicago.
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 18)))
        let days: (Int) -> Date = { calendar.date(byAdding: .day, value: -$0, to: now)! }

        XCTAssertEqual(MealDates.lastMade(days(0), now: now, calendar: calendar), Strings.Meals.today)
        XCTAssertEqual(MealDates.lastMade(days(1), now: now, calendar: calendar), Strings.Meals.yesterday)
        XCTAssertEqual(MealDates.lastMade(days(2), now: now, calendar: calendar), "Monday")
        XCTAssertEqual(MealDates.lastMade(days(6), now: now, calendar: calendar), "Thursday")
        XCTAssertEqual(MealDates.lastMade(days(7), now: now, calendar: calendar), "Sep 9", "a week out gets a date")
        XCTAssertEqual(MealDates.lastMade(days(60), now: now, calendar: calendar), "Jul 18")
    }

    func testLastMadeIsTodayEvenWhenTheStampIsLaterInTheDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 6)))
        let later = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 22)))
        XCTAssertEqual(MealDates.lastMade(later, now: now, calendar: calendar), Strings.Meals.today)
    }

    // MARK: the undo window

    func testUndoInsideTheWindowRestoresAndNeverSendsTheRemoval() async throws {
        let undo = ListUndo(window: .milliseconds(60))
        var restored = 0
        var committed = 0
        undo.offer("Bread removed", restore: { restored += 1 }, commit: { committed += 1 })
        XCTAssertEqual(undo.message, "Bread removed")

        undo.undo()
        XCTAssertEqual(restored, 1)
        XCTAssertEqual(committed, 0, "the DELETE was held back, so there is nothing to send")
        XCTAssertNil(undo.message)

        // The expiry must not fire after an undo took the offer away.
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(committed, 0)
        XCTAssertEqual(restored, 1)
    }

    func testTheWindowClosingSendsTheRemovalExactlyOnce() async throws {
        let undo = ListUndo(window: .milliseconds(60))
        var restored = 0
        var committed = 0
        undo.offer("Bread removed", restore: { restored += 1 }, commit: { committed += 1 })

        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(committed, 1)
        XCTAssertEqual(restored, 0)
        XCTAssertNil(undo.message, "the bar is gone")

        undo.dismiss()
        XCTAssertEqual(committed, 1, "there is nothing left to commit")
    }

    func testASecondDeletionSendsTheFirstOneRatherThanLosingIt() {
        let undo = ListUndo(window: .milliseconds(500))
        var firstCommitted = 0
        var secondCommitted = 0
        var firstRestored = 0
        undo.offer("Bread removed", restore: { firstRestored += 1 }, commit: { firstCommitted += 1 })
        undo.offer("Milk removed", restore: {}, commit: { secondCommitted += 1 })

        XCTAssertEqual(firstCommitted, 1, "the older removal goes out when its bar is replaced")
        XCTAssertEqual(firstRestored, 0)
        XCTAssertEqual(secondCommitted, 0)
        XCTAssertEqual(undo.message, "Milk removed")

        undo.undo()
        XCTAssertEqual(secondCommitted, 0, "the one still on screen was taken back")
    }

    // MARK: a row the server refused

    func testRemovingARejectedRowSendsNothing() throws {
        let item = try XCTUnwrap(try ListActions.addShoppingItem("Bread", by: "anne", in: context, now: clock))
        item.rejected = true // the server said 400; the row stays on the phone, marked
        try ListActions.removeShoppingItem(item, in: context, now: clock)
        XCTAssertTrue(item.removed)
        XCTAssertFalse(item.needsDelete, "the server never had it, so there is nothing to delete there")
        XCTAssertFalse(item.needsPost)
    }

    // MARK: helpers

    private func liveItems() throws -> [ShoppingItemRecord] {
        try context.fetch(FetchDescriptor<ShoppingItemRecord>(
            predicate: #Predicate { !$0.removed }, sortBy: [SortDescriptor(\.createdAt)]
        ))
    }
}

/// The other half of undo: what a real sync pass does with the store the undo left behind.
final class ListUndoSyncTests: ListSyncTestCase {
    func testUndoBeforeTheDeleteGoesOutSendsNoDeleteAtAll() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let item = ShoppingItemRecord(id: "sh-1", title: "Bread", addedBy: "anne", createdAt: listClock)
        item.syncedAt = listClock
        item.seq = 5
        ctx.insert(item)
        try ctx.save()

        try ListActions.removeShoppingItem(item, in: ctx, now: listClock)
        _ = try ListActions.restoreShoppingItem(item, in: ctx, now: listClock)

        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 5)) }
        let outcome = await client.syncNow()
        XCTAssertEqual(outcome, .synced(posted: 0, deleted: 0, received: 0))
        XCTAssertEqual(StubURLProtocol.requests("DELETE").count, 0, "the removal never left the phone")
        XCTAssertEqual(StubURLProtocol.requests("POST").count, 0)
        let back = try XCTUnwrap(try shoppingRow("sh-1"))
        XCTAssertFalse(back.removed)
    }

    func testUndoAfterTheDeleteWentOutPostsTheCopyOnceAndNeverResendsTheDelete() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let item = ShoppingItemRecord(
            id: "sh-1", title: "Eggs", addedBy: "anne", bought: true, boughtBy: "anne", boughtAt: listClock,
            createdAt: listClock
        )
        item.syncedAt = listClock
        item.seq = 5
        ctx.insert(item)
        try ctx.save()
        try ListActions.removeShoppingItem(item, in: ctx, now: listClock)

        // Pass one: the DELETE goes out.
        StubURLProtocol.reset { req in
            if req.httpMethod == "DELETE" {
                return (200, json(shoppingJSON(id: "sh-1", title: "Eggs", seq: 6, deleted: true)))
            }
            return (200, listsSyncJSON(cursor: 6))
        }
        let deletePass = await client.syncNow()
        XCTAssertEqual(deletePass, .synced(posted: 0, deleted: 1, received: 0))
        XCTAssertEqual(StubURLProtocol.requests("DELETE").map(\.path), ["/shopping/sh-1"])

        // Undo now: the server row is gone for good, so a fresh row goes out as a create.
        let undoCtx = fresh()
        let tombstone = try XCTUnwrap(try shoppingRow("sh-1", in: undoCtx))
        XCTAssertTrue(tombstone.deleteReachedServer)
        let copy = try ListActions.restoreShoppingItem(tombstone, in: undoCtx, now: listClock)
        let copyId = copy.id

        StubURLProtocol.reset { req in
            if req.httpMethod == "POST" {
                return (201, json(shoppingJSON(id: copyId, title: "Eggs", seq: 7)))
            }
            if req.httpMethod == "PATCH" {
                return (200, json(shoppingJSON(id: copyId, title: "Eggs", bought: true, boughtBy: "anne",
                                               boughtAt: listStamp, seq: 8)))
            }
            return (200, listsSyncJSON(cursor: 8))
        }
        let createPass = await client.syncNow()
        XCTAssertEqual(createPass, .synced(posted: 2, deleted: 0, received: 0))
        XCTAssertEqual(StubURLProtocol.requests("POST").map(\.path), ["/shopping"])
        XCTAssertEqual(StubURLProtocol.requests("POST").first?.body?["id"] as? String, copyId)
        XCTAssertEqual(StubURLProtocol.requests("PATCH").first?.body?["bought"] as? Bool, true,
                       "the copy's bought flag follows the create")
        XCTAssertEqual(StubURLProtocol.requests("DELETE").count, 0, "the tombstone is not sent again")

        // Pass three: everything is settled, so nothing more goes out.
        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 8)) }
        let settledPass = await client.syncNow()
        XCTAssertEqual(settledPass, .synced(posted: 0, deleted: 0, received: 0))
        XCTAssertEqual(StubURLProtocol.requests("POST").count, 0)
        XCTAssertEqual(StubURLProtocol.requests("DELETE").count, 0)
        let live = try fresh().fetch(FetchDescriptor<ShoppingItemRecord>(predicate: #Predicate { !$0.removed }))
        XCTAssertEqual(live.map(\.id), [copyId], "one live row, the copy")
    }

    func testAReorderPatchesOnlyTheStepsThatMoved() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let project = ProjectRecord(id: "pr-1", title: "Garage", createdAt: listClock, syncedAt: listClock)
        ctx.insert(project)
        let titles = ["Sort", "Shelves", "Paint"]
        for (index, title) in titles.enumerated() {
            let step = SubtaskRecord(
                id: "st-\(index)", projectId: "pr-1", title: title, sortOrder: index * SubtaskOrder.stride,
                createdAt: listClock, syncedAt: listClock
            )
            step.seq = 5 + index
            ctx.insert(step)
        }
        try ctx.save()

        // 0, 16, 32 has room, so dragging the last step to the middle is one PATCH.
        let changed = try ListActions.reorderSubtasks(of: project, move: [2], to: 1, in: ctx, now: listClock)
        XCTAssertEqual(changed, 1)

        StubURLProtocol.reset { req in
            if req.httpMethod == "PATCH" {
                return (200, json(subtaskJSON(id: "st-2", projectId: "pr-1", title: "Paint", sortOrder: 8, seq: 9)))
            }
            return (200, listsSyncJSON(cursor: 9))
        }
        let reorderPass = await client.syncNow()
        XCTAssertEqual(reorderPass, .synced(posted: 1, deleted: 0, received: 0))
        let patches = StubURLProtocol.requests("PATCH")
        XCTAssertEqual(patches.map(\.path), ["/subtasks/st-2"])
        XCTAssertEqual(patches.first?.body?["sortOrder"] as? Int, 8)
        XCTAssertNil(patches.first?.body?["title"], "only the field that changed is sent")
        let moved = try XCTUnwrap(try subtaskRow("st-2"))
        XCTAssertEqual(moved.pendingPatch, 0)
        XCTAssertEqual(moved.sortOrder, 8)
    }

    // MARK: - Projects composer (Return on title)

    func testTitleReturnNeverClearsFirstSteps() {
        let blank = ProjectComposer.afterTitleReturn(title: "   ", steps: "Sort boxes\nSweep")
        XCTAssertEqual(blank.title, "")
        XCTAssertEqual(blank.steps, "Sort boxes\nSweep", "Return on a blank title must not discard steps")

        let kept = ProjectComposer.afterTitleReturn(title: "Garage", steps: "Sort boxes")
        XCTAssertEqual(kept.title, "Garage")
        XCTAssertEqual(kept.steps, "Sort boxes", "Return on a real title does not start and does not clear steps")
    }

    func testFirstStepsStayVisibleWhenOnlyStepsRemain() {
        XCTAssertTrue(ProjectComposer.showsFirstSteps(title: "Garage", steps: ""))
        XCTAssertTrue(ProjectComposer.showsFirstSteps(title: "", steps: "Sort"))
        XCTAssertTrue(ProjectComposer.showsFirstSteps(title: "  ", steps: "  Sort  "))
        XCTAssertFalse(ProjectComposer.showsFirstSteps(title: "", steps: ""))
        XCTAssertFalse(ProjectComposer.showsFirstSteps(title: "   ", steps: "\n"))
    }
}
