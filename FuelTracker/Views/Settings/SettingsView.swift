import SwiftUI

/// App settings. Currently the home for unit preferences; structured so future
/// preferences (default vehicle, first day of week, etc.) slot in as new
/// sections without a redesign.
struct SettingsView: View {
    @Environment(UnitSettings.self) private var unitSettings

    var body: some View {
        @Bindable var units = unitSettings

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
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environment(UnitSettings())
}
