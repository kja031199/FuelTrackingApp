import SwiftUI
import SwiftData
import WatchKit

/// Compact fill-up entry form — the first thing on the watch screen.
/// Total cost is calculated live from gallons × price per gallon.
struct WatchFillUpForm: View {
    @Environment(\.modelContext) private var modelContext
    let vehicle: Vehicle?

    @State private var odometer: Double?
    @State private var gallons: Double?
    @State private var pricePerGallon: Double?
    @State private var isFullTank = true
    @State private var justSaved = false

    private var totalCost: Double {
        (gallons ?? 0) * (pricePerGallon ?? 0)
    }

    private var canSave: Bool {
        vehicle != nil
            && (odometer ?? 0) > 0
            && (gallons ?? 0) > 0
            && (pricePerGallon ?? 0) > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Fill-Up")
                .font(.headline)

            numberField("Odometer (mi)", value: $odometer)
            numberField("Gallons", value: $gallons)
            numberField("Price / Gallon", value: $pricePerGallon)

            HStack {
                Text("Total")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Format.currency(totalCost))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(totalCost > 0 ? .primary : .secondary)
            }
            .padding(.vertical, 2)

            Toggle("Full tank", isOn: $isFullTank)
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
            .disabled(!canSave)
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
        guard let vehicle, let odometer, let gallons, let pricePerGallon else { return }

        let entry = FuelEntry(
            odometer: odometer,
            gallons: gallons,
            pricePerGallon: pricePerGallon,
            isFullTank: isFullTank,
            vehicle: vehicle
        )
        modelContext.insert(entry)
        WKInterfaceDevice.current().play(.success)

        self.odometer = nil
        self.gallons = nil
        self.pricePerGallon = nil
        isFullTank = true

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
