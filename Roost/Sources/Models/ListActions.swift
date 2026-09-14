// Every local write the list screens make, in one place: write to the store first, flag what the server
// has to hear about, save. The screens call these and then `SyncCoordinator.syncSoon()`. Tests call them
// too, so a check-off in a test is the same check-off a tap makes.
//
// Ids are client-generated UUIDs (they fit the server's id pattern); `person` is the paired person's raw
// value, or nil on an unpaired phone (the server stamps `addedBy` / `boughtBy` / `doneBy` from the token
// anyway, so local stamps are only a preview).
import Foundation
import SwiftData

enum ListActions {
    // MARK: shopping

    @discardableResult
    static func addShoppingItem(_ title: String, by person: String?, in context: ModelContext,
                                now: Date = Date()) throws -> ShoppingItemRecord?
    {
        guard let title = cleaned(title) else { return nil }
        let item = ShoppingItemRecord(id: newId(), title: title, addedBy: person ?? "", createdAt: now)
        context.insert(item)
        try context.save()
        return item
    }

    static func setBought(
        _ item: ShoppingItemRecord,
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

    /// Rename a row (long-press → Edit). A blank title is refused — the field keeps what was typed —
    /// and a no-op edit flags nothing.
    static func renameShoppingItem(
        _ item: ShoppingItemRecord, to title: String, in context: ModelContext, now: Date = Date()
    ) throws {
        guard let title = cleaned(title), title != item.title else { return }
        item.title = title
        item.markEdited(.title, at: now)
        try context.save()
    }

    static func removeShoppingItem(_ item: ShoppingItemRecord, in context: ModelContext, now: Date = Date()) throws {
        item.markRemoved(at: now)
        try context.save()
    }

    /// Everything already ticked, removed in one go. Returns the rows so the undo bar can put them back.
    @discardableResult
    static func clearBought(in context: ModelContext, now: Date = Date()) throws -> [ShoppingItemRecord] {
        let ticked = try context.fetch(FetchDescriptor<ShoppingItemRecord>(
            predicate: #Predicate { $0.bought && !$0.removed }
        ))
        for item in ticked {
            item.markRemoved(at: now)
        }
        try context.save()
        return ticked
    }

    /// Undo of `removeShoppingItem`. Returns the row that is now on the list: the same one when the
    /// DELETE never left the phone, a fresh copy when the server has already been told.
    @discardableResult
    static func restoreShoppingItem(
        _ item: ShoppingItemRecord, in context: ModelContext, now: Date = Date()
    ) throws -> ShoppingItemRecord {
        guard item.deleteReachedServer else {
            item.unremove(at: now)
            try context.save()
            return item
        }
        let copy = ShoppingItemRecord(
            id: newId(),
            title: item.title,
            addedBy: item.addedBy,
            bought: item.bought,
            boughtBy: item.boughtBy,
            boughtAt: item.boughtAt,
            createdAt: item.createdAt,
            updatedAt: now
        )
        // The create carries only id and title, so a ticked row needs `bought` sent after it.
        if copy.bought {
            copy.pendingFields = .bought
        }
        context.insert(copy)
        try context.save()
        return copy
    }


    // MARK: meals

    @discardableResult
    static func addMeal(_ title: String, tag: String, in context: ModelContext,
                        now: Date = Date()) throws -> MealRecord?
    {
        guard let title = cleaned(title) else { return nil }
        let meal = MealRecord(id: newId(), title: title, tag: cleaned(tag, limit: tagLimit) ?? "", createdAt: now)
        context.insert(meal)
        try context.save()
        return meal
    }

    /// Exclusive: turning it on turns it off everywhere else locally. Those rows are not flagged; the
    /// server clears them itself when the PATCH lands and the delta confirms it.
    static func setNextUp(_ meal: MealRecord, _ isOn: Bool, in context: ModelContext, now: Date = Date()) throws {
        if isOn {
            for other in try context
                .fetch(FetchDescriptor<MealRecord>(predicate: #Predicate { $0.nextUp && !$0.removed }))
                where other.id != meal.id
            {
                other.nextUp = false
            }
        }
        meal.nextUp = isOn
        meal.markEdited(.nextUp, at: now)
        try context.save()
    }

    static func madeToday(_ meal: MealRecord, in context: ModelContext, now: Date = Date()) throws {
        meal.lastMadeAt = now
        meal.markEdited(.lastMadeAt, at: now)
        try context.save()
    }

    static func removeMeal(_ meal: MealRecord, in context: ModelContext, now: Date = Date()) throws {
        meal.markRemoved(at: now)
        try context.save()
    }

    /// Undo of `removeMeal`. A meal's create carries every field, so the copy needs nothing flagged.
    @discardableResult
    static func restoreMeal(_ meal: MealRecord, in context: ModelContext, now: Date = Date()) throws -> MealRecord {
        guard meal.deleteReachedServer else {
            meal.unremove(at: now)
            try context.save()
            return meal
        }
        let copy = MealRecord(
            id: newId(),
            title: meal.title,
            tag: meal.tag,
            lastMadeAt: meal.lastMadeAt,
            nextUp: meal.nextUp,
            createdAt: meal.createdAt,
            updatedAt: now
        )
        context.insert(copy)
        try context.save()
        return copy
    }

    // MARK: projects

    /// `steps` become the first subtasks, in order, with `sortOrder` 0..n. Blank lines are skipped, and
    /// only as many as the server takes on a create are kept.
    @discardableResult
    static func startProject(_ title: String, steps: [String] = [], in context: ModelContext,
                             now: Date = Date()) throws -> ProjectRecord?
    {
        guard let title = cleaned(title) else { return nil }
        let project = ProjectRecord(id: newId(), title: title, createdAt: now)
        context.insert(project)
        let firstSteps = steps.compactMap { cleaned($0) }.prefix(firstStepsLimit)
        for (index, step) in firstSteps.enumerated() {
            context.insert(SubtaskRecord(
                id: newId(),
                projectId: project.id,
                title: step,
                sortOrder: index,
                createdAt: now
            ))
        }
        try context.save()
        return project
    }

    /// `dueOn` is a Chicago calendar day ("2026-09-20"), or nil to clear the day.
    static func setDueOn(_ project: ProjectRecord, _ dueOn: String?, in context: ModelContext, now: Date = Date()) throws {
        project.dueOn = dueOn
        project.markEdited(.dueOn, at: now)
        try context.save()
    }

    /// Appends after the project's highest live step, the same default the server uses. An owner given
    /// here is flagged as an edit as well: a step that rides its project's create goes out without it,
    /// and the flag is what sends it after.
    @discardableResult
    static func addSubtask(_ title: String, to project: ProjectRecord, assignee: String? = nil,
                           in context: ModelContext, now: Date = Date()) throws -> SubtaskRecord?
    {
        guard let title = cleaned(title) else { return nil }
        let siblings = try liveSubtasks(of: project.id, in: context)
        let next = (siblings.map(\.sortOrder).max() ?? -1) + 1
        let subtask = SubtaskRecord(
            id: newId(), projectId: project.id, title: title, sortOrder: next, assignee: assignee, createdAt: now
        )
        if assignee != nil {
            subtask.pendingFields = .assignee
        }
        context.insert(subtask)
        try context.save()
        return subtask
    }

    /// `anne`, `wes`, or nil for nobody.
    static func setAssignee(_ subtask: SubtaskRecord, _ person: String?, in context: ModelContext,
                            now: Date = Date()) throws
    {
        subtask.assignee = person
        subtask.markEdited(.assignee, at: now)
        try context.save()
    }

    static func setDone(
        _ subtask: SubtaskRecord,
        _ done: Bool,
        by person: String?,
        in context: ModelContext,
        now: Date = Date()
    ) throws {
        subtask.done = done
        subtask.doneBy = done ? person : nil
        subtask.doneAt = done ? now : nil
        subtask.markEdited(.done, at: now)
        try context.save()
    }

    static func removeSubtask(_ subtask: SubtaskRecord, in context: ModelContext, now: Date = Date()) throws {
        subtask.markRemoved(at: now)
        try context.save()
    }

    /// Undo of `removeSubtask`. The copy keeps its place in the project; `done` is not part of a
    /// create, so a step that was ticked has it flagged for the PATCH that follows.
    @discardableResult
    static func restoreSubtask(
        _ subtask: SubtaskRecord, in context: ModelContext, now: Date = Date()
    ) throws -> SubtaskRecord {
        guard subtask.deleteReachedServer else {
            subtask.unremove(at: now)
            try context.save()
            return subtask
        }
        let copy = SubtaskRecord(
            id: newId(),
            projectId: subtask.projectId,
            title: subtask.title,
            sortOrder: subtask.sortOrder,
            assignee: subtask.assignee,
            done: subtask.done,
            doneBy: subtask.doneBy,
            doneAt: subtask.doneAt,
            createdAt: subtask.createdAt,
            updatedAt: now
        )
        var pending: PatchFields = []
        if copy.done {
            pending.insert(.done)
        }
        if copy.assignee != nil {
            pending.insert(.assignee)
        }
        copy.pendingFields = pending
        context.insert(copy)
        try context.save()
        return copy
    }

    /// Applies a drag: `SubtaskOrder` decides the new `sortOrder` values and this writes them,
    /// flagging only the rows that actually moved. Returns how many rows will be PATCHed.
    @discardableResult
    static func reorderSubtasks(
        of project: ProjectRecord,
        move source: IndexSet,
        to destination: Int,
        in context: ModelContext,
        now: Date = Date()
    ) throws -> Int {
        let steps = try liveSubtasks(of: project.id, in: context)
        let rows = steps.map { (id: $0.id, sortOrder: $0.sortOrder) }
        let changes = SubtaskOrder.plan(rows: rows, move: source, to: destination)
        guard !changes.isEmpty else { return 0 }
        let byId = Dictionary(uniqueKeysWithValues: steps.map { ($0.id, $0) })
        for change in changes {
            guard let step = byId[change.id] else { continue }
            step.sortOrder = change.sortOrder
            step.markEdited(.sortOrder, at: now)
        }
        try context.save()
        return changes.count
    }

    /// Removes the project and every live step under it. One DELETE (the project's) covers the steps:
    /// the server cascades, so the steps are acknowledged here and never sent on their own.
    ///
    /// Returns the steps it cascaded, so an undo puts back exactly those and not a step that had
    /// already been deleted on its own.
    @discardableResult
    static func removeProject(
        _ project: ProjectRecord, in context: ModelContext, now: Date = Date()
    ) throws -> [SubtaskRecord] {
        let cascaded = try liveSubtasks(of: project.id, in: context)
        for subtask in cascaded {
            subtask.removed = true
            subtask.deleteSynced = true
            subtask.updatedAt = now
        }
        project.markRemoved(at: now)
        try context.save()
        return cascaded
    }

    /// Undo of `removeProject`, with the steps that call cascaded. When the DELETE never left the
    /// phone the project and those steps simply come back; when it did, the server cascaded for good,
    /// so a fresh project and a fresh copy of each step go out as new creates.
    @discardableResult
    static func restoreProject(
        _ project: ProjectRecord, steps: [SubtaskRecord], in context: ModelContext, now: Date = Date()
    ) throws -> ProjectRecord {
        guard project.deleteReachedServer else {
            project.unremove(at: now)
            for step in steps {
                step.unremove(at: now)
            }
            try context.save()
            return project
        }
        let copy = ProjectRecord(id: newId(), title: project.title, dueOn: project.dueOn, createdAt: project.createdAt, updatedAt: now)
        // A create does not carry the day, so flag it for the PATCH that follows.
        if copy.dueOn != nil {
            copy.pendingFields = .dueOn
        }
        context.insert(copy)
        for step in steps.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let stepCopy = SubtaskRecord(
                id: newId(),
                projectId: copy.id,
                title: step.title,
                sortOrder: step.sortOrder,
                assignee: step.assignee,
                done: step.done,
                doneBy: step.doneBy,
                doneAt: step.doneAt,
                createdAt: step.createdAt,
                updatedAt: now
            )
            // A create carries the step's title and its place, but not whether it is ticked or who owns it.
            var pending: PatchFields = []
            if stepCopy.done {
                pending.insert(.done)
            }
            if stepCopy.assignee != nil {
                pending.insert(.assignee)
            }
            stepCopy.pendingFields = pending
            context.insert(stepCopy)
        }
        try context.save()
        return copy
    }

    static func liveSubtasks(of projectId: String, in context: ModelContext) throws -> [SubtaskRecord] {
        try context.fetch(FetchDescriptor<SubtaskRecord>(
            predicate: #Predicate { $0.projectId == projectId && !$0.removed },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
    }

    // MARK: helpers

    /// The server's limits (server/src/app.js): a title is 1–200 characters, a tag at most 40, and a
    /// create takes at most 100 steps. Text is cut here rather than rejected there.
    static let titleLimit = 200
    static let tagLimit = 40
    static let firstStepsLimit = 100

    static func newId() -> String {
        UUID().uuidString
    }

    /// Trimmed, nil when blank, cut to `limit` characters.
    static func cleaned(_ text: String, limit: Int = titleLimit) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(limit))
    }
}
