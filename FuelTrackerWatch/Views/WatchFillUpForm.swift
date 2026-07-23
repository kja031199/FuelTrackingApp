import SwiftUI
import SwiftData
import WatchKit

/// Compact fill-up entry form — the first thing on the watch screen.
/// Field state and validation live in the shared FillUpFormModel;
/// total cost is calculated live from gallons × price per gallon.
struct WatchFillUpForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(UnitSettings.self) private var unitSettings: UnitSettings?
    let vehicle: Vehicle?

    @State private var form = FillUpFormModel()
    @State private var justSaved = false

    private var units: UnitPreferences { unitSettings?.preferences ?? .us }

    // Bind to the user's units; the form keeps canonical values.
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
        VStack(alignment: .leading, spacing: 8) {
            Text("New Fill-Up")
                .font(.headline)

            numberField("Odometer (\(units.distance.abbreviation))", value: odometerField)
            numberField(units.volume.name, value: gallonsField)
            numberField("Price / \(units.volume.singularNoun)", value: priceField)

            HStack {
                Text("Total")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Format.currency(form.totalCost))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(form.totalCost > 0 ? .primary : .secondary)
            }
            .padding(.vertical, 2)

            Toggle("Full tank", isOn: $form.isFullTank)
                .font(.caption)

            Button {
                save()
            } label: {
                if justSaved {
                    Label("Saved", systemImage: "checkmark")
                } else {
                    Label("Save Fill-Up", systemImage: "fuelpump.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!form.canSave || vehicle == nil)
        }
    }

    private func numberField(_ title: String, value: Binding<Double?>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("0", value: value, format: .number)
        }
    }

    private func save() {
        guard let vehicle else { return }

        form.date = .now
        form.save(to: vehicle, in: modelContext)
        form.resetForNextEntry()
        WKInterfaceDevice.current().play(.success)

        justSaved = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            justSaved = false
        }
    }
}

#Preview {
    ScrollView {
        WatchFillUpForm(vehicle: nil)
    }
    .modelContainer(PreviewData.container)
}
