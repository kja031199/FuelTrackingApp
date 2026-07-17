import SwiftUI
import SwiftData

@main
struct FuelTrackerWatchApp: App {
    // Same iCloud container as the iPhone app, so fill-ups logged on the
    // watch sync to the phone and vice versa.
    var sharedModelContainer = ModelContainerFactory.makeShared()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
