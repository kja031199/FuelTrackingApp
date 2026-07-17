import SwiftUI
import SwiftData

@main
struct FuelTrackerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Vehicle.self,
            FuelEntry.self,
        ])

        // Sync through the private CloudKit database of the container declared
        // in FuelTracker.entitlements. If iCloud isn't available (no signing
        // team, missing capability), fall back to a local-only store so the
        // app still works — data just stays on this device.
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
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
