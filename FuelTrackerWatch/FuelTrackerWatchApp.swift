import SwiftUI
import SwiftData

@main
struct FuelTrackerWatchApp: App {
    // Same iCloud container as the iPhone app, so fill-ups logged on the
    // watch sync to the phone and vice versa.
    var sharedModelContainer = ModelContainerFactory.makeShared()
    // The watch keeps its own unit preference in its local defaults; syncing it
    // with the phone would need a shared App Group (deferred with iCloud sync).
    @State private var unitSettings = UnitSettings()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(unitSettings)
        }
        .modelContainer(sharedModelContainer)
    }
}
