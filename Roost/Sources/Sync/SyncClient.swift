// The sync policy, on its own actor with its own ModelContext.
//
// syncNow():  1. POST every completion that needs it (idempotent on id; 400 → rejected, never retried)
//             2. DELETE every soft-deleted completion the server has not acknowledged (404 counts as done)
//             3. replay the list queues the same way (ListSync.swift: POST creates, PATCH edits, DELETE removals)
//             4. GET /sync?cursor=&choresVersion= and apply the delta; store the new cursor
// Offline or 5xx is not an error: the queue stays and the next call retries. An in-flight guard makes
// overlapping callers coalesce into one extra pass, so "sync after every tap" never stampedes.
import Foundation
import RoostCore
import SwiftData

enum SyncOutcome: Equatable, Sendable {
    case synced(posted: Int, deleted: Int, received: Int)
    case unpaired
    case coalesced
    case failed(String)
}

@ModelActor
actor SyncClient {
    private var tokenStore: TokenStore = KeychainTokenStore()
    private var session: URLSession = .shared
    private var now: @Sendable () -> Date = { Date() }
    private var inFlight = false
    private var rerunRequested = false

    /// Test/preview hook. Call once, right after init.
    func configure(tokenStore: TokenStore, session: URLSession, now: @escaping @Sendable () -> Date = { Date() }) {
        self.tokenStore = tokenStore
        self.session = session
        self.now = now
    }

    // MARK: pairing

    /// Validates the token against the server, then stores it (Keychain) and the base URL + person (SyncState).
    /// Throws SyncAPIError on 401 / network failure; nothing is stored in that case.
    func pair(baseURL: URL, token: String) async throws -> Person {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let api = SyncAPI(baseURL: baseURL, token: trimmed, session: session)
        let state = try syncState()
        let response = try await api.sync(cursor: 0, choresVersion: state.choresVersion)
        guard let person = Person(rawValue: response.person) else {
            throw SyncAPIError.decoding("unknown person '\(response.person)'")
        }
        try tokenStore.write(trimmed)
        state.baseURL = baseURL.absoluteString
        state.person = person.rawValue
        try apply(response, to: state)
        try modelContext.save()
        return person
    }

    func unpair() throws {
        try tokenStore.clear()
        let state = try syncState()
        state.person = nil
        state.baseURL = nil
        try modelContext.save()
    }

    // MARK: sync

    func syncNow() async -> SyncOutcome {
        if inFlight {
            rerunRequested = true
            return .coalesced
        }
        inFlight = true
        defer { inFlight = false }
        var outcome = await runOnce()
        while rerunRequested {
            rerunRequested = false
            outcome = await runOnce()
        }
        return outcome
    }

    private func runOnce() async -> SyncOutcome {
        do {
            let state = try syncState()
            guard let base = state.baseURL.flatMap(URL.init(string:)), state.person != nil,
                  let token = try tokenStore.read() else { return .unpaired }
            let api = SyncAPI(baseURL: base, token: token, session: session)

            var posted = 0
            for record in try pendingPosts() {
                do {
                    let dto = try await api.post(
                        id: record.id,
                        choreId: record.choreId,
                        completedAt: record.completedAt
                    )
                    record.syncedAt = now()
                    record.seq = dto.seq
                    posted += 1
                } catch let e as SyncAPIError where e == .unauthorized {
                    throw e
                } catch let e as SyncAPIError where !e.isTransient {
                    record
                        .rejected = true // 400/404: the server will never take this row; keep it locally, stop retrying
                } catch let e as SyncAPIError {
                    try modelContext.save()
                    return .failed(e.description) // transient: leave the rest queued
                }
            }

            var deleted = 0
            for record in try pendingDeletes() {
                do {
                    _ = try await api.delete(id: record.id)
                    record.deleteSynced = true
                    deleted += 1
                } catch let e as SyncAPIError where e == .notFound {
                    record.deleteSynced = true // never reached the server; nothing to delete there
                    deleted += 1
                } catch let e as SyncAPIError where e == .unauthorized {
                    throw e
                } catch let e as SyncAPIError {
                    try modelContext.save()
                    return .failed(e.description)
                }
            }
            try modelContext.save()

            // Throws on 401 or a transport failure, queue intact; a row the server refuses or cannot take
            // right now does not stop the pass, so the pull below still runs.
            let lists = try await replayLists(api: api, now: now())
            posted += lists.posted
            deleted += lists.deleted

            let response = try await api.sync(cursor: state.cursor, choresVersion: state.choresVersion)
            let received = try apply(response, to: state)
            state.lastSyncAt = now()
            try modelContext.save()
            return .synced(posted: posted, deleted: deleted, received: received)
        } catch let e as SyncAPIError {
            return .failed(e.description)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: applying a /sync response

    /// Returns the number of rows applied (completions plus the list deltas).
    @discardableResult
    private func apply(_ response: SyncAPI.SyncResponse, to state: SyncState) throws -> Int {
        if let chores = response.chores {
            let list = ChoreList(version: response.choresVersion, chores: chores.compactMap { dto in
                guard let cadence = Cadence(rawValue: dto.cadence),
                      let category = ChoreCategory(rawValue: dto.category) else { return nil }
                return Chore(
                    id: dto.id,
                    title: dto.title,
                    cadence: cadence,
                    fixedAssignee: dto.fixedAssignee.flatMap(Person.init(rawValue:)),
                    category: category
                )
            })
            try ChoreSeeder.seed(list, into: modelContext)
        }

        var applied = 0
        for dto in response.completions {
            guard let completedAt = SyncAPI.parseDate(dto.completedAt) else { continue }
            let id = dto.id
            let existing = try modelContext
                .fetch(FetchDescriptor<CompletionRecord>(predicate: #Predicate { $0.id == id })).first
            if let existing {
                if existing.needsDelete {
                    // Our delete is still pending; local intent wins until the DELETE replays.
                    existing.seq = dto.seq
                    existing.syncedAt = existing.syncedAt ?? now()
                    continue
                }
                existing.choreId = dto.choreId
                existing.person = dto.person
                existing.completedAt = completedAt
                existing.syncedAt = existing.syncedAt ?? now()
                existing.seq = dto.seq
                existing.rejected = false
                if dto.deleted {
                    existing.removed = true
                    existing.deleteSynced = true
                }
            } else {
                let record = CompletionRecord(
                    id: dto.id,
                    choreId: dto.choreId,
                    person: dto.person,
                    completedAt: completedAt,
                    syncedAt: now(),
                    removed: dto.deleted
                )
                record.deleteSynced = dto.deleted
                record.seq = dto.seq
                modelContext.insert(record)
            }
            applied += 1
        }
        applied += try applyListDelta(response, now: now())
        state.cursor = max(state.cursor, response.cursor)
        state.choresVersion = response.choresVersion
        return applied
    }

    // MARK: fetches

    private func syncState() throws -> SyncState {
        try ChoreSeeder.syncState(in: modelContext)
    }

    private func pendingPosts() throws -> [CompletionRecord] {
        try modelContext.fetch(FetchDescriptor<CompletionRecord>(
            predicate: #Predicate { $0.syncedAt == nil && !$0.rejected && !$0.removed },
            sortBy: [SortDescriptor(\.completedAt)]
        ))
    }

    private func pendingDeletes() throws -> [CompletionRecord] {
        try modelContext.fetch(FetchDescriptor<CompletionRecord>(
            predicate: #Predicate { $0.removed && !$0.deleteSynced },
            sortBy: [SortDescriptor(\.completedAt)]
        ))
    }
}
