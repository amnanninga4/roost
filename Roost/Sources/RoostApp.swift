import SwiftUI
import SwiftData
import RoostDesign

@main
struct RoostApp: App {
    let container: ModelContainer

    init() {
        try? RoostFonts.register()
        do {
            container = try ModelContainer(for: RoostSchema.schema)
            let seeded = try ChoreSeeder.seedIfNeeded(into: container.mainContext, from: ChoreSeeder.bundledChoresURL())
            print("Roost: seeded \(seeded) chores")
        } catch {
            fatalError("Roost: could not open the local store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ChoreListScreen()
        }
        .modelContainer(container)
    }
}
