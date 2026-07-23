import PhotosUI
import SwiftUI
import SwiftData
import UIKit

/// The form someone else uses to submit a fill-up for a vehicle. In the full
/// feature this opens on the recipient's device via a shared link; for now it's
/// reachable in-app so the submit → review → approve loop can be exercised end
/// to end. It creates a ``PendingFillUp`` — never a `FuelEntry` directly — so
/// an outside submission always goes through the owner's review.
struct SubmitFillUpView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(UnitSettings.self) private var unitSettings: UnitSettings?

    let vehicle: Vehicle

    @State private var form = FillUpFormModel()
    @State private var submitterName = ""
    @State private var receiptItem: PhotosPickerItem?
    @State private var submitted = false

    private var units: UnitPreferences { unitSettings?.preferences ?? .us }

    // Bind the fields to the user's units; the form keeps canonical values.
    private var odometerField: Binding<Double?> {
        Binding(
            get: { form.odometer.map { units.distance.fromMiles($0) } },
            set: { form.odometer = $0.map { units.distance.toMiles($0) } }
        )
    }

    private var gallonsField: Binding<Double?> {
        Binding(
            get: { form.gallons.map { units.volume.fromGallons($0) } },
            set: { form.gallons = $0.map { units.volume.toGallons($0) } }
        )
    }

    private var priceField: Binding<Double?> {
        Binding(
            get: { form.pricePerGallon.map { $0 / units.volume.fromGallons(1) } },
            set: { form.pricePerGallon = $0.map { $0 * units.volume.fromGallons(1) } }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if submitted {
                    ContentUnavailableView {
                        Label("Sent for Review", systemImage: "paperplane")
                    } description: {
                        Text("Your fill-up was submitted for \(vehicle.name). The owner will review it before it's added to their log.")
                    } actions: {
                        Button("Done") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    formContent
                }
            }
            .navigationTitle("Submit Fill-Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { submit() }
                        .disabled(!form.canSave)
                }
            }
            .onChange(of: receiptItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    defer { receiptItem = nil }
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let compressed = ReceiptImage.compressed(from: data) {
                        form.receiptImageData = compressed
                    }
                }
            }
        }
    }

    private var formContent: some View {
        Form {
            Section {
                TextField("Your name (optional)", text: $submitterName)
            } header: {
                Text("You")
            } footer: {
                Text("Submitting a fill-up for \(vehicle.name). The owner reviews every submission before it's added.")
            }

            Section("Fill-Up") {
                DatePicker("Date", selection: $form.date, displayedComponents: [.date, .hourAndMinute])

                LabeledContent("Odometer") {
                    TextField(units.distance.abbreviation, value: odometerField, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(units.volume.name) {
                    TextField("0.000", value: gallonsField, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Price per \(units.volume.singularNoun)") {
                    TextField("0.000", value: priceField, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Total Cost") {
                    Text(Format.currency(form.totalCost))
                        .fontWeight(.semibold)
                        .foregroundStyle(form.totalCost > 0 ? .primary : .secondary)
                }
            }

            Section("Details") {
                Toggle("Filled the tank completely", isOn: $form.isFullTank)
                Picker("Fuel Grade", selection: $form.fuelGrade) {
                    ForEach(FuelGrade.allCases) { grade in
                        Text(grade.rawValue).tag(grade)
                    }
                }
                TextField("Gas Station (optional)", text: $form.station)
                TextField("Notes (optional)", text: $form.notes, axis: .vertical)
                    .lineLimit(1...4)
            }

            Section("Receipt") {
                receiptRow
            }
        }
    }

    @ViewBuilder
    private var receiptRow: some View {
        if let data = form.receiptImageData, let uiImage = UIImage(data: data) {
            HStack(spacing: 12) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("Receipt attached")
                Spacer()
            }
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

    private func submit() {
        guard let draft = form.draft else { return }
        let pending = PendingFillUp.from(
            draft: draft,
            submitterName: submitterName.trimmingCharacters(in: .whitespaces),
            vehicleID: vehicle.id
        )
        modelContext.insert(pending)
        submitted = true
    }
}
