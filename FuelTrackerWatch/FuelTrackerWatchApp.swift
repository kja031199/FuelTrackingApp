import SwiftUI
import SwiftData

@main
struct FuelTrackerWatchApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Vehicle.self,
            FuelEntry.self,
        ])

        // Same iCloud container as the iPhone app, so fill-ups logged on the
        // watch sync to the phone and vice versa. Falls back to a local store
        // when iCloud isn't available.
        do {
            let cloudConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            return try ModelContainer(for: schema, configurations: [cloudConfiguration])
        } catch {
            print("iCloud sync unavailable, using local store: \(error)")
        }

        do {
            let localConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [localConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
