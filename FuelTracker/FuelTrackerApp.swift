import SwiftUI
import SwiftData

@main
struct FuelTrackerApp: App {
    var sharedModelContainer = ModelContainerFactory.makeShared()
    @State private var unitSettings = UnitSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(unitSettings)
        }
        .modelContainer(sharedModelContainer)
    }
}
