import SwiftData

/// Single place both apps build their SwiftData container from.
enum ModelContainerFactory {
    static var schema: Schema {
        Schema([Vehicle.self, FuelEntry.self])
    }

    /// Syncs through the private CloudKit database of the container declared
    /// in the target's entitlements. If iCloud isn't available (no signing
    /// team, missing capability), falls back to a local-only store so the
    /// app still works — data just stays on this device.
    static func makeShared() -> ModelContainer {
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
    }

    /// In-memory container for previews and tests.
    static func makeInMemory() -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create in-memory ModelContainer: \(error)")
        }
    }
}
