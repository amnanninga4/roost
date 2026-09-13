// The list half of a sync pass: shopping, meals, projects, subtasks. SyncClient.runOnce calls into here
// between its completion replay and the /sync pull, under the same policy:
//
//   replayLists()     POST every pending create (a project carries its pending steps in one request),
//                     PATCH every pending edit (only the flagged fields), DELETE every pending removal.
//                     2xx marks the row synced. 400, and 404 on a PATCH, mark it rejected: kept locally,
//                     never retried; a DELETE the server refuses is acknowledged the same way, and a 404
//                     there means already gone. 401 and a transport failure throw, with everything done so
//                     far saved. Anything else (429, 5xx, an unreadable reply) is one row's problem for one
//                     pass: logged, left queued, and the next row and the pull go ahead.
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

    /// What one outbound request did to its row.
    private enum Sent {
        /// The server has it (for a DELETE: confirms it is gone).
        case taken
        /// The server will never take it: marked, kept locally, never retried.
        case rejected
        /// No answer this pass; it stays queued for the next one.
        case deferred
    }

    // MARK: creates

    /// Projects go before their steps: a step's POST needs its project on the server. A 201 means the
    /// server built the row from the body, so the flags for the fields the body carried are cleared; a
    /// 200 replay ignored the body, so every flag stays and the edit goes out as a PATCH next.
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
            let sent = try await outbound(item) {
                let reply = try await api.postShopping(id: item.id, title: item.title)
                if reply.isNew {
                    item.pendingFields
                        .remove(.title) // a pending `bought` waits for the edits: the POST has no such field
                }
                item.apply(reply.row, now: now)
            }
            if sent == .taken {
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
            let sent = try await outbound(meal) {
                let reply = try await api.postMeal(
                    id: meal.id, title: meal.title, tag: meal.tag, lastMadeAt: meal.lastMadeAt, nextUp: meal.nextUp
                )
                if reply.isNew {
                    meal.pendingPatch = 0 // the create carried every field
                }
                meal.apply(reply.row, now: now)
            }
            if sent == .taken {
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
            let sent = try await outbound(project) {
                let reply = try await api.postProject(id: project.id, title: project.title, subtasks: seeds)
                if reply.isNew {
                    project.pendingFields.remove(.title)
                }
                project.apply(reply.row, now: now)
                let returned = Dictionary(uniqueKeysWithValues: (reply.row.subtasks ?? []).map { ($0.id, $0) })
                for step in steps {
                    guard let serverStep = returned[step.id] else { continue }
                    if reply.isNew {
                        step.pendingFields.subtract([.title, .sortOrder])
                    }
                    step.apply(serverStep, now: now)
                    stepsTaken += 1
                }
            }
            if sent == .taken {
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
            let sent = try await outbound(step) {
                let reply = try await api.postSubtask(
                    projectId: projectId, id: step.id, title: step.title, sortOrder: step.sortOrder
                )
                if reply.isNew {
                    step.pendingFields.subtract([.title, .sortOrder])
                }
                step.apply(reply.row, now: now)
            }
            if sent == .taken {
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
            let flagged = row.pendingFields
            let sent = try await outbound(row) {
                let dto = try await send(row)
                row.pendingFields.subtract(flagged)
                apply(row, dto)
            }
            if sent == .taken {
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
        var deleted = 0
        for row in rows {
            let sent = try await outboundDelete(row) { try await send(row) }
            if sent == .taken {
                deleted += 1
            }
        }
        return deleted
    }

    // MARK: one request

    /// One outbound POST or PATCH. 401 and a transport failure end the pass (saved up to here, queue
    /// intact): the token is dead, or nothing else would get through either. Any other 4xx means the
    /// server will never take this row: rejected, kept locally, never retried. Anything else (429, 5xx,
    /// an unreadable reply) is this row's problem for this pass: logged, left queued, and the rest of the
    /// pass, the pull included, goes ahead.
    private func outbound(_ record: some ListRecord, _ call: () async throws -> Void) async throws -> Sent {
        do {
            try await call()
            return .taken
        } catch let failure as SyncAPIError where failure.endsThePass {
            try modelContext.save()
            throw failure
        } catch let failure as SyncAPIError where failure.isTransient {
            deferRow(record, failure)
            return .deferred
        } catch let failure as SyncAPIError {
            print(
                "Roost: \(Self.name(of: record)) \(record.id) was refused (\(failure)); keeping it here, not retrying"
            )
            record.rejected = true
            record.pendingPatch = 0
            return .rejected
        }
    }

    /// One outbound DELETE, under the same rules. 404 counts as done: the row never reached the server,
    /// or is already gone there. A refusal (400) is acknowledged locally too: the row is already gone from
    /// the phone, and asking again would get the same answer.
    private func outboundDelete(_ record: some ListRecord, _ call: () async throws -> Void) async throws -> Sent {
        do {
            try await call()
        } catch let failure as SyncAPIError where failure == .notFound {
            // as good as deleted
        } catch let failure as SyncAPIError where failure.endsThePass {
            try modelContext.save()
            throw failure
        } catch let failure as SyncAPIError where failure.isTransient {
            deferRow(record, failure)
            return .deferred
        } catch let failure as SyncAPIError {
            print("Roost: DELETE of \(Self.name(of: record)) \(record.id) was refused (\(failure)); not retrying")
            record.rejected = true
            record.deleteSynced = true
            return .rejected
        }
        record.deleteSynced = true
        return .taken
    }

    private func deferRow(_ record: some ListRecord, _ failure: SyncAPIError) {
        print("Roost: \(Self.name(of: record)) \(record.id) stays queued for the next pass (\(failure))")
    }

    private static func name(of record: some ListRecord) -> String {
        String(describing: type(of: record))
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
