import PhotosUI
import SwiftUI
import SwiftData
import UIKit

/// Form for logging a new fill-up or editing an existing one.
/// Field state and validation live in the shared FillUpFormModel;
/// total cost is calculated live from gallons × price per gallon.
struct AddEditFillUpView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]

    private let defaultVehicle: Vehicle?
    @State private var form: FillUpFormModel
    @State private var selectedVehicleID: UUID?
    @State private var importer = FillUpImportModel()
    @State private var showingScanner = false
    @State private var showingOdometerScanner = false
    @State private var showingReceiptViewer = false
    @State private var photoItem: PhotosPickerItem?
    @State private var receiptItem: PhotosPickerItem?

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
                            Label("Add from Photo", systemImage: "photo.on.rectangle.angled")
                            Spacer()
                            if importer.isImportingPhoto {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(importer.isImportingPhoto)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let summary = importer.summary {
                            Label(summary, systemImage: "sparkles")
                                .foregroundStyle(.tint)
                        }
                        if let hint = importer.hint {
                            Label(hint, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                        }
                        Text("Scan live at the pump, or pick a photo you already took — of the pump display or a paper receipt. The app figures out which it is and fills in the gallons, price, date, and station. Everything happens on your device.")
                    }
                }

                Section {
                    DatePicker("Date", selection: $form.date, displayedComponents: [.date, .hourAndMinute])
                        .listRowBackground(highlightBackground(for: .date))

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
                    .listRowBackground(highlightBackground(for: .odometer))

                    LabeledContent("Gallons") {
                        TextField("0.000", value: $form.gallons, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    .listRowBackground(highlightBackground(for: .gallons))

                    LabeledContent("Price per Gallon") {
                        TextField("0.000", value: $form.pricePerGallon, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    .listRowBackground(highlightBackground(for: .price))

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

                    Toggle("Missed logging a fill before this", isOn: $form.missedPreviousFillUp)

                    Picker("Fuel Grade", selection: $form.fuelGrade) {
                        ForEach(FuelGrade.allCases) { grade in
                            Text(grade.rawValue).tag(grade)
                        }
                    }

                    HStack {
                        TextField("Gas Station (optional)", text: $form.station)
                        Button {
                            Task { await importer.detectStation(into: form) }
                        } label: {
                            if importer.isLocatingStation {
                                ProgressView()
                            } else {
                                Image(systemName: "location.fill")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(importer.isLocatingStation)
                        .accessibilityLabel("Detect gas station from my location")
                    }
                    .listRowBackground(highlightBackground(for: .station))

                    TextField("Notes (optional)", text: $form.notes, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("Details")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let stationHint = importer.stationHint {
                            Label(stationHint, systemImage: "location.slash")
                        }
                        Text("Marking full tanks lets the app calculate exact MPG between fills. Leave it off for partial fills — those gallons still count toward the next full-tank MPG. If you forgot to log a fill-up before this one, mark it so the impossible-looking MPG segment is excluded from your stats — the fuel still counts toward spending.")
                    }
                }

                Section {
                    receiptRow
                } header: {
                    Text("Receipt")
                } footer: {
                    Text("Keep the pump or receipt photo with this fill-up — a permanent record for warranties, expenses, or settling arguments. Scanned and imported pump photos are attached automatically.")
                }
            }
            .navigationTitle(form.isEditing ? "Edit Fill-Up" : "New Fill-Up")
            .navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.success, trigger: importer.successPulse)
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
                PumpScannerView { reading, photoData in
                    if let gallons = reading.gallons {
                        form.gallons = gallons
                    }
                    if let price = reading.pricePerGallon {
                        form.pricePerGallon = price
                    }
                    if let photoData {
                        form.receiptImageData = photoData
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
                guard let newItem else { return }
                Task {
                    defer { photoItem = nil }
                    guard let data = try? await newItem.loadTransferable(type: Data.self) else {
                        importer.reportPhotoLoadFailure()
                        return
                    }
                    let context = odometerScanContext
                    await importer.importPhoto(
                        data: data,
                        into: form,
                        previousOdometer: context.previous,
                        typicalMilesPerFill: context.typical
                    )
                }
            }
            .onChange(of: receiptItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    defer { receiptItem = nil }
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        importer.attachReceipt(data: data, into: form)
                    }
                }
            }
            .sheet(isPresented: $showingReceiptViewer) {
                if let data = form.receiptImageData {
                    ReceiptViewer(imageData: data)
                }
            }
            .onAppear {
                if selectedVehicleID == nil {
                    selectedVehicleID = defaultVehicle?.id ?? vehicles.first?.id
                }
                // Auto-fill the station for new entries once the user has
                // granted location access (the button asks the first time).
                if !form.isEditing, form.station.isEmpty, importer.isStationAuthorized {
                    Task { await importer.detectStation(into: form) }
                }
            }
        }
    }

    /// A field row's background, briefly tinted when the last import filled it.
    private func highlightBackground(for field: ImportOutcome.Field) -> some View {
        let isOn = importer.highlightedFields.contains(field)
        return (isOn ? Color.accentColor.opacity(0.15) : Color(.secondarySystemGroupedBackground))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: importer.highlightedFields)
    }

    @ViewBuilder
    private var receiptRow: some View {
        if let data = form.receiptImageData, let uiImage = UIImage(data: data) {
            Button {
                showingReceiptViewer = true
            } label: {
                HStack(spacing: 12) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Receipt attached")
                        Text("Tap to view full screen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                form.receiptImageData = nil
            } label: {
                Label("Remove Receipt", systemImage: "trash")
            }
        } else {
            PhotosPicker(selection: $receiptItem, matching: .images) {
                Label("Attach Receipt Photo", systemImage: "paperclip")
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
