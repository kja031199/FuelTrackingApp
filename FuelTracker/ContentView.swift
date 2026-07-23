import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @AppStorage("selectedVehicleID") private var selectedVehicleID: String = ""
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var showingOnboarding = false

    private var selectedVehicle: Vehicle? {
        vehicles.first { $0.id.uuidString == selectedVehicleID } ?? vehicles.first
    }

    var body: some View {
        TabView {
            DashboardView(
                selectedVehicle: selectedVehicle,
                vehicles: vehicles,
                selectedVehicleID: $selectedVehicleID
            )
            .tabItem {
                Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent")
            }

            FillUpsListView(
                selectedVehicle: selectedVehicle,
                vehicles: vehicles,
                selectedVehicleID: $selectedVehicleID
            )
            .tabItem {
                Label("Fill-Ups", systemImage: "fuelpump.fill")
            }

            VehiclesView(selectedVehicleID: $selectedVehicleID)
                .tabItem {
                    Label("Vehicles", systemImage: "car.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            WelcomeView {
                hasOnboarded = true
                showingOnboarding = false
            }
        }
        .task {
            // Decide once on launch, before iCloud sync might populate vehicles.
            if OnboardingGate.shouldOnboard(hasCompleted: hasOnboarded, vehicleCount: vehicles.count) {
                showingOnboarding = true
            }
        }
    }
}

/// Toolbar menu for switching between vehicles.
struct VehiclePickerMenu: View {
    let vehicles: [Vehicle]
    @Binding var selectedVehicleID: String
    let selectedVehicle: Vehicle?

    var body: some View {
        if vehicles.count > 1 {
            Menu {
                ForEach(vehicles) { vehicle in
                    Button {
                        selectedVehicleID = vehicle.id.uuidString
                    } label: {
                        if vehicle.id == selectedVehicle?.id {
                            Label(vehicle.name, systemImage: "checkmark")
                        } else {
                            Text(vehicle.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "car.fill")
                    Text(selectedVehicle?.name ?? "Vehicle")
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
        .environment(UnitSettings())
        .environment(PrivacySettings())
        .environment(AppLock(authenticator: BiometricAuthenticator()))
}
