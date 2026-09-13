// The list half of a sync pass: shopping, meals, projects, subtasks. SyncClient.runOnce calls into here
// between its completion replay and the /sync pull, under the same policy:
//
//   replayLists()     POST every pending create (a project carries its pending steps in one request),
//                     PATCH every pending edit (only the flagged fields), DELETE every pending removal.
//                     2xx marks the row synced; 400/404 marks it rejected and it is never retried; 401
//                     and transport/5xx throw with everything done so far saved, so the queue survives.
//   applyListDelta()  upsert every row of the delta by id, honoring `deleted`. A row with a pending
//                     DELETE keeps its local intent until the DELETE replays; a row with a pending edit
//                     keeps its own flagged fields and takes the rest from the server.
//
// How a record takes a server row and what it sends in a PATCH is in ListSync+Records.swift.
import Foundation
import SwiftData

struct ListSyncStats: Equatable, Sendable {
    /// Creates and edits sent (POST and PATCH).
    var posted = 0
    var deleted = 0
}

extension SyncClient {
    // MARK: outbound

    func replayLists(api: SyncAPI, now: Date) async throws -> ListSyncStats {
        var stats = ListSyncStats()
        stats.posted += try await replayCreates(api: api, now: now)
        stats.posted += try await replayEdits(api: api, now: now)
        stats.deleted += try await replayRemovals(api: api, now: now)
        try modelContext.save()
        return stats
    }

    // MARK: creates

    /// Projects go before their steps: a step's POST needs its project on the server.
    private func replayCreates(api: SyncAPI, now: Date) async throws -> Int {
        var posted = 0
        posted += try await postShoppingItems(api: api, now: now)
        posted += try await postMeals(api: api, now: now)
        posted += try await postProjects(api: api, now: now)
        posted += try await postSubtasks(api: api, now: now)
        return posted
    }

    private func postShoppingItems(api: SyncAPI, now: Date) async throws -> Int {
        let items = try fetch(
            #Predicate<ShoppingItemRecord> { $0.syncedAt == nil && !$0.rejected && !$0.removed },
            sort: [SortDescriptor(\.createdAt)]
        )
        var posted = 0
        for item in items {
            let taken = try await outbound(item) {
                let dto = try await api.postShopping(id: item.id, title: item.title)
                item.pendingFields.remove(.title) // the POST carried the title; a pending `bought` waits for the edits
                item.apply(dto, now: now)
            }
            if taken {
                posted += 1
            }
        }
        return posted
    }

    private func postMeals(api: SyncAPI, now: Date) async throws -> Int {
        let meals = try fetch(
            #Predicate<MealRecord> { $0.syncedAt == nil && !$0.rejected && !$0.removed },
            sort: [SortDescriptor(\.createdAt)]
        )
        var posted = 0
        for meal in meals {
            let taken = try await outbound(meal) {
                let dto = try await api.postMeal(
                    id: meal.id, title: meal.title, tag: meal.tag, lastMadeAt: meal.lastMadeAt, nextUp: meal.nextUp
                )
                meal.pendingPatch = 0 // the POST carries every field
                meal.apply(dto, now: now)
            }
            if taken {
                posted += 1
            }
        }
        return posted
    }

    /// One POST per project, carrying every step still pending. A 200 replay ignores steps the server has
    /// not seen; those stay pending and go through POST /projects/:id/subtasks in `postSubtasks`.
    private func postProjects(api: SyncAPI, now: Date) async throws -> Int {
        let projects = try fetch(
            #Predicate<ProjectRecord> { $0.syncedAt == nil && !$0.rejected && !$0.removed },
            sort: [SortDescriptor(\.createdAt)]
        )
        var posted = 0
        for project in projects {
            let steps = try pendingSteps(of: project.id)
            let seeds = steps.map { SyncAPI.SubtaskSeed(id: $0.id, title: $0.title) }
            var stepsTaken = 0
            let taken = try await outbound(project) {
                let dto = try await api.postProject(id: project.id, title: project.title, subtasks: seeds)
                project.pendingFields.remove(.title)
                project.apply(dto, now: now)
                let returned = Dictionary(uniqueKeysWithValues: (dto.subtasks ?? []).map { ($0.id, $0) })
                for step in steps {
                    guard let serverStep = returned[step.id] else { continue }
                    step.pendingFields.subtract([.title, .sortOrder])
                    step.apply(serverStep, now: now)
                    stepsTaken += 1
                }
            }
            if taken {
                posted += 1 + stepsTaken
            }
        }
        return posted
    }

