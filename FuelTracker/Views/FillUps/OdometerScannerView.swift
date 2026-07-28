import SwiftUI
import VisionKit

/// Live camera scanner that reads the odometer off the dashboard and
/// validates it against the vehicle's history before it can be saved.
struct OdometerScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let previousOdometer: Double?
    let typicalMilesPerFill: Double?
    let onAccept: (Double) -> Void

    @State private var candidate: OdometerCandidate?

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ZStack(alignment: .bottom) {
                        OdometerDataScanner(
                            candidate: $candidate,
                            previousOdometer: previousOdometer,
                            typicalMilesPerFill: typicalMilesPerFill
                        )
                        .ignoresSafeArea()
                        readingBar
                    }
                } else {
                    ContentUnavailableView(
                        "Camera Not Available",
                        systemImage: "camera",
                        description: Text("Live scanning needs a device with a camera and camera permission. It isn't available in the Simulator — enter the reading manually instead.")
                    )
                }
            }
            .navigationTitle("Scan Odometer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var readingBar: some View {
        VStack(spacing: 10) {
            Text("Point the camera at your odometer")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text(candidate.map { "\(Format.odometer($0.value)) mi" } ?? "—")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(candidate == nil ? .secondary : .primary)
                if let candidate {
                    validationLabel(for: candidate.validation)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                if let candidate {
                    onAccept(candidate.value)
                }
                dismiss()
            } label: {
                Label("Use This Reading", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(candidate == nil)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding()
    }

    private func validationLabel(for validation: OdometerValidation) -> some View {
        let (message, icon): (String, String) = switch validation {
        case .plausible(let miles):
            ("Looks right — \(Format.odometer(miles)) mi since your last fill", "checkmark.circle")
        case .noHistory:
            ("No previous reading to check against", "questionmark.circle")
        case .belowLastReading(let last):
            ("Below your last reading of \(Format.odometer(last)) mi — double-check", "exclamationmark.triangle.fill")
        case .implausiblyFar(_, let miles):
            ("\(Format.odometer(miles)) mi since your last fill — double-check", "exclamationmark.triangle.fill")
        }
        return Label(message, systemImage: icon)
            .font(.caption2)
            .foregroundStyle(validation.isWarning ? AccessiblePalette.color(.orange, in: colorScheme) : Color.secondary)
            .multilineTextAlignment(.center)
    }
}

private struct OdometerDataScanner: UIViewControllerRepresentable {
    @Binding var candidate: OdometerCandidate?
    let previousOdometer: Double?
    let typicalMilesPerFill: Double?

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            candidate: $candidate,
            previousOdometer: previousOdometer,
            typicalMilesPerFill: typicalMilesPerFill
        )
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        @Binding var candidate: OdometerCandidate?
        let previousOdometer: Double?
        let typicalMilesPerFill: Double?

        init(candidate: Binding<OdometerCandidate?>, previousOdometer: Double?, typicalMilesPerFill: Double?) {
            _candidate = candidate
            self.previousOdometer = previousOdometer
            self.typicalMilesPerFill = typicalMilesPerFill
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            update(with: allItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            update(with: allItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            update(with: allItems)
        }

        private func update(with items: [RecognizedItem]) {
            let lines = items.compactMap { item -> String? in
                if case .text(let text) = item {
                    return text.transcript
                }
                return nil
            }
            let parsed = OdometerScanParser.parse(
                lines,
                previousOdometer: previousOdometer,
                typicalMilesPerFill: typicalMilesPerFill
            )
            candidate = OdometerScanParser.preferred(current: candidate, new: parsed)
        }
    }
}
