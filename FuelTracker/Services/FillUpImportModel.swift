import Foundation
import Observation

/// Orchestrates the ways a fill-up can be populated from a photo — importing a
/// pump photo, scanning a receipt, attaching a receipt image, and looking up
/// the station — and maps the results onto a ``FillUpFormModel``.
///
/// The async I/O (Vision OCR, MapKit, image decoding) stays at the edges in
/// the instance methods; the result-to-form mapping is factored into the
/// `nonisolated static` `apply…` helpers, which are pure and unit-tested.
@MainActor
@Observable
final class FillUpImportModel {
    var isImportingPumpPhoto = false
    var isScanningReceipt = false
    var isLocatingStation = false

    /// What the last import filled in, for a confirmation line.
    var summary: String?
    /// A recoverable problem with the last import, e.g. an unreadable photo.
    var hint: String?
    /// A problem detecting the station from the device's location.
    var stationHint: String?

    private let stationLocator = StationLocator()

    var isStationAuthorized: Bool { stationLocator.isAuthorized }

    /// Called by the view when a picked photo's bytes couldn't be loaded.
    func reportPhotoLoadFailure() {
        hint = "Couldn't load that photo — try picking it again."
    }

    // MARK: - Pump photo

    func importPumpPhoto(
        data: Data,
        into form: FillUpFormModel,
        previousOdometer: Double?,
        typicalMilesPerFill: Double?
    ) async {
        isImportingPumpPhoto = true
        summary = nil
        hint = nil
        defer { isImportingPumpPhoto = false }

        // Keep the photo with the fill-up rather than discarding it after
        // parsing. Store only the re-encoded, size-bounded image, never the
        // raw bytes, which could be an unbounded/undecodable payload.
        form.receiptImageData = ReceiptImage.compressed(from: data)

        let imported = await PumpPhotoImporter.process(data: data)
        guard imported.foundAnything else {
            hint = "Couldn't read pump numbers or metadata from that photo. A sharp, straight-on shot of the display works best."
            return
        }

        let station = await nearestStation(latitude: imported.latitude, longitude: imported.longitude, when: true)
        let outcome = Self.applyPumpReading(
            imported,
            to: form,
            previousOdometer: previousOdometer,
            typicalMilesPerFill: typicalMilesPerFill,
            resolvedStation: station
        )
        summary = outcome.summary
        hint = outcome.hint
    }

    // MARK: - Receipt

    func scanReceipt(data: Data, into form: FillUpFormModel) async {
        isScanningReceipt = true
        summary = nil
        hint = nil
        defer { isScanningReceipt = false }

        form.receiptImageData = ReceiptImage.compressed(from: data)

        let imported = await ReceiptPhotoImporter.process(data: data)
        guard imported.foundAnything else {
            hint = "Couldn't read this receipt. A flat, well-lit photo of the whole receipt works best."
            return
        }

        // A brand printed on the receipt beats an after-the-fact GPS lookup, so
        // only reach for location when the receipt didn't name the station.
        let station = await nearestStation(
            latitude: imported.latitude,
            longitude: imported.longitude,
            when: imported.stationName == nil
        )
        let outcome = Self.applyReceipt(imported, to: form, resolvedStation: station)
        summary = outcome.summary
        hint = outcome.hint
    }

    func attachReceipt(data: Data, into form: FillUpFormModel) {
        if let compressed = ReceiptImage.compressed(from: data) {
            form.receiptImageData = compressed
        }
    }

    // MARK: - Station

    func detectStation(into form: FillUpFormModel) async {
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

    // MARK: - Pure result → form mapping (unit-tested)

    struct Outcome: Equatable {
        var summary: String?
        var hint: String?
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
        resolvedStation: DetectedStation?
    ) -> Outcome {
        var parts: [String] = []

        if let gallons = imported.reading.gallons {
            form.gallons = gallons
            parts.append("\(Format.gallons(gallons)) gal")
        }
        if let price = imported.reading.pricePerGallon {
            form.pricePerGallon = price
            parts.append("\(Format.fuelPrice(price))/gal")
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
            }
        }
        if let capturedAt = imported.capturedAt {
            form.date = capturedAt
            parts.append(capturedAt.formatted(date: .abbreviated, time: .shortened))
        }
        applyCoordinates(
            latitude: imported.latitude,
            longitude: imported.longitude,
            printedStation: nil,
            resolvedStation: resolvedStation,
            to: form,
            parts: &parts
        )

        let hint = missingNumberHint(imported.reading, message: "Couldn't read every pump number — fill in the rest manually.")
        return Outcome(summary: parts.isEmpty ? nil : "Imported: " + parts.joined(separator: " · "), hint: hint)
    }

    /// Applies a receipt import onto the form and returns the confirmation
    /// text. The printed date and station win over the photo's metadata.
    nonisolated static func applyReceipt(
        _ imported: ReceiptPhotoImport,
        to form: FillUpFormModel,
        resolvedStation: DetectedStation?
    ) -> Outcome {
        var parts: [String] = []

        if let gallons = imported.reading.gallons {
            form.gallons = gallons
            parts.append("\(Format.gallons(gallons)) gal")
        }
        if let price = imported.reading.pricePerGallon {
            form.pricePerGallon = price
            parts.append("\(Format.fuelPrice(price))/gal")
        }
        // The date printed on the receipt is the real purchase date; the
        // photo's capture date is only a fallback when that's unreadable.
        if let date = imported.bestDate {
            form.date = date
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        if let station = imported.stationName {
            form.station = station
            parts.append(station)
        }
        applyCoordinates(
            latitude: imported.latitude,
            longitude: imported.longitude,
            printedStation: imported.stationName,
            resolvedStation: resolvedStation,
            to: form,
            parts: &parts
        )

        let hint = missingNumberHint(imported.reading, message: "Couldn't read every number — fill in the rest manually.")
        let summary = parts.isEmpty
            ? "Receipt attached — fill in the details manually."
            : "Imported: " + parts.joined(separator: " · ")
        return Outcome(summary: summary, hint: hint)
    }

    /// Records coordinates on the form, preferring an already-named station
    /// (printed on a receipt) and otherwise the resolved GPS station, falling
    /// back to just saving the location.
    private nonisolated static func applyCoordinates(
        latitude: Double?,
        longitude: Double?,
        printedStation: String?,
        resolvedStation: DetectedStation?,
        to form: FillUpFormModel,
        parts: inout [String]
    ) {
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
        } else {
            parts.append("location saved")
        }
    }

    private nonisolated static func missingNumberHint(_ reading: PumpReading, message: String) -> String? {
        (reading.gallons == nil || reading.pricePerGallon == nil) ? message : nil
    }
}
