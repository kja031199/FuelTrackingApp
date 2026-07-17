import SwiftUI
import SwiftData

/// Form for logging a new fill-up or editing an existing one.
/// Field state and validation live in the shared FillUpFormModel;
/// total cost is calculated live from gallons × price per gallon.
struct AddEditFillUpView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    private let defaultVehicle: Vehicle?
    @State private var form: FillUpFormModel
    @State private var selectedVehicleID: UUID?

    init(entry: FuelEntry? = nil, defaultVehicle: Vehicle? = nil) {
        self.defaultVehicle = entry?.vehicle ?? defaultVehicle
        _form = State(initialValue: entry.map(FillUpFormModel.init(entry:)) ?? FillUpFormModel())
    }

    private var selectedVehicle: Vehicle? {
        vehicles.first { $0.id == selectedVehicleID }
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
                    DatePicker("Date", selection: $form.date, displayedComponents: [.date, .hourAndMinute])

                    LabeledContent("Odometer") {
                        TextField("miles", value: $form.odometer, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("Gallons") {
                        TextField("0.000", value: $form.gallons, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("Price per Gallon") {
                        TextField("0.000", value: $form.pricePerGallon, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("Total Cost") {
                        Text(Format.currency(form.totalCost))
                            .fontWeight(.semibold)
                            .foregroundStyle(form.totalCost > 0 ? .primary : .secondary)
                    }
                } header: {
                    Text("Fill-Up")
                } footer: {
                    if form.odometerLooksWrong(for: selectedVehicle),
                       let previous = form.previousOdometer(for: selectedVehicle) {
                        Label(
                            "Odometer is at or below the last reading (\(Format.odometer(previous)) mi). Double-check before saving.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }

                Section {
                    Toggle("Filled the tank completely", isOn: $form.isFullTank)

                    Picker("Fuel Grade", selection: $form.fuelGrade) {
                        ForEach(FuelGrade.allCases) { grade in
                            Text(grade.rawValue).tag(grade)
                        }
                    }

                    TextField("Gas Station (optional)", text: $form.station)

                    TextField("Notes (optional)", text: $form.notes, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("Details")
                } footer: {
                    Text("Marking full tanks lets the app calculate exact MPG between fills. Leave it off for partial fills — those gallons still count toward the next full-tank MPG.")
                }
            }
            .navigationTitle(form.isEditing ? "Edit Fill-Up" : "New Fill-Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!form.canSave || selectedVehicle == nil)
                }
            }
            .onAppear {
                if selectedVehicleID == nil {
                    selectedVehicleID = defaultVehicle?.id ?? vehicles.first?.id
                }
            }
        }
    }

    private func save() {
        guard let vehicle = selectedVehicle else { return }
        form.save(to: vehicle, in: modelContext)
        dismiss()
    }
}

#Preview {
    AddEditFillUpView()
        .modelContainer(PreviewData.container)
}
