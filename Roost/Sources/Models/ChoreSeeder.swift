// Loads data/chores.json (bundled as a resource, referenced from the repo, not copied) into ChoreRecord rows.
// Idempotent: existing rows are updated in place, rows missing from the file are marked retired,
// and SyncState.choresVersion tracks the file's `version`.
import Foundation
import SwiftData
import RoostCore

enum ChoreSeeder {
    enum SeedError: Error, CustomStringConvertible {
        case missingResource
        var description: String { "Roost: chores.json is not in the app bundle" }
    }

    static func bundledChoresURL(bundle: Bundle = .main) throws -> URL {
        guard let url = bundle.url(forResource: "chores", withExtension: "json") else { throw SeedError.missingResource }
        return url
    }

    /// Returns the number of active chores after seeding.
    @discardableResult
    static func seedIfNeeded(into context: ModelContext, from url: URL) throws -> Int {
        let list = try ChoreList.load(from: url)
        return try seed(list, into: context)
    }

    @discardableResult
    static func seed(_ list: ChoreList, into context: ModelContext) throws -> Int {
        let existing = try context.fetch(FetchDescriptor<ChoreRecord>())
        var byId = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        for (index, chore) in list.chores.enumerated() {
            if let record = byId.removeValue(forKey: chore.id) {
                record.apply(chore, sortOrder: index)
            } else {
                context.insert(ChoreRecord(chore, sortOrder: index))
            }
        }
        // Whatever is left in byId was not in the file this time.
        for orphan in byId.values { orphan.retired = true }

        let state = try syncState(in: context)
        state.choresVersion = list.version

        if context.hasChanges { try context.save() }
        return list.chores.count
    }

    /// The single SyncState row, created on first use.
    static func syncState(in context: ModelContext) throws -> SyncState {
        if let state = try context.fetch(FetchDescriptor<SyncState>()).first { return state }
        let state = SyncState()
        context.insert(state)
        return state
    }
}
