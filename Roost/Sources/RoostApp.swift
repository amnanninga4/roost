import RoostDesign
import SwiftData
import SwiftUI

@main
struct RoostApp: App {
    /// The two APNs callbacks and the notification-center delegate have no SwiftUI equivalent; this is the
    /// only UIKit in the app. See `Push/RoostAppDelegate.swift`.
    @UIApplicationDelegateAdaptor(RoostAppDelegate.self) private var appDelegate

    let container: ModelContainer
    @State private var sync: SyncCoordinator
    @Environment(\.scenePhase) private var scenePhase
    /// Gear → Settings → Appearance, stored on this phone and nowhere else. The raw value rather than the
    /// enum, so a string this build does not know reads as `.system` instead of taking the screen with it;
    /// `Appearance.stored` is that read. See Models/Appearance.swift.
    @AppStorage(Appearance.storageKey) private var storedAppearance = Appearance.system.rawValue

    init() {
        try? RoostFonts.register()
        #if DEBUG
            // `-roostUITestState <name>`: an in-memory store with a fixed set of records and no server to
            // reach. See Sources/Debug/UITestSeed.swift. Nothing below runs in that case — the fixture has
            // already seeded its own chores, and the on-disk store is left alone.
            if let seed = UITestSeed.current {
                let container = seed.makeContainer()
                self.container = container
                _sync = State(initialValue: SyncCoordinator(container: container, tokenStore: seed.tokenStore))
                return
            }
        #endif
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
                // One override for the whole window, which is the only place it can go: the Settings sheet
                // and Kitchen mode's full-screen cover are presented from inside it, so they turn over in
                // the same frame as the screen behind them. `nil` hands the decision back to iOS.
                .preferredColorScheme(Appearance.stored(storedAppearance).colorScheme)
                // Launch and every return to the front: ask APNs for this phone's address again, because a
                // token can rotate and there is no notification when it does. `PushService` only sends one
                // the server does not already have.
                .task { await sync.registerForPushIfAllowed() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await sync.registerForPushIfAllowed() }
                }
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
