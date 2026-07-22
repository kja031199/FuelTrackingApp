import Foundation
import Testing
@testable import FuelTracker

/// Unit tests for the pure result-to-form mapping extracted from the fill-up
/// view. The async I/O (Vision, MapKit, PhotosUI) stays at the edge; this is
/// the logic that decides which fields get filled and what the user is told.
@MainActor
struct FillUpImportModelTests {
    private func pumpImport(
        gallons: Double? = nil, price: Double? = nil, total: Double? = nil,
        capturedAt: Date? = nil, latitude: Double? = nil, longitude: Double? = nil,
        ocrLines: [String] = []
    ) -> PumpPhotoImport {
        PumpPhotoImport(
            reading: PumpReading(gallons: gallons, pricePerGallon: price, totalCost: total),
            capturedAt: capturedAt, latitude: latitude, longitude: longitude, ocrLines: ocrLines
        )
    }

    private func receiptImport(
        gallons: Double? = nil, price: Double? = nil,
        purchaseDate: Date? = nil, capturedAt: Date? = nil, stationName: String? = nil,
        latitude: Double? = nil, longitude: Double? = nil
    ) -> ReceiptPhotoImport {
        ReceiptPhotoImport(
            reading: PumpReading(gallons: gallons, pricePerGallon: price),
            purchaseDate: purchaseDate, capturedAt: capturedAt, stationName: stationName,
            latitude: latitude, longitude: longitude
        )
    }

    // MARK: - Pump photo mapping

    @Test func pumpReadingFillsGallonsPriceAndSummarizes() {
        let form = FillUpFormModel()
        let outcome = FillUpImportModel.applyPumpReading(
            pumpImport(gallons: 8.712, price: 3.499),
            to: form, previousOdometer: nil, typicalMilesPerFill: nil, resolvedStation: nil
        )
        #expect(form.gallons == 8.712)
        #expect(form.pricePerGallon == 3.499)
        #expect(outcome.summary?.contains("gal") == true)
        #expect(outcome.hint == nil)
    }

    @Test func pumpReadingWithAMissingNumberSetsAHint() {
        let form = FillUpFormModel()
        let outcome = FillUpImportModel.applyPumpReading(
            pumpImport(gallons: 8.712), // price missing
            to: form, previousOdometer: nil, typicalMilesPerFill: nil, resolvedStation: nil
        )
        #expect(form.gallons == 8.712)
        #expect(outcome.hint == "Couldn't read every pump number — fill in the rest manually.")
    }

    @Test func pumpCaptureDateFillsTheFormDate() {
        let form = FillUpFormModel()
        let captured = Date(timeIntervalSince1970: 1_700_000_000)
        _ = FillUpImportModel.applyPumpReading(
            pumpImport(gallons: 8.712, price: 3.499, capturedAt: captured),
            to: form, previousOdometer: nil, typicalMilesPerFill: nil, resolvedStation: nil
        )
        #expect(form.date == captured)
    }

    @Test func aValidatedOdometerFromTheOCRAutoFills() {
        // 42,360 sits just past the last reading and within a plausible tank,
        // so it validates and fills; the fuel numbers are excluded as candidates.
        let form = FillUpFormModel()
        _ = FillUpImportModel.applyPumpReading(
            pumpImport(gallons: 8.712, price: 3.499, ocrLines: ["42360", "8.712", "3.499"]),
            to: form, previousOdometer: 42_000, typicalMilesPerFill: 350, resolvedStation: nil
        )
        #expect(form.odometer == 42_360)
    }

    @Test func anImplausibleOdometerIsNotAutoFilled() {
        // A reading below the last odometer can't be right — leave it blank.
        let form = FillUpFormModel()
        _ = FillUpImportModel.applyPumpReading(
            pumpImport(gallons: 8.712, price: 3.499, ocrLines: ["42360"]),
            to: form, previousOdometer: 50_000, typicalMilesPerFill: 350, resolvedStation: nil
        )
        #expect(form.odometer == nil)
    }

