import SwiftUI
import SwiftData

@main
struct FuelTrackerApp: App {
    var sharedModelContainer = ModelContainerFactory.makeShared()
    @State private var unitSettings = UnitSettings()
    @State private var privacySettings = PrivacySettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(unitSettings)
                .environment(privacySettings)
        }
        .modelContainer(sharedModelContainer)
    }
}
