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
    @State private var showingScanner = false
    @State private var stationLocator = StationLocator()
    @State private var isLocatingStation = false
    @State private var stationHint: String?

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
                    Button {
                        showingScanner = true
                    } label: {
                        Label("Scan Pump Display", systemImage: "viewfinder")
                    }
                } footer: {
                    Text("Point your camera at the pump and the gallons, price, and total are read automatically — on your device, nothing leaves your phone.")
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

                    HStack {
                        TextField("Gas Station (optional)", text: $form.station)
                        Button {
                            detectStation()
                        } label: {
                            if isLocatingStation {
                                ProgressView()
                            } else {
                                Image(systemName: "location.fill")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(isLocatingStation)
                        .accessibilityLabel("Detect gas station from my location")
                    }

                    TextField("Notes (optional)", text: $form.notes, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("Details")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let stationHint {
                            Label(stationHint, systemImage: "location.slash")
                        }
                        Text("Marking full tanks lets the app calculate exact MPG between fills. Leave it off for partial fills — those gallons still count toward the next full-tank MPG.")
                    }
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
            .sheet(isPresented: $showingScanner) {
                PumpScannerView { reading in
                    if let gallons = reading.gallons {
                        form.gallons = gallons
                    }
                    if let price = reading.pricePerGallon {
                        form.pricePerGallon = price
                    }
                }
            }
            .onAppear {
                if selectedVehicleID == nil {
                    selectedVehicleID = defaultVehicle?.id ?? vehicles.first?.id
                }
                // Auto-fill the station for new entries once the user has
                // granted location access (the button asks the first time).
                if !form.isEditing, form.station.isEmpty, stationLocator.isAuthorized {
                    detectStation()
                }
            }
        }
    }

    private func detectStation() {
        guard !isLocatingStation else { return }
        isLocatingStation = true
        stationHint = nil
        Task {
            defer { isLocatingStation = false }
            do {
                let station = try await stationLocator.detectStation()
                form.station = station.name
                form.latitude = station.latitude
                form.longitude = station.longitude
            } catch StationLocatorError.permissionDenied {
                stationHint = "Allow location access in Settings to detect the station automatically."
            } catch StationLocatorError.noStationNearby {
                stationHint = "No gas station found nearby — you can type the name instead."
            } catch {
                stationHint = "Couldn't determine your location — you can type the station name instead."
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