    private func pendingSteps(of projectId: String) throws -> [SubtaskRecord] {
        let pending = #Predicate<SubtaskRecord> {
            $0.projectId == projectId && $0.syncedAt == nil && !$0.rejected && !$0.removed
        }
        let order: [SortDescriptor<SubtaskRecord>] = [
            SortDescriptor(\SubtaskRecord.sortOrder),
            SortDescriptor(\SubtaskRecord.createdAt),
        ]
        return try fetch(pending, sort: order)
    }

    /// Steps added to a project the server already has, or left over from a 200 replay of the project.
    private func postSubtasks(api: SyncAPI, now: Date) async throws -> Int {
        let steps = try fetch(
            #Predicate<SubtaskRecord> { $0.syncedAt == nil && !$0.rejected && !$0.removed },
            sort: [SortDescriptor(\.createdAt)]
        )
        var posted = 0
        for step in steps {
            let projectId = step.projectId
            guard let project = try fetchOne(#Predicate<ProjectRecord> { $0.id == projectId }), !project.rejected else {
                step.rejected = true // its project will never exist on the server
                continue
            }
            guard project.syncedAt != nil, !project.removed else { continue } // waits for the project, or goes with it
            let taken = try await outbound(step) {
                let dto = try await api.postSubtask(
                    projectId: projectId, id: step.id, title: step.title, sortOrder: step.sortOrder
                )
                step.pendingFields.subtract([.title, .sortOrder])
                step.apply(dto, now: now)
            }
            if taken {
                posted += 1
            }
        }
        return posted
    }

    // MARK: edits

    /// Only the flagged fields, oldest edit first. Success clears the flags that went out and applies the reply.
    private func replayEdits(api: SyncAPI, now: Date) async throws -> Int {
        let items = try fetch(
            #Predicate<ShoppingItemRecord> {
                $0.syncedAt != nil && $0.pendingPatch != 0 && !$0.rejected && !$0.removed
            },
            sort: [SortDescriptor(\.updatedAt)]
        )
        let meals = try fetch(
            #Predicate<MealRecord> { $0.syncedAt != nil && $0.pendingPatch != 0 && !$0.rejected && !$0.removed },
            sort: [SortDescriptor(\.updatedAt)]
        )
        let projects = try fetch(
            #Predicate<ProjectRecord> { $0.syncedAt != nil && $0.pendingPatch != 0 && !$0.rejected && !$0.removed },
            sort: [SortDescriptor(\.updatedAt)]
        )
        let steps = try fetch(
            #Predicate<SubtaskRecord> { $0.syncedAt != nil && $0.pendingPatch != 0 && !$0.rejected && !$0.removed },
            sort: [SortDescriptor(\.updatedAt)]
        )
        var posted = 0
        posted += try await patch(items) { try await api.patchShopping(id: $0.id, $0.patchBody()) }
            apply: { $0.apply($1, now: now) }
        posted += try await patch(meals) { try await api.patchMeal(id: $0.id, $0.patchBody()) }
            apply: { $0.apply($1, now: now) }
        posted += try await patch(projects) { try await api.patchProject(id: $0.id, $0.patchBody()) }
            apply: { $0.apply($1, now: now) }
        posted += try await patch(steps) { try await api.patchSubtask(id: $0.id, $0.patchBody()) }
            apply: { $0.apply($1, now: now) }
        return posted
    }

    /// PATCHes each row and returns how many the server took.
    private func patch<Row: ListRecord, DTO>(
        _ rows: [Row], _ send: (Row) async throws -> DTO, apply: (Row, DTO) -> Void
    ) async throws -> Int {
        var posted = 0
        for row in rows {
            let sent = row.pendingFields
            let taken = try await outbound(row) {
                let dto = try await send(row)
                row.pendingFields.subtract(sent)
                apply(row, dto)
            }
            if taken {
                posted += 1
            }
        }
        return posted
    }

    // MARK: removals

    /// Steps removed on their own go first. A removed project's steps were acknowledged locally
    /// (ListActions.removeProject) because the server cascades, so only the project is sent and the
    /// cascade's seqs come back on the reply.
    private func replayRemovals(api: SyncAPI, now: Date) async throws -> Int {
        let steps = try fetch(
            #Predicate<SubtaskRecord> { $0.removed && !$0.deleteSynced }, sort: [SortDescriptor(\.updatedAt)]
        )
        let projects = try fetch(
            #Predicate<ProjectRecord> { $0.removed && !$0.deleteSynced }, sort: [SortDescriptor(\.updatedAt)]
        )
        let items = try fetch(
            #Predicate<ShoppingItemRecord> { $0.removed && !$0.deleteSynced }, sort: [SortDescriptor(\.updatedAt)]
        )
        let meals = try fetch(
            #Predicate<MealRecord> { $0.removed && !$0.deleteSynced }, sort: [SortDescriptor(\.updatedAt)]
        )
        var deleted = 0
        deleted += try await remove(steps) { _ = try await api.deleteSubtask(id: $0.id) }
        deleted += try await remove(projects) { project in
            let dto = try await api.deleteProject(id: project.id)
            project.seq = dto.seq
            for serverStep in dto.subtasks ?? [] {
                let stepId = serverStep.id
                try fetchOne(#Predicate<SubtaskRecord> { $0.id == stepId })?.apply(serverStep, now: now)
            }
        }
        deleted += try await remove(items) { _ = try await api.deleteShopping(id: $0.id) }
        deleted += try await remove(meals) { _ = try await api.deleteMeal(id: $0.id) }
        return deleted
    }

    /// DELETEs each row and returns how many are now gone on the server.
    private func remove<Row: ListRecord>(_ rows: [Row], _ send: (Row) async throws -> Void) async throws -> Int {
        for row in rows {
            try await outboundDelete(row) { try await send(row) }
        }
        return rows.count
    }

    // MARK: one request

    /// One outbound POST or PATCH under the completions rules. True when the server took it. 401 throws;
    /// any other 4xx marks the row rejected (kept locally, never retried); transport/5xx saves what has
    /// been done so far and throws, so the caller ends the pass with the queue intact.
    private func outbound(_ record: some ListRecord, _ call: () async throws -> Void) async throws -> Bool {
        do {
            try await call()
            return true
        } catch let failure as SyncAPIError where failure == .unauthorized {
            throw failure
        } catch let failure as SyncAPIError where !failure.isTransient {
            record.rejected = true
            record.pendingPatch = 0
            return false
        } catch let failure as SyncAPIError {
            try modelContext.save()
            throw failure
        }
    }

    /// One outbound DELETE. 200 and 404 both mean the row is gone on the server.
    private func outboundDelete(_ record: some ListRecord, _ call: () async throws -> Void) async throws {
        do {
            try await call()
        } catch let failure as SyncAPIError where failure == .notFound {
            // never reached the server, or already deleted there
        } catch let failure as SyncAPIError where failure == .unauthorized {
            throw failure
        } catch let failure as SyncAPIError {
            try modelContext.save()
            throw failure
        }
        record.deleteSynced = true
    }

    // MARK: inbound

    /// Upserts every row of the delta by id. Returns the number of list rows applied.
    func applyListDelta(_ response: SyncAPI.SyncResponse, now: Date) throws -> Int {
        for dto in response.shopping ?? [] {
            let id = dto.id
            try upsert(fetchOne(#Predicate<ShoppingItemRecord> { $0.id == id }), seq: dto.seq, now: now) {
                ShoppingItemRecord(dto, now: now)
            } apply: { $0.apply(dto, now: now) }
        }
        for dto in response.meals ?? [] {
            let id = dto.id
            try upsert(fetchOne(#Predicate<MealRecord> { $0.id == id }), seq: dto.seq, now: now) {
                MealRecord(dto, now: now)
            } apply: { $0.apply(dto, now: now) }
            if dto.nextUp, !dto.deleted {
                try clearNextUp(except: id)
            }
        }
        for dto in response.projects ?? [] {
            let id = dto.id
            try upsert(fetchOne(#Predicate<ProjectRecord> { $0.id == id }), seq: dto.seq, now: now) {
                ProjectRecord(dto, now: now)
            } apply: { $0.apply(dto, now: now) }
        }
        for dto in response.subtasks ?? [] {
            let id = dto.id
            try upsert(fetchOne(#Predicate<SubtaskRecord> { $0.id == id }), seq: dto.seq, now: now) {
                SubtaskRecord(dto, now: now)
            } apply: { $0.apply(dto, now: now) }
        }
        let counts = [
            response.shopping?.count,
            response.meals?.count,
            response.projects?.count,
            response.subtasks?.count,
        ]
        return counts.compactMap(\.self).reduce(0, +)
    }

    /// One delta row against the store: an unknown id is inserted; a row with a pending DELETE keeps its
    /// local intent and only notes the seq; anything else takes the server's fields, minus pending edits.
    private func upsert<Row: ListRecord & PersistentModel>(
        _ existing: Row?, seq: Int, now: Date, insert: () -> Row, apply: (Row) -> Void
    ) {
        guard let existing else {
            modelContext.insert(insert())
            return
        }
        if existing.needsDelete {
            existing.noteServerSeq(seq, now: now)
        } else {
            apply(existing)
        }
    }

    /// The server keeps `nextUp` on one meal at most; mirror that locally, leaving a pending local edit alone.
    private func clearNextUp(except id: String) throws {
        let others = try fetch(#Predicate<MealRecord> { $0.nextUp && $0.id != id }, sort: [])
        for other in others where !other.pendingFields.contains(.nextUp) {
            other.nextUp = false
        }
    }

    // MARK: fetch helpers

    private func fetch<R: PersistentModel>(_ predicate: Predicate<R>, sort: [SortDescriptor<R>]) throws -> [R] {
        try modelContext.fetch(FetchDescriptor<R>(predicate: predicate, sortBy: sort))
    }

    private func fetchOne<R: PersistentModel>(_ predicate: Predicate<R>) throws -> R? {
        var descriptor = FetchDescriptor<R>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
