import SwiftUI
import SwiftData

/// Form for logging a new fill-up or editing an existing one.
/// Total cost is calculated live from gallons × price per gallon.
struct AddEditFillUpView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    /// Entry being edited, or nil when adding a new one.
    let entry: FuelEntry?
    let defaultVehicle: Vehicle?

    @State private var selectedVehicleID: UUID?
    @State private var date: Date = .now
    @State private var odometer: Double?
    @State private var gallons: Double?
    @State private var pricePerGallon: Double?
    @State private var isFullTank = true
    @State private var fuelGrade: FuelGrade = .regular
    @State private var station = ""
    @State private var notes = ""

    init(entry: FuelEntry? = nil, defaultVehicle: Vehicle? = nil) {
        self.entry = entry
        self.defaultVehicle = defaultVehicle
    }

    private var selectedVehicle: Vehicle? {
        vehicles.first { $0.id == selectedVehicleID }
    }

    private var totalCost: Double {
        (gallons ?? 0) * (pricePerGallon ?? 0)
    }

    /// Highest odometer already logged for the selected vehicle (new entries only).
    private var previousOdometer: Double? {
        guard entry == nil, let vehicle = selectedVehicle else { return nil }
        return vehicle.fillUps.map(\.odometer).max()
    }

    private var odometerLooksWrong: Bool {
        guard let odometer, let previousOdometer else { return false }
        return odometer <= previousOdometer
    }

    private var canSave: Bool {
        selectedVehicle != nil
            && (odometer ?? 0) > 0
            && (gallons ?? 0) > 0
            && (pricePerGallon ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                if vehicles.count > 1 {
                    Section {
                        Picker("Vehicle", selection: $selectedVehicleID) {
                            ForEach(vehicles) { vehicle in
                                Text(vehicle.name).tag(Optional(vehicle.id))
                            }
                        }
                    }
                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])

                    LabeledContent("Odometer") {
                        TextField("miles", value: $odometer, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("Gallons") {
                        TextField("0.000", value: $gallons, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("Price per Gallon") {
                        TextField("0.000", value: $pricePerGallon, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("Total Cost") {
                        Text(Format.currency(totalCost))
                            .fontWeight(.semibold)
                            .foregroundStyle(totalCost > 0 ? .primary : .secondary)
                    }
                } header: {
                    Text("Fill-Up")
                } footer: {
                    if odometerLooksWrong, let previousOdometer {
                        Label(
                            "Odometer is at or below the last reading (\(Format.odometer(previousOdometer)) mi). Double-check before saving.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }

                Section {
                    Toggle("Filled the tank completely", isOn: $isFullTank)

                    Picker("Fuel Grade", selection: $fuelGrade) {
                        ForEach(FuelGrade.allCases) { grade in
                            Text(grade.rawValue).tag(grade)
                        }
                    }

                    TextField("Gas Station (optional)", text: $station)

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("Details")
                } footer: {
                    Text("Marking full tanks lets the app calculate exact MPG between fills. Leave it off for partial fills — those gallons still count toward the next full-tank MPG.")
                }
            }
            .navigationTitle(entry == nil ? "New Fill-Up" : "Edit Fill-Up")
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
            .onAppear(perform: populate)
        }
    }

    private func populate() {
        if let entry {
            selectedVehicleID = entry.vehicle?.id
            date = entry.date
            odometer = entry.odometer
            gallons = entry.gallons
            pricePerGallon = entry.pricePerGallon
            isFullTank = entry.isFullTank
            fuelGrade = entry.fuelGrade
            station = entry.station
            notes = entry.notes
        } else {
            selectedVehicleID = defaultVehicle?.id ?? vehicles.first?.id
        }
    }

    private func save() {
        guard let vehicle = selectedVehicle,
              let odometer, let gallons, let pricePerGallon else { return }

        if let entry {
            entry.vehicle = vehicle
            entry.date = date
            entry.odometer = odometer
            entry.gallons = gallons
            entry.pricePerGallon = pricePerGallon
            entry.isFullTank = isFullTank
            entry.fuelGrade = fuelGrade
            entry.station = station
            entry.notes = notes
        } else {
            let newEntry = FuelEntry(
                date: date,
                odometer: odometer,
                gallons: gallons,
                pricePerGallon: pricePerGallon,
                isFullTank: isFullTank,
                fuelGrade: fuelGrade,
                station: station,
                notes: notes,
                vehicle: vehicle
            )
            modelContext.insert(newEntry)
        }
        dismiss()
    }
}

#Preview {
    AddEditFillUpView()
        .modelContainer(PreviewData.container)
}
