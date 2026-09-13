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

    static func removeShoppingItem(_ item: ShoppingItemRecord, in context: ModelContext, now: Date = Date()) throws {
        item.markRemoved(at: now)
        try context.save()
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

    /// Appends after the project's highest live step, the same default the server uses.
    @discardableResult
    static func addSubtask(_ title: String, to project: ProjectRecord, in context: ModelContext,
                           now: Date = Date()) throws -> SubtaskRecord?
    {
        guard let title = cleaned(title) else { return nil }
        let siblings = try liveSubtasks(of: project.id, in: context)
        let next = (siblings.map(\.sortOrder).max() ?? -1) + 1
        let subtask = SubtaskRecord(id: newId(), projectId: project.id, title: title, sortOrder: next, createdAt: now)
        context.insert(subtask)
        try context.save()
        return subtask
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

    /// Removes the project and every live step under it. One DELETE (the project's) covers the steps:
    /// the server cascades, so the steps are acknowledged here and never sent on their own.
    static func removeProject(_ project: ProjectRecord, in context: ModelContext, now: Date = Date()) throws {
        for subtask in try liveSubtasks(of: project.id, in: context) {
            subtask.removed = true
            subtask.deleteSynced = true
            subtask.updatedAt = now
        }
        project.markRemoved(at: now)
        try context.save()
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
