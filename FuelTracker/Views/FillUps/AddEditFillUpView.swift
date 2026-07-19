import PhotosUI
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
    @State private var showingOdometerScanner = false
    @State private var stationLocator = StationLocator()
    @State private var isLocatingStation = false
    @State private var stationHint: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var isImportingPhoto = false
    @State private var importSummary: String?
    @State private var importHint: String?

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

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        HStack {
                            Label("Import Pump Photo", systemImage: "photo.on.rectangle.angled")
                            Spacer()
                            if isImportingPhoto {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isImportingPhoto)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let importSummary {
                            Label(importSummary, systemImage: "sparkles")
                                .foregroundStyle(.tint)
                        }
                        if let importHint {
                            Label(importHint, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                        }
                        Text("Scan live at the pump, or pick a photo you took earlier — gallons and price are read from the display, and the date, time, and gas station come from the photo itself. Everything happens on your device.")
                    }
                }

                Section {
                    DatePicker("Date", selection: $form.date, displayedComponents: [.date, .hourAndMinute])

                    LabeledContent("Odometer") {
                        HStack {
                            TextField("miles", value: $form.odometer, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Button {
                                showingOdometerScanner = true
                            } label: {
                                Image(systemName: "camera.viewfinder")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Scan odometer with the camera")
                        }
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
            .sheet(isPresented: $showingOdometerScanner) {
                let context = odometerScanContext
                OdometerScannerView(
                    previousOdometer: context.previous,
                    typicalMilesPerFill: context.typical
                ) { value in
                    form.odometer = value
                }
            }
            .onChange(of: photoItem) { _, newItem in
                if let newItem {
                    importPhoto(newItem)
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

    private func importPhoto(_ item: PhotosPickerItem) {
        isImportingPhoto = true
        importSummary = nil
        importHint = nil
        Task {
            defer {
                isImportingPhoto = false
                photoItem = nil
            }

            guard let data = try? await item.loadTransferable(type: Data.self) else {
                importHint = "Couldn't load that photo — try picking it again."
                return
            }

            let imported = await PumpPhotoImporter.process(data: data)
            guard imported.foundAnything else {
                importHint = "Couldn't read pump numbers or metadata from that photo. A sharp, straight-on shot of the display works best."
                return
            }

            var summaryParts: [String] = []

            if let gallons = imported.reading.gallons {
                form.gallons = gallons
                summaryParts.append("\(Format.gallons(gallons)) gal")
            }
            if let price = imported.reading.pricePerGallon {
                form.pricePerGallon = price
                summaryParts.append("\(Format.fuelPrice(price))/gal")
            }
            // A dashboard photo can carry the odometer. Only a reading that
            // validates against this vehicle's history is trusted enough to
            // auto-fill; anything doubtful is left to the live scanner or
            // manual entry.
            if form.odometer == nil {
                let claimed = [
                    imported.reading.gallons,
                    imported.reading.pricePerGallon,
                    imported.reading.totalCost,
                ].compactMap { $0 }
                let context = odometerScanContext
                if let candidate = OdometerScanParser.parse(
                    imported.ocrLines,
                    previousOdometer: context.previous,
                    typicalMilesPerFill: context.typical,
                    excluding: claimed
                ), case .plausible = candidate.validation {
                    form.odometer = candidate.value
                    summaryParts.append("\(Format.odometer(candidate.value)) mi")
                }
            }
            if let capturedAt = imported.capturedAt {
                form.date = capturedAt
                summaryParts.append(capturedAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let latitude = imported.latitude, let longitude = imported.longitude {
                form.latitude = latitude
                form.longitude = longitude
                if let station = try? await stationLocator.nearestStation(latitude: latitude, longitude: longitude) {
                    form.station = station.name
                    form.latitude = station.latitude
                    form.longitude = station.longitude
                    summaryParts.append(station.name)
                } else {
                    summaryParts.append("location saved")
                }
            }

            importSummary = "Imported: " + summaryParts.joined(separator: " · ")
            if imported.reading.gallons == nil || imported.reading.pricePerGallon == nil {
                importHint = "Couldn't read every pump number — fill in the rest manually."
            }
        }
    }

    /// History context for validating a scanned odometer: the vehicle's
    /// highest recorded reading and its typical distance between fills.
    private var odometerScanContext: (previous: Double?, typical: Double?) {
        guard let vehicle = selectedVehicle else { return (nil, nil) }
        let statistics = FuelStatistics(entries: vehicle.fillUps)
        return (vehicle.fillUps.map(\.odometer).max(), statistics.averageMilesBetweenFillUps)
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
