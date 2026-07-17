import Foundation
import SwiftData

// CloudKit-synced models can't use unique constraints and every attribute
// needs a default value.
@Model
final class FuelEntry {
    var id: UUID = UUID()
    var date: Date = Date.now
    /// Odometer reading at the time of the fill-up, in miles.
    var odometer: Double = 0
    var gallons: Double = 0
    var pricePerGallon: Double = 0
    /// A full tank lets the app compute exact MPG between fills.
    var isFullTank: Bool = true
    var fuelGradeRaw: String = FuelGrade.regular.rawValue
    var station: String = ""
    var notes: String = ""

    var vehicle: Vehicle?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        odometer: Double,
        gallons: Double,
        pricePerGallon: Double,
        isFullTank: Bool = true,
        fuelGrade: FuelGrade = .regular,
        station: String = "",
        notes: String = "",
        vehicle: Vehicle? = nil
    ) {
        self.id = id
        self.date = date
        self.odometer = odometer
        self.gallons = gallons
        self.pricePerGallon = pricePerGallon
        self.isFullTank = isFullTank
        self.fuelGradeRaw = fuelGrade.rawValue
        self.station = station
        self.notes = notes
        self.vehicle = vehicle
    }

    var fuelGrade: FuelGrade {
        get { FuelGrade(rawValue: fuelGradeRaw) ?? .other }
        set { fuelGradeRaw = newValue.rawValue }
    }

    var totalCost: Double {
        gallons * pricePerGallon
    }
}
