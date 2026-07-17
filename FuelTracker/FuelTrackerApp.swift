import SwiftUI
import SwiftData

@main
struct FuelTrackerApp: App {
    var sharedModelContainer = ModelContainerFactory.makeShared()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
