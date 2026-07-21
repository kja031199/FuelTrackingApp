import SwiftUI
import VisionKit

/// Live camera scanner that reads gallons, price per gallon, and total
/// straight off the gas pump display. All recognition is on-device.
/// Holds a weak reference to the live scanner so the accept action can grab
/// a still frame to keep as the fill-up's receipt.
final class ScannerCaptureHandle {
    weak var scanner: DataScannerViewController?

    func capturePhotoData() async -> Data? {
        guard let scanner else { return nil }
        guard let image = try? await scanner.capturePhoto() else { return nil }
        return ReceiptImage.compressed(from: image)
    }
}

struct PumpScannerView: View {
    @Environment(\.dismiss) private var dismiss
    /// Delivers the parsed reading and, when available, a still photo of the
    /// pump to keep as the receipt.
    let onAccept: (PumpReading, Data?) -> Void

    @State private var reading = PumpReading()
    @State private var isCapturing = false
    private let captureHandle = ScannerCaptureHandle()

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ZStack(alignment: .bottom) {
                        PumpDataScanner(reading: $reading, captureHandle: captureHandle)
                            .ignoresSafeArea()
                        readingBar
                    }
                } else {
                    ContentUnavailableView(
                        "Camera Not Available",
                        systemImage: "camera",
                        description: Text("Live scanning needs a device with a camera and camera permission. It isn't available in the Simulator — enter the numbers manually instead.")
                    )
                }
            }
            .navigationTitle("Scan Pump")
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
            Text("Point the camera at the pump display")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                readingChip("Gallons", reading.gallons.map(Format.gallons))
                readingChip("Price/Gal", reading.pricePerGallon.map(Format.fuelPrice))
                readingChip("Total", reading.totalCost.map(Format.currency))
            }

            Button {
                capture()
            } label: {
                Label(isCapturing ? "Saving…" : "Use These Values", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!reading.isComplete || isCapturing)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    /// Grabs a still of the pump (best-effort) and hands both the reading and
    /// the photo back before dismissing.
    private func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        Task {
            let photo = await captureHandle.capturePhotoData()
            onAccept(reading, photo)
            dismiss()
        }
    }

    private func readingChip(_ title: String, _ value: String?) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(value == nil ? .secondary : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PumpDataScanner: UIViewControllerRepresentable {
    @Binding var reading: PumpReading
    let captureHandle: ScannerCaptureHandle

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        captureHandle.scanner = scanner
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        captureHandle.scanner = scanner
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(reading: $reading)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        @Binding var reading: PumpReading

        init(reading: Binding<PumpReading>) {
            _reading = reading
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
            let parsed = PumpScanParser.parse(lines)
            reading = PumpScanParser.merge(current: reading, new: parsed)
        }
    }
}
