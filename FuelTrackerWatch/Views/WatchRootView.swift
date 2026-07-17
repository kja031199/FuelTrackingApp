import SwiftUI
import SwiftData

/// Single scrolling screen: quick fill-up entry on top, then KPIs and charts.
struct WatchRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @AppStorage("watchSelectedVehicleID") private var selectedVehicleID: String = ""

    private var selectedVehicle: Vehicle? {
        vehicles.first { $0.id.uuidString == selectedVehicleID } ?? vehicles.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if vehicles.isEmpty {
                        noVehicleView
                    } else {
                        if vehicles.count > 1 {
                            Picker("Vehicle", selection: $selectedVehicleID) {
                                ForEach(vehicles) { vehicle in
                                    Text(vehicle.name).tag(vehicle.id.uuidString)
                                }
                            }
                            .pickerStyle(.navigationLink)
                        }

                        WatchFillUpForm(vehicle: selectedVehicle)

                        if let vehicle = selectedVehicle {
                            let statistics = FuelStatistics(entries: vehicle.fillUps)
                            if statistics.fillUpCount > 0 {
                                WatchKPISection(statistics: statistics)
                                WatchChartsSection(statistics: statistics)
                            }
                        }
                    }
                }
            }
            .navigationTitle("FuelTracker")
        }
        .onAppear {
            // Keep the stored selection valid after deletions or first sync.
            if selectedVehicleID.isEmpty, let first = vehicles.first {
                selectedVehicleID = first.id.uuidString
            }
        }
    }

    private var noVehicleView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No Vehicle Yet")
                .font(.headline)
            Text("Add one on your iPhone — it syncs here via iCloud — or create one now.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Create \u{201C}My Car\u{201D}") {
                let vehicle = Vehicle(name: "My Car")
                modelContext.insert(vehicle)
                selectedVehicleID = vehicle.id.uuidString
            }
        }
    }
}

#Preview {
    WatchRootView()
        .modelContainer(PreviewData.container)
}
