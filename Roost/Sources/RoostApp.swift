import RoostDesign
import SwiftData
import SwiftUI

@main
struct RoostApp: App {
    let container: ModelContainer
    @State private var sync: SyncCoordinator

    init() {
        try? RoostFonts.register()
        let container = Self.openStore()
        self.container = container
        _sync = State(initialValue: SyncCoordinator(container: container))
        do {
            let seeded = try ChoreSeeder.seedIfNeeded(into: container.mainContext, from: ChoreSeeder.bundledChoresURL())
            print("Roost: seeded \(seeded) chores")
        } catch {
            fatalError("Roost: could not seed the chore list: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootGate()
                .environment(sync)
        }
        .modelContainer(container)
    }

    /// Opens the default store. If the on-disk schema cannot be migrated (pre-release builds change it freely),
    /// the store is discarded and rebuilt: chores re-seed from the bundle and completions come back from the server.
    private static func openStore() -> ModelContainer {
        do {
            return try ModelContainer(for: RoostSchema.schema)
        } catch {
            print("Roost: store failed to open (\(error)); rebuilding")
            let dir = URL.applicationSupportDirectory
            for name in ["default.store", "default.store-shm", "default.store-wal"] {
                try? FileManager.default.removeItem(at: dir.appending(path: name))
            }
            do {
                return try ModelContainer(for: RoostSchema.schema)
            } catch {
                fatalError("Roost: could not open the local store: \(error)")
            }
        }
    }
}
