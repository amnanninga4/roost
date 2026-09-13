// The handoff half of a sync pass. SyncClient.runOnce calls into here after the list replay and before
// the /sync pull, under the policy ListSync.swift already documents:
//
//   replayHandoffs()     POST every offer the phone has made and not sent (a client-generated UUID, so
//                        a replay is safe), then POST every accept or decline it owes. 2xx marks the row
//                        synced. 400, 403 and 409 are final for a handoff — "not the owner", "there is
//                        already an open offer", "that is not pending any more" are verdicts about the
//                        row, not a gateway saying no for now — so the row is kept locally, never
//                        retried, and the Tasks tab takes the change back. 401 and a transport failure
//                        end the pass with everything done so far saved. Anything else (429, 5xx, an
//                        unreadable reply) is one row's problem for one pass: left queued, and the next
//                        row and the pull still go ahead.
//   applyHandoffDelta()  upsert every row of the delta by id, honoring `deleted`. A row with an answer
//                        still queued keeps its local state until that answer goes out.
//
// A refused offer differs from a refused answer, and the difference matters to the planner. An offer the
// server refused never existed there, so `rejected` is exactly right and the row is left out of the live
// set. An answer the server refused is a row the server *does* have: dropping our answer and taking the
// server's own state back is the whole fix, and marking the row rejected would hide a handoff that is
// real from the scheduler. So an answer conflict clears `pendingAnswer` and applies the server's row.
import Foundation
import RoostCore
import SwiftData

extension SyncClient {
    // MARK: outbound

    /// Returns how many offers and answers the server took.
    func replayHandoffs(api: SyncAPI, now: Date) async throws -> Int {
        var sent = 0
        sent += try await postOffers(api: api, now: now)
        sent += try await postAnswers(api: api, now: now)
        try modelContext.save()
        return sent
    }

    /// Offers made on this phone that the server has not seen. Oldest first, so two offers queued
    /// offline reach the server in the order they were made and the second one gets the 409.
    private func postOffers(api: SyncAPI, now: Date) async throws -> Int {
        let offers = try handoffs(
            #Predicate<HandoffRecord> { $0.syncedAt == nil && !$0.rejected && !$0.removed },
            sort: [SortDescriptor(\.createdAt)]
        )
        var sent = 0
        for offer in offers {
            guard let to = Person(rawValue: offer.toPerson), let cadence = Cadence(rawValue: offer.cadence) else {
                offer.rejected = true // a row this build cannot describe; the server would only 400 it
                continue
            }
            let taken = try await outbound(offer, finalOn403: true) {
                let reply = try await api.postHandoff(
                    id: offer.id,
                    choreId: offer.choreId,
                    to: to,
                    periodIndex: offer.periodIndex,
                    cadence: cadence
                )
                offer.apply(reply.row, now: now)
            }
            if taken == .taken {
                sent += 1
            }
        }
        return sent
    }

    /// Accepts and declines this phone has made and not sent. The row already shows the answer, so a
    /// refusal is the one case that has to put something back on screen.
    ///
    /// A 409 and a 403 are both caught here rather than left to `outbound`, because the row they are
    /// about is a row the server *has*: the answer is dropped and never retried, and the row takes the
    /// server's own state. Marking it `rejected` — which is what `outbound` does with a final failure —
    /// would drop a real handoff out of the live set and leave the two phones disagreeing about who owes
    /// the chore. A 400 is not in the contract for these routes and falls through to that generic path.
    private func postAnswers(api: SyncAPI, now: Date) async throws -> Int {
        let pending = try handoffs(
            #Predicate<HandoffRecord> { $0.pendingAnswer != nil && !$0.removed && !$0.rejected },
            sort: [SortDescriptor(\.updatedAt)]
        )
        var sent = 0
        for row in pending {
            guard row.syncedAt != nil else { continue } // an offer of our own still queued; nothing to answer
            guard let decision = row.queuedAnswer else {
                row.pendingAnswer = nil
                continue
            }
            var answered = false
            _ = try await outbound(row) {
                do {
                    let dto = try await api.answerHandoff(id: row.id, decision)
                    row.applyAnswered(dto, now: now)
                    answered = true
                } catch let conflict as SyncAPI.HandoffConflict {
                    print("Roost: handoff \(row.id) answer refused (\(conflict.message)); taking the server's state")
                    row.pendingAnswer = nil
                    if let dto = conflict.handoff {
                        row.apply(dto, now: now)
                    }
                } catch SyncAPIError.forbidden {
                    print("Roost: handoff \(row.id) is not this phone's to answer; dropping the answer")
                    row.pendingAnswer = nil
                }
            }
            if answered {
                sent += 1
            }
        }
        return sent
    }

    // MARK: inbound

    /// Upserts every row of the handoff delta by id. Returns the number of rows applied.
    func applyHandoffDelta(_ response: SyncAPI.SyncResponse, now: Date) throws -> Int {
        let rows = response.handoffs ?? []
        for dto in rows {
            let id = dto.id
            let existing = try handoffs(#Predicate<HandoffRecord> { $0.id == id }, sort: []).first
            guard let existing else {
                modelContext.insert(HandoffRecord(dto, now: now))
                continue
            }
            existing.apply(dto, now: now)
        }
        return rows.count
    }

    private func handoffs(
        _ predicate: Predicate<HandoffRecord>, sort: [SortDescriptor<HandoffRecord>]
    ) throws -> [HandoffRecord] {
        try modelContext.fetch(FetchDescriptor<HandoffRecord>(predicate: predicate, sortBy: sort))
    }
}

extension HandoffRecord {
    convenience init(_ dto: SyncAPI.HandoffDTO, now: Date) {
        self.init(
            id: dto.id,
            choreId: dto.choreId,
            fromPerson: dto.from,
            toPerson: dto.to,
            periodIndex: dto.periodIndex,
            cadence: dto.cadence,
            state: dto.state,
            createdAt: SyncAPI.parseDate(dto.createdAt) ?? now,
            updatedAt: SyncAPI.parseDate(dto.updatedAt) ?? now,
            syncedAt: now,
            removed: dto.deleted
        )
        deleteSynced = dto.deleted
        seq = dto.seq
    }

    /// The server's copy over ours. `state` is the one field a local answer can be holding, so it is
    /// left alone until that answer has gone out — the same rule `pendingFields` follows on a list row.
    func apply(_ dto: SyncAPI.HandoffDTO, now: Date) {
        choreId = dto.choreId
        fromPerson = dto.from
        toPerson = dto.to
        periodIndex = dto.periodIndex
        cadence = dto.cadence
        if pendingAnswer == nil {
            state = dto.state
        }
        createdAt = SyncAPI.parseDate(dto.createdAt) ?? createdAt
        markSynced(seq: dto.seq, deleted: dto.deleted, updatedAt: dto.updatedAt, now: now)
    }

    /// The reply to an accept or decline the server took: the answer is no longer pending, so the row
    /// takes the state the server just wrote.
    func applyAnswered(_ dto: SyncAPI.HandoffDTO, now: Date) {
        pendingAnswer = nil
        apply(dto, now: now)
    }
}
