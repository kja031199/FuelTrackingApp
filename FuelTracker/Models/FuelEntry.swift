import Foundation
import SwiftData

@Model
final class FuelEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    /// Odometer reading at the time of the fill-up, in miles.
    var odometer: Double
    var gallons: Double
    var pricePerGallon: Double
    /// A full tank lets the app compute exact MPG between fills.
    var isFullTank: Bool
    var fuelGradeRaw: String
    var station: String
    var notes: String

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
