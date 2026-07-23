import Foundation
import Observation

/// The result of applying an import to a form: a confirmation line, an optional
/// recoverable hint, and which fields were filled (so the UI can highlight
/// them). One shape shared by every import path.
struct ImportOutcome: Equatable {
    enum Field: Hashable { case gallons, price, odometer, date, station }

    var summary: String?
    var hint: String?
    var filled: Set<Field> = []

    var didFill: Bool { !filled.isEmpty }
}

/// Orchestrates the ways a fill-up can be populated from a photo — importing a
/// pump or receipt photo (auto-detected), attaching a receipt image, and
/// looking up the station — and maps the results onto a ``FillUpFormModel``.
///
/// The async I/O (Vision OCR, MapKit, image decoding) stays at the edges in the
/// instance methods; the result-to-form mapping is factored into the
/// `nonisolated static` `apply…` helpers, which are pure and unit-tested.
@MainActor
@Observable
final class FillUpImportModel {
    var isImportingPhoto = false
    var isLocatingStation = false

    /// What the last import filled in, for a confirmation line.
    var summary: String?
    /// A recoverable problem with the last import, e.g. an unreadable photo.
    var hint: String?
    /// A problem detecting the station from the device's location.
    var stationHint: String?

    /// Fields the last import just filled, briefly, so the form can flash them.
    var highlightedFields: Set<ImportOutcome.Field> = []
    /// Increments on each successful import — a trigger for success feedback.
    private(set) var successPulse = 0

    private var highlightToken = 0
    private let stationLocator = StationLocator()

    var isStationAuthorized: Bool { stationLocator.isAuthorized }

    /// Called by the view when a picked photo's bytes couldn't be loaded.
    func reportPhotoLoadFailure() {
        hint = "Couldn't load that photo — try picking it again."
    }

    // MARK: - Import a photo (pump display or receipt, auto-detected)

    func importPhoto(
        data: Data,
        into form: FillUpFormModel,
        previousOdometer: Double?,
        typicalMilesPerFill: Double?,
        captureLocation: Bool = true
    ) async {
        isImportingPhoto = true
        summary = nil
        hint = nil
        defer { isImportingPhoto = false }

        // Keep the photo with the fill-up. Store only the re-encoded,
        // size-bounded image, never the raw bytes.
        form.receiptImageData = ReceiptImage.compressed(from: data)

        // OCR once; a receipt reading is derived from the same recognized text.
        let pump = await PumpPhotoImporter.process(data: data)
        let receipt = ReceiptPhotoImporter.reading(from: pump)
        guard pump.foundAnything || Self.looksLikeReceipt(receipt) else {
            hint = "Couldn't read numbers, a date, or a station from that photo. A sharp, straight-on shot works best."
            return
        }

        let outcome: ImportOutcome
        if Self.looksLikeReceipt(receipt) {
            // A printed date or station means it's a receipt. Only reach for
            // GPS when the receipt didn't name the station itself — and never
            // when the user has opted out of location capture.
            let station = await nearestStation(
                latitude: receipt.latitude, longitude: receipt.longitude,
                when: receipt.stationName == nil && captureLocation
            )
            outcome = Self.applyReceipt(
                receipt, to: form, resolvedStation: station, captureLocation: captureLocation
            )
        } else {
            let station = await nearestStation(
                latitude: pump.latitude, longitude: pump.longitude, when: captureLocation
            )
            outcome = Self.applyPumpReading(
                pump, to: form,
                previousOdometer: previousOdometer,
                typicalMilesPerFill: typicalMilesPerFill,
                resolvedStation: station,
                captureLocation: captureLocation
            )
        }
        summary = outcome.summary
        hint = outcome.hint
        if outcome.didFill { flashHighlight(outcome.filled) }
    }

    func attachReceipt(data: Data, into form: FillUpFormModel) {
        if let compressed = ReceiptImage.compressed(from: data) {
            form.receiptImageData = compressed
        } else {
            hint = "Couldn't read that image — try a different photo."
        }
    }

    // MARK: - Station

    func detectStation(into form: FillUpFormModel, captureLocation: Bool = true) async {
        // Respect the location-capture opt-out: never touch Core Location when
        // the user has turned capture off. (The UI also hides the button, but
        // this guard keeps the model safe on its own.)
        guard captureLocation else { return }
        guard !isLocatingStation else { return }
        isLocatingStation = true
        stationHint = nil
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

    private func nearestStation(latitude: Double?, longitude: Double?, when condition: Bool) async -> DetectedStation? {
        guard condition, let latitude, let longitude else { return nil }
        return try? await stationLocator.nearestStation(latitude: latitude, longitude: longitude)
    }

    /// Shows the filled fields highlighted, then clears them a moment later.
    /// A token guards against an older flash clearing a newer one.
    private func flashHighlight(_ fields: Set<ImportOutcome.Field>) {
        successPulse += 1
        highlightedFields = fields
        highlightToken += 1
        let token = highlightToken
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if token == highlightToken { highlightedFields = [] }
        }
    }

    // MARK: - Detection & mapping (pure, unit-tested)

    /// A pump display shows only numbers; a printed date or a known station
    /// brand is the signature of a receipt.
    nonisolated static func looksLikeReceipt(_ receipt: ReceiptPhotoImport) -> Bool {
        receipt.purchaseDate != nil || receipt.stationName != nil
    }

