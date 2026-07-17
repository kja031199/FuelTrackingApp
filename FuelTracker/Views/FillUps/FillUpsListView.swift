import SwiftUI
import SwiftData

/// Chronological history of fill-ups for the selected vehicle.
struct FillUpsListView: View {
    @Environment(\.modelContext) private var modelContext

    let selectedVehicle: Vehicle?
    let vehicles: [Vehicle]
    @Binding var selectedVehicleID: String

    @State private var showingAddSheet = false
    @State private var entryBeingEdited: FuelEntry?

    private var entries: [FuelEntry] {
        (selectedVehicle?.entries ?? []).sorted { $0.date > $1.date }
    }

    private var statistics: FuelStatistics {
        FuelStatistics(entries: selectedVehicle?.entries ?? [])
    }

    var body: some View {
        NavigationStack {
            Group {
                if selectedVehicle == nil {
                    ContentUnavailableView(
                        "No Vehicle Yet",
                        systemImage: "car",
                        description: Text("Add a vehicle in the Vehicles tab to start logging fill-ups.")
                    )
                } else if entries.isEmpty {
                    ContentUnavailableView {
                        Label("No Fill-Ups Yet", systemImage: "fuelpump")
                    } description: {
                        Text("Log your first fill-up to start tracking fuel economy and costs.")
                    } actions: {
                        Button("Log Fill-Up") { showingAddSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(entries) { entry in
                            Button {
                                entryBeingEdited = entry
                            } label: {
                                FillUpRow(entry: entry, mpg: statistics.mpg(for: entry))
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: deleteEntries)
                    }
                }
            }
            .navigationTitle("Fill-Ups")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VehiclePickerMenu(
                        vehicles: vehicles,
                        selectedVehicleID: $selectedVehicleID,
                        selectedVehicle: selectedVehicle
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(selectedVehicle == nil)
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddEditFillUpView(defaultVehicle: selectedVehicle)
            }
            .sheet(item: $entryBeingEdited) { entry in
                AddEditFillUpView(entry: entry)
            }
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        let toDelete = offsets.map { entries[$0] }
        for entry in toDelete {
            modelContext.delete(entry)
        }
    }
}

struct FillUpRow: View {
    let entry: FuelEntry
    let mpg: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.headline)
                Spacer()
                Text(Format.currency(entry.totalCost))
                    .font(.headline)
            }

            HStack(spacing: 12) {
                Label(
                    "\(Format.gallons(entry.gallons)) gal @ \(Format.fuelPrice(entry.pricePerGallon))",
                    systemImage: "fuelpump"
                )
                Spacer()
                Label("\(Format.odometer(entry.odometer)) mi", systemImage: "gauge.open.with.lines.needle.33percent")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if let mpg {
                    Text("\(Format.mpg(mpg)) MPG")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.blue.opacity(0.15), in: Capsule())
                        .foregroundStyle(.blue)
                }
                if !entry.isFullTank {
                    Text("Partial")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                if !entry.station.isEmpty {
                    Text(entry.station)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
