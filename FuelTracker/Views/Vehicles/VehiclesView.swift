import SwiftUI
import SwiftData

struct VehiclesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Binding var selectedVehicleID: String

    @State private var showingAddSheet = false
    @State private var vehicleBeingEdited: Vehicle?

    var body: some View {
        NavigationStack {
            Group {
                if vehicles.isEmpty {
                    ContentUnavailableView {
                        Label("No Vehicles", systemImage: "car")
                    } description: {
                        Text("Add your car to start tracking fill-ups, fuel economy, and costs.")
                    } actions: {
                        Button("Add Vehicle") { showingAddSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(vehicles) { vehicle in
                            Button {
                                vehicleBeingEdited = vehicle
                            } label: {
                                vehicleRow(vehicle)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: deleteVehicles)
                    }
                }
            }
            .navigationTitle("Vehicles")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddEditVehicleView()
            }
            .sheet(item: $vehicleBeingEdited) { vehicle in
                AddEditVehicleView(vehicle: vehicle)
            }
        }
    }

    private func vehicleRow(_ vehicle: Vehicle) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "car.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.name)
                    .font(.headline)
                if !vehicle.displaySubtitle.isEmpty {
                    Text(vehicle.displaySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(vehicle.fillUps.count) fill-up\(vehicle.fillUps.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if vehicle.id.uuidString == selectedVehicleID {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }

    private func deleteVehicles(at offsets: IndexSet) {
        for index in offsets {
            let vehicle = vehicles[index]
            if vehicle.id.uuidString == selectedVehicleID {
                selectedVehicleID = ""
            }
            modelContext.delete(vehicle)
        }
    }
}

struct AddEditVehicleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let vehicle: Vehicle?

    @State private var name = ""
    @State private var make = ""
    @State private var model = ""
    @State private var year = Calendar.current.component(.year, from: .now)

    init(vehicle: Vehicle? = nil) {
        self.vehicle = vehicle
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle") {
                    TextField("Nickname (e.g. Daily Driver)", text: $name)
                    TextField("Make (optional)", text: $make)
                    TextField("Model (optional)", text: $model)
                    Picker("Year", selection: $year) {
                        let currentYear = Calendar.current.component(.year, from: .now)
                        ForEach(((currentYear - 60)...(currentYear + 1)).reversed(), id: \.self) { y in
                            Text(String(y)).tag(y)
                        }
                    }
                }
            }
            .navigationTitle(vehicle == nil ? "New Vehicle" : "Edit Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if let vehicle {
                    name = vehicle.name
                    make = vehicle.make
                    model = vehicle.model
                    year = vehicle.year
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let vehicle {
            vehicle.name = trimmedName
            vehicle.make = make.trimmingCharacters(in: .whitespaces)
            vehicle.model = model.trimmingCharacters(in: .whitespaces)
            vehicle.year = year
        } else {
            let newVehicle = Vehicle(
                name: trimmedName,
                make: make.trimmingCharacters(in: .whitespaces),
                model: model.trimmingCharacters(in: .whitespaces),
                year: year
            )
            modelContext.insert(newVehicle)
        }
        dismiss()
    }
}

#Preview {
    VehiclesView(selectedVehicleID: .constant(""))
        .modelContainer(PreviewData.container)
}