    /// Applies a pump-photo import onto the form and returns the confirmation
    /// text. `resolvedStation` is the station already looked up from the
    /// photo's coordinates (nil if none), kept out of here so MapKit stays at
    /// the edge.
    nonisolated static func applyPumpReading(
        _ imported: PumpPhotoImport,
        to form: FillUpFormModel,
        previousOdometer: Double?,
        typicalMilesPerFill: Double?,
        resolvedStation: DetectedStation?,
        captureLocation: Bool = true
    ) -> ImportOutcome {
        var parts: [String] = []
        var filled: Set<ImportOutcome.Field> = []

        if let gallons = imported.reading.gallons {
            form.gallons = gallons
            parts.append("\(Format.gallons(gallons)) gal")
            filled.insert(.gallons)
        }
        if let price = imported.reading.pricePerGallon {
            form.pricePerGallon = price
            parts.append("\(Format.fuelPrice(price))/gal")
            filled.insert(.price)
        }
        // A dashboard photo can carry the odometer. Only a reading that
        // validates against this vehicle's history is trusted enough to
        // auto-fill; anything doubtful is left to the live scanner or manual
        // entry.
        if form.odometer == nil {
            let claimed = [
                imported.reading.gallons,
                imported.reading.pricePerGallon,
                imported.reading.totalCost,
            ].compactMap { $0 }
            if let candidate = OdometerScanParser.parse(
                imported.ocrLines,
                previousOdometer: previousOdometer,
                typicalMilesPerFill: typicalMilesPerFill,
                excluding: claimed
            ), case .plausible = candidate.validation {
                form.odometer = candidate.value
                parts.append("\(Format.odometer(candidate.value)) mi")
                filled.insert(.odometer)
            }
        }
        if let capturedAt = imported.capturedAt {
            form.date = capturedAt
            parts.append(capturedAt.formatted(date: .abbreviated, time: .shortened))
            filled.insert(.date)
        }
        applyCoordinates(
            latitude: imported.latitude,
            longitude: imported.longitude,
            printedStation: nil,
            resolvedStation: resolvedStation,
            captureLocation: captureLocation,
            to: form,
            parts: &parts,
            filled: &filled
        )

        let hint = missingNumberHint(imported.reading, message: "Couldn't read every pump number — fill in the rest manually.")
        return ImportOutcome(
            summary: parts.isEmpty ? nil : "Imported: " + parts.joined(separator: " · "),
            hint: hint,
            filled: filled
        )
    }

    /// Applies a receipt import onto the form and returns the confirmation
    /// text. The printed date and station win over the photo's metadata.
    nonisolated static func applyReceipt(
        _ imported: ReceiptPhotoImport,
        to form: FillUpFormModel,
        resolvedStation: DetectedStation?,
        captureLocation: Bool = true
    ) -> ImportOutcome {
        var parts: [String] = []
        var filled: Set<ImportOutcome.Field> = []

        if let gallons = imported.reading.gallons {
            form.gallons = gallons
            parts.append("\(Format.gallons(gallons)) gal")
            filled.insert(.gallons)
        }
        if let price = imported.reading.pricePerGallon {
            form.pricePerGallon = price
            parts.append("\(Format.fuelPrice(price))/gal")
            filled.insert(.price)
        }
        // The date printed on the receipt is the real purchase date; the
        // photo's capture date is only a fallback when that's unreadable.
        if let date = imported.bestDate {
            form.date = date
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
            filled.insert(.date)
        }
        if let station = imported.stationName {
            form.station = station
            parts.append(station)
            filled.insert(.station)
        }
        applyCoordinates(
            latitude: imported.latitude,
            longitude: imported.longitude,
            printedStation: imported.stationName,
            resolvedStation: resolvedStation,
            captureLocation: captureLocation,
            to: form,
            parts: &parts,
            filled: &filled
        )

        let hint = missingNumberHint(imported.reading, message: "Couldn't read every number — fill in the rest manually.")
        let summary = parts.isEmpty
            ? "Receipt attached — fill in the details manually."
            : "Imported: " + parts.joined(separator: " · ")
        return ImportOutcome(summary: summary, hint: hint, filled: filled)
    }

    /// Records coordinates on the form, preferring an already-named station
    /// (printed on a receipt) and otherwise the resolved GPS station, falling
    /// back to just saving the location.
    private nonisolated static func applyCoordinates(
        latitude: Double?,
        longitude: Double?,
        printedStation: String?,
        resolvedStation: DetectedStation?,
        captureLocation: Bool,
        to form: FillUpFormModel,
        parts: inout [String],
        filled: inout Set<ImportOutcome.Field>
    ) {
        // With capture off, a photo's embedded GPS is ignored entirely — no
        // coordinates stored and no location-derived station. A station printed
        // on the receipt is text, not location, so it's kept (set by the caller
        // before this point).
        guard captureLocation else { return }
        guard let latitude, let longitude else { return }
        form.latitude = latitude
        form.longitude = longitude

        // A station named on the receipt already went into the summary; don't
        // override it with a GPS guess.
        guard printedStation == nil else { return }

        if let station = resolvedStation {
            form.station = station.name
            form.latitude = station.latitude
            form.longitude = station.longitude
            parts.append(station.name)
            filled.insert(.station)
        } else {
            parts.append("location saved")
        }
    }

    private nonisolated static func missingNumberHint(_ reading: PumpReading, message: String) -> String? {
        (reading.gallons == nil || reading.pricePerGallon == nil) ? message : nil
    }
}
