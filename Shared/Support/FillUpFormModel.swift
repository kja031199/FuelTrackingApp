import Foundation
import Observation
import SwiftData

/// State and rules for the fill-up form, shared by the iPhone and watch
/// entry screens: live total-cost calculation, validation, odometer
/// sanity check, and saving.
@Observable
final class FillUpFormModel {
    var date: Date = .now
    var odometer: Double?
    var gallons: Double?
    var pricePerGallon: Double?
    var isFullTank = true
    var missedPreviousFillUp = false
    var fuelGrade: FuelGrade = .regular
    var station = ""
    var notes = ""
    var latitude: Double?
    var longitude: Double?
    var receiptImageData: Data?

    /// Entry being edited, or nil when creating a new one.
    private(set) var editedEntry: FuelEntry?

    init() {}

    init(entry: FuelEntry) {
        editedEntry = entry
        date = entry.date
        odometer = entry.odometer
        gallons = entry.gallons
        pricePerGallon = entry.pricePerGallon
        isFullTank = entry.isFullTank
        missedPreviousFillUp = entry.missedPreviousFillUp
        fuelGrade = entry.fuelGrade
        station = entry.station
        notes = entry.notes
        latitude = entry.latitude
        longitude = entry.longitude
        receiptImageData = entry.receiptImageData
    }

    var isEditing: Bool {
        editedEntry != nil
    }

    var totalCost: Double {
        (gallons ?? 0) * (pricePerGallon ?? 0)
    }

    /// The validated draft of the current form, or nil if it can't be saved.
    /// The single point where loose form state becomes a writable entry — all
    /// validation lives in `FuelEntryDraft`, not scattered across callers.
    var draft: FuelEntryDraft? {
        FuelEntryDraft(
            date: date,
            odometer: odometer,
            gallons: gallons,
            pricePerGallon: pricePerGallon,
            isFullTank: isFullTank,
            missedPreviousFillUp: missedPreviousFillUp,
            fuelGrade: fuelGrade,
            station: station,
            notes: notes,
            latitude: latitude,
            longitude: longitude,
            receiptImageData: receiptImageData
        )
    }

    var canSave: Bool { draft != nil }

    /// Highest odometer already logged for the vehicle, for sanity-checking
    /// new entries (editing an old entry legitimately has a lower reading).
    func previousOdometer(for vehicle: Vehicle?) -> Double? {
        guard !isEditing else { return nil }
        return vehicle?.fillUps.map(\.odometer).max()
    }

    func odometerLooksWrong(for vehicle: Vehicle?) -> Bool {
        guard let odometer, let previous = previousOdometer(for: vehicle) else { return false }
        return odometer <= previous
    }

    /// Writes the form into the edited entry, or inserts a new one — always
    /// through the validated `FuelEntryDraft`, never a direct insert.
    func save(to vehicle: Vehicle, in context: ModelContext) {
        guard let draft else { return }

        if let entry = editedEntry {
            draft.apply(to: entry, vehicle: vehicle)
        } else {
            let entry = draft.makeEntry(vehicle: vehicle)
            context.insert(entry)
            // Adopt the inserted entry so a repeated save (e.g. a
            // double-tapped Save button) updates it instead of
            // inserting a duplicate.
            editedEntry = entry
        }
    }

    /// Clears the fields for the next quick entry (watch flow).
    func resetForNextEntry() {
        date = .now
        odometer = nil
        gallons = nil
        pricePerGallon = nil
        isFullTank = true
        missedPreviousFillUp = false
        station = ""
        notes = ""
        latitude = nil
        longitude = nil
        receiptImageData = nil
        // Detach from the previously saved entry so the next save inserts.
        editedEntry = nil
    }
}