    @Test func anOdometerAlreadyTypedIsNeverOverwritten() {
        let form = FillUpFormModel()
        form.odometer = 12_345
        _ = FillUpImportModel.applyPumpReading(
            pumpImport(gallons: 8.712, price: 3.499, ocrLines: ["42360"]),
            to: form, previousOdometer: 42_000, typicalMilesPerFill: 350, resolvedStation: nil
        )
        #expect(form.odometer == 12_345)
    }

    @Test func aResolvedStationOverridesTheRawCoordinates() {
        let form = FillUpFormModel()
        let station = DetectedStation(name: "Shell", latitude: 37.5, longitude: -122.5)
        let outcome = FillUpImportModel.applyPumpReading(
            pumpImport(gallons: 8.712, price: 3.499, latitude: 37.0, longitude: -122.0),
            to: form, previousOdometer: nil, typicalMilesPerFill: nil, resolvedStation: station
        )
        #expect(form.station == "Shell")
        #expect(form.latitude == 37.5)   // station's, not the raw photo fix
        #expect(form.longitude == -122.5)
        #expect(outcome.summary?.contains("Shell") == true)
    }

    @Test func coordinatesWithoutAResolvedStationJustSaveTheLocation() {
        let form = FillUpFormModel()
        let outcome = FillUpImportModel.applyPumpReading(
            pumpImport(gallons: 8.712, price: 3.499, latitude: 37.0, longitude: -122.0),
            to: form, previousOdometer: nil, typicalMilesPerFill: nil, resolvedStation: nil
        )
        #expect(form.latitude == 37.0)
        #expect(form.station.isEmpty)
        #expect(outcome.summary?.contains("location saved") == true)
    }

    // MARK: - Receipt mapping

    @Test func receiptFillsNumbersDateAndPrintedStation() {
        let form = FillUpFormModel()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let outcome = FillUpImportModel.applyReceipt(
            receiptImport(gallons: 10, price: 3.2, purchaseDate: date, stationName: "Chevron"),
            to: form, resolvedStation: nil
        )
        #expect(form.gallons == 10)
        #expect(form.pricePerGallon == 3.2)
        #expect(form.date == date)
        #expect(form.station == "Chevron")
        #expect(outcome.summary?.contains("Chevron") == true)
    }

    @Test func aPrintedStationWinsOverAGPSLookup() {
        // The receipt named the station, so a GPS result must not override it,
        // and the raw photo coordinates are kept (not the station's).
        let form = FillUpFormModel()
        let gps = DetectedStation(name: "Shell", latitude: 1, longitude: 2)
        let outcome = FillUpImportModel.applyReceipt(
            receiptImport(gallons: 10, price: 3.2, stationName: "Chevron", latitude: 40, longitude: -100),
            to: form, resolvedStation: gps
        )
        #expect(form.station == "Chevron")
        #expect(form.latitude == 40)
        #expect(outcome.summary?.contains("Chevron") == true)
        #expect(outcome.summary?.contains("Shell") == false)
    }

    @Test func aReceiptWithoutAPrintedStationUsesTheGPSResult() {
        let form = FillUpFormModel()
        let gps = DetectedStation(name: "Costco", latitude: 47.6, longitude: -122.3)
        _ = FillUpImportModel.applyReceipt(
            receiptImport(gallons: 10, price: 3.2, latitude: 47.0, longitude: -122.0),
            to: form, resolvedStation: gps
        )
        #expect(form.station == "Costco")
        #expect(form.latitude == 47.6)
    }

    @Test func aReceiptThatYieldedNothingReadableStillConfirmsTheAttachment() {
        let form = FillUpFormModel()
        let outcome = FillUpImportModel.applyReceipt(receiptImport(), to: form, resolvedStation: nil)
        #expect(outcome.summary == "Receipt attached — fill in the details manually.")
        #expect(outcome.hint == "Couldn't read every number — fill in the rest manually.")
    }

    @Test func theBestDatePrefersTheReceiptDateOverTheCaptureDate() {
        let form = FillUpFormModel()
        let printed = Date(timeIntervalSince1970: 1_700_000_000)
        let captured = Date(timeIntervalSince1970: 1_700_500_000)
        _ = FillUpImportModel.applyReceipt(
            receiptImport(gallons: 10, price: 3.2, purchaseDate: printed, capturedAt: captured),
            to: form, resolvedStation: nil
        )
        #expect(form.date == printed)
    }
}
