// How each list record meets its server row (ListSync.swift does the requests):
//
//   init(dto, now)   a row the phone has never seen, already synced
//   apply(dto, now)  the server's copy over ours, except fields with a local edit still pending
//   patchBody()      the PATCH body: only the flagged fields, so a stale copy of a field the other phone
//                    edited is never sent
//   noteServerSeq()  a delta row for something we are about to DELETE: remember the seq, keep the intent
import Foundation

extension ListRecord {
    /// A delta row for something we are about to DELETE: remember the seq, keep the local intent.
    func noteServerSeq(_ serverSeq: Int, now: Date) {
        seq = serverSeq
        syncedAt = syncedAt ?? now
    }

    /// The bookkeeping every server row carries.
    func markSynced(seq serverSeq: Int, deleted: Bool, updatedAt serverUpdatedAt: String, now: Date) {
        updatedAt = SyncAPI.parseDate(serverUpdatedAt) ?? updatedAt
        syncedAt = syncedAt ?? now
        seq = serverSeq
        rejected = false
        if deleted {
            removed = true
            deleteSynced = true
        }
    }
}

extension ShoppingItemRecord {
    convenience init(_ dto: SyncAPI.ShoppingDTO, now: Date) {
        self.init(
            id: dto.id,
            title: dto.title,
            addedBy: dto.addedBy,
            bought: dto.bought,
            boughtBy: dto.boughtBy,
            boughtAt: dto.boughtAt.flatMap(SyncAPI.parseDate),
            createdAt: SyncAPI.parseDate(dto.createdAt) ?? now,
            updatedAt: SyncAPI.parseDate(dto.updatedAt) ?? now,
            syncedAt: now,
            removed: dto.deleted
        )
        deleteSynced = dto.deleted
        seq = dto.seq
    }

    func apply(_ dto: SyncAPI.ShoppingDTO, now: Date) {
        let dirty = pendingFields
        if !dirty.contains(.title) {
            title = dto.title
        }
        if !dirty.contains(.bought) {
            bought = dto.bought
            boughtBy = dto.boughtBy
            boughtAt = dto.boughtAt.flatMap(SyncAPI.parseDate)
        }
        addedBy = dto.addedBy
        markSynced(seq: dto.seq, deleted: dto.deleted, updatedAt: dto.updatedAt, now: now)
    }

    func patchBody() -> SyncAPI.Fields {
        var body: SyncAPI.Fields = [:]
        if pendingFields.contains(.title) {
            body["title"] = .string(title)
        }
        if pendingFields.contains(.bought) {
            body["bought"] = .bool(bought)
        }
        return body
    }
}

extension MealRecord {
    convenience init(_ dto: SyncAPI.MealDTO, now: Date) {
        self.init(
            id: dto.id,
            title: dto.title,
            tag: dto.tag,
            lastMadeAt: dto.lastMadeAt.flatMap(SyncAPI.parseDate),
            nextUp: dto.nextUp,
            createdAt: SyncAPI.parseDate(dto.createdAt) ?? now,
            updatedAt: SyncAPI.parseDate(dto.updatedAt) ?? now,
            syncedAt: now,
            removed: dto.deleted
        )
        deleteSynced = dto.deleted
        seq = dto.seq
    }

    func apply(_ dto: SyncAPI.MealDTO, now: Date) {
        let dirty = pendingFields
        if !dirty.contains(.title) {
            title = dto.title
        }
        if !dirty.contains(.tag) {
            tag = dto.tag
        }
        if !dirty.contains(.lastMadeAt) {
            lastMadeAt = dto.lastMadeAt.flatMap(SyncAPI.parseDate)
        }
        if !dirty.contains(.nextUp) {
            nextUp = dto.nextUp
        }
        markSynced(seq: dto.seq, deleted: dto.deleted, updatedAt: dto.updatedAt, now: now)
    }

    func patchBody() -> SyncAPI.Fields {
        var body: SyncAPI.Fields = [:]
        if pendingFields.contains(.title) {
            body["title"] = .string(title)
        }
        if pendingFields.contains(.tag) {
            body["tag"] = .string(tag)
        }
        if pendingFields.contains(.lastMadeAt) {
            body["lastMadeAt"] = lastMadeAt.map { .string(SyncAPI.iso.string(from: $0)) } ?? .null
        }
        if pendingFields.contains(.nextUp) {
            body["nextUp"] = .bool(nextUp)
        }
        return body
    }
}

extension ProjectRecord {
    convenience init(_ dto: SyncAPI.ProjectDTO, now: Date) {
        self.init(
            id: dto.id,
            title: dto.title,
            createdAt: SyncAPI.parseDate(dto.createdAt) ?? now,
            updatedAt: SyncAPI.parseDate(dto.updatedAt) ?? now,
            syncedAt: now,
            removed: dto.deleted
        )
        deleteSynced = dto.deleted
        seq = dto.seq
    }

    func apply(_ dto: SyncAPI.ProjectDTO, now: Date) {
        if !pendingFields.contains(.title) {
            title = dto.title
        }
        markSynced(seq: dto.seq, deleted: dto.deleted, updatedAt: dto.updatedAt, now: now)
    }

    func patchBody() -> SyncAPI.Fields {
        var body: SyncAPI.Fields = [:]
        if pendingFields.contains(.title) {
            body["title"] = .string(title)
        }
        return body
    }
}

extension SubtaskRecord {
    convenience init(_ dto: SyncAPI.SubtaskDTO, now: Date) {
        self.init(
            id: dto.id,
            projectId: dto.projectId,
            title: dto.title,
            sortOrder: dto.sortOrder,
            done: dto.done,
            doneBy: dto.doneBy,
            doneAt: dto.doneAt.flatMap(SyncAPI.parseDate),
            createdAt: SyncAPI.parseDate(dto.createdAt) ?? now,
            updatedAt: SyncAPI.parseDate(dto.updatedAt) ?? now,
            syncedAt: now,
            removed: dto.deleted
        )
        deleteSynced = dto.deleted
        seq = dto.seq
    }

    func apply(_ dto: SyncAPI.SubtaskDTO, now: Date) {
        let dirty = pendingFields
        projectId = dto.projectId
        if !dirty.contains(.title) {
            title = dto.title
        }
        if !dirty.contains(.sortOrder) {
            sortOrder = dto.sortOrder
        }
        if !dirty.contains(.done) {
            done = dto.done
            doneBy = dto.doneBy
            doneAt = dto.doneAt.flatMap(SyncAPI.parseDate)
        }
        markSynced(seq: dto.seq, deleted: dto.deleted, updatedAt: dto.updatedAt, now: now)
    }

    func patchBody() -> SyncAPI.Fields {
        var body: SyncAPI.Fields = [:]
        if pendingFields.contains(.title) {
            body["title"] = .string(title)
        }
        if pendingFields.contains(.done) {
            body["done"] = .bool(done)
        }
        if pendingFields.contains(.sortOrder) {
            body["sortOrder"] = .int(sortOrder)
        }
        return body
    }
}
