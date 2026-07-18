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
    var fuelGrade: FuelGrade = .regular
    var station = ""
    var notes = ""
    var latitude: Double?
    var longitude: Double?

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
        fuelGrade = entry.fuelGrade
        station = entry.station
        notes = entry.notes
        latitude = entry.latitude
        longitude = entry.longitude
    }

    var isEditing: Bool {
        editedEntry != nil
    }

    var totalCost: Double {
        (gallons ?? 0) * (pricePerGallon ?? 0)
    }

    var canSave: Bool {
        (odometer ?? 0) > 0 && (gallons ?? 0) > 0 && (pricePerGallon ?? 0) > 0
    }

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

    /// Writes the form into the edited entry, or inserts a new one.
    func save(to vehicle: Vehicle, in context: ModelContext) {
        guard canSave, let odometer, let gallons, let pricePerGallon else { return }

        if let entry = editedEntry {
            entry.vehicle = vehicle
            entry.date = date
            entry.odometer = odometer
            entry.gallons = gallons
            entry.pricePerGallon = pricePerGallon
            entry.isFullTank = isFullTank
            entry.fuelGrade = fuelGrade
            entry.station = station
            entry.notes = notes
            entry.latitude = latitude
            entry.longitude = longitude
        } else {
            let entry = FuelEntry(
                date: date,
                odometer: odometer,
                gallons: gallons,
                pricePerGallon: pricePerGallon,
                isFullTank: isFullTank,
                fuelGrade: fuelGrade,
                station: station,
                notes: notes,
                latitude: latitude,
                longitude: longitude,
                vehicle: vehicle
            )
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
        station = ""
        notes = ""
        latitude = nil
        longitude = nil
        // Detach from the previously saved entry so the next save inserts.
        editedEntry = nil
    }
}
