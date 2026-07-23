import SwiftUI
import UIKit

/// App settings — the home for unit and privacy preferences. Structured so
/// future preferences slot in as new sections without a redesign.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(UnitSettings.self) private var unitSettings
    @Environment(PrivacySettings.self) private var privacySettings
    @Environment(AppLock.self) private var appLock

    @State private var showingPurgeConfirmation = false
    @State private var purgeResultMessage: String?

    var body: some View {
        @Bindable var units = unitSettings
        @Bindable var privacy = privacySettings
        @Bindable var lock = appLock

        NavigationStack {
            Form {
                Section {
                    Picker("Volume", selection: $units.volumeUnit) {
                        ForEach(VolumeUnit.allCases) { unit in
                            Text(unit.name).tag(unit)
                        }
                    }
                    Picker("Distance", selection: $units.distanceUnit) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.name).tag(unit)
                        }
                    }
                    Picker("Fuel Economy", selection: $units.economyUnit) {
                        ForEach(EconomyUnit.allCases) { unit in
                            Text("\(unit.name) (\(unit.abbreviation))").tag(unit)
                        }
                    }
                } header: {
                    Text("Units")
                } footer: {
                    Text("Choose how volume, distance, and fuel economy are shown. Your fill-ups are stored the same way regardless — changing units only changes how the numbers are displayed and entered.")
                }

                Section {
                    Toggle("Record Fill-Up Locations", isOn: $privacy.locationCaptureEnabled)

                    Button {
                        showingPurgeConfirmation = true
                    } label: {
                        Text("Remove All Saved Locations")
                            .foregroundStyle(.red)
                    }

                    Button("Open Location Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    Text("Location")
                } footer: {
                    Text("When on, logging a fill-up can save where it happened — with your permission — so the app can name the station. Turn it off to stop recording locations entirely; the app won't request or use your location. Removing saved locations clears the coordinates from fill-ups you've already logged, keeping the fill-ups themselves.")
                }

                Section {
                    Toggle("Require Face ID / Passcode", isOn: $lock.isEnabled)
                        .disabled(!appLock.canUseLock)
                } header: {
                    Text("Security")
                } footer: {
                    Text(appLock.canUseLock
                         ? "Require Face ID, Touch ID, or your device passcode to open FuelTracker. The app locks whenever it leaves the foreground."
                         : "Set up Face ID, Touch ID, or a passcode in the Settings app to use an app lock.")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Remove all saved locations?",
                isPresented: $showingPurgeConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove All Locations", role: .destructive) {
                    let count = LocationPrivacy.purgeSavedLocations(in: modelContext)
                    purgeResultMessage = count == 0
                        ? "There were no saved locations to remove."
                        : "Removed the saved location from \(count) fill-up\(count == 1 ? "" : "s")."
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears the saved coordinates from every fill-up. The fill-ups themselves are kept. This can't be undone.")
            }
            .alert(
                "Locations Removed",
                isPresented: Binding(
                    get: { purgeResultMessage != nil },
                    set: { if !$0 { purgeResultMessage = nil } }
                )
            ) {
                Button("OK") { purgeResultMessage = nil }
            } message: {
                Text(purgeResultMessage ?? "")
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(UnitSettings())
        .environment(PrivacySettings())
        .environment(AppLock(authenticator: BiometricAuthenticator()))
}
