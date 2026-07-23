import SwiftUI
import SwiftData

@main
struct FuelTrackerApp: App {
    var sharedModelContainer = ModelContainerFactory.makeShared()
    @State private var unitSettings = UnitSettings()
    @State private var privacySettings = PrivacySettings()
    @State private var appLock = AppLock(authenticator: BiometricAuthenticator())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(unitSettings)
                .environment(privacySettings)
                .modifier(AppLockGate())
                // Applied outside the gate so the gate itself (and its lock
                // overlay) can read it, while it still flows into ContentView.
                .environment(appLock)
        }
        .modelContainer(sharedModelContainer)
    }
}
