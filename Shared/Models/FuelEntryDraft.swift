import Foundation

/// A validated fill-up ready to be written to the store.
///
/// Every new or edited entry passes through here: construction **fails** unless
/// the required numeric fields are present and positive, so no code path can
/// insert an unvalidated entry. Any future source of fill-ups — for example a
/// shared-link submission from another person — builds one of these too, which
/// keeps validation in exactly one place instead of trusting each caller.
///
/// It also owns the single field-by-field mapping onto `FuelEntry`, so adding a
/// field means touching one method rather than several scattered copies.
struct FuelEntryDraft {
    let date: Date
    let odometer: Double
    let gallons: Double
    let pricePerGallon: Double
    let isFullTank: Bool
    let missedPreviousFillUp: Bool
    let fuelGrade: FuelGrade
    let station: String
    let notes: String
    let latitude: Double?
    let longitude: Double?
    let receiptImageData: Data?

    /// A sanitized receipt is a couple hundred KB. Anything past this ceiling
    /// at the write boundary means the bounded image-intake path was bypassed,
    /// so the blob is dropped rather than persisted (and synced) unbounded.
    static let maxReceiptBytes = 4 * 1024 * 1024

    /// Fails when odometer, gallons, or price-per-gallon is missing, not
    /// positive, or not finite — the same rule the form's Save button
    /// enforces. `NaN` fails the `> 0` test already; the explicit `isFinite`
    /// also rejects `+∞`, which would otherwise slip through as "positive"
    /// from a crafted or corrupted synced record and poison every statistic.
    init?(
        date: Date,
        odometer: Double?,
        gallons: Double?,
        pricePerGallon: Double?,
        isFullTank: Bool = true,
        missedPreviousFillUp: Bool = false,
        fuelGrade: FuelGrade = .regular,
        station: String = "",
        notes: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        receiptImageData: Data? = nil
    ) {
        guard let odometer, odometer > 0, odometer.isFinite,
              let gallons, gallons > 0, gallons.isFinite,
              let pricePerGallon, pricePerGallon > 0, pricePerGallon.isFinite else {
            return nil
        }
        self.date = date
        self.odometer = odometer
        self.gallons = gallons
        self.pricePerGallon = pricePerGallon
        self.isFullTank = isFullTank
        self.missedPreviousFillUp = missedPreviousFillUp
        self.fuelGrade = fuelGrade
        self.station = station
        self.notes = notes
        self.latitude = latitude
        self.longitude = longitude
        if let receiptImageData, receiptImageData.count <= Self.maxReceiptBytes {
            self.receiptImageData = receiptImageData
        } else {
            self.receiptImageData = nil
        }
    }

    /// The single source of the entry field mapping. Writing a new entry goes
    /// through `makeEntry`, which builds a bare entry and applies here.
    func apply(to entry: FuelEntry, vehicle: Vehicle) {
        entry.vehicle = vehicle
        entry.date = date
        entry.odometer = odometer
        entry.gallons = gallons
        entry.pricePerGallon = pricePerGallon
        entry.isFullTank = isFullTank
        entry.missedPreviousFillUp = missedPreviousFillUp
        entry.fuelGrade = fuelGrade
        entry.station = station
        entry.notes = notes
        entry.latitude = latitude
        entry.longitude = longitude
        entry.receiptImageData = receiptImageData
    }

    func makeEntry(vehicle: Vehicle) -> FuelEntry {
        let entry = FuelEntry(odometer: odometer, gallons: gallons, pricePerGallon: pricePerGallon)
        apply(to: entry, vehicle: vehicle)
        return entry
    }
}
