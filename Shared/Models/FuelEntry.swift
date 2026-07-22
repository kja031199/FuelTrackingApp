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
    /// Set when the user forgot to log a fill-up before this one: the MPG
    /// chain restarts here instead of producing a bogus segment.
    var missedPreviousFillUp: Bool = false
    var fuelGradeRaw: String = FuelGrade.regular.rawValue
    var station: String = ""
    var notes: String = ""
    /// Where the fill-up happened, when detected via location services.
    var latitude: Double?
    var longitude: Double?
    /// The pump or receipt photo, kept as a permanent record of the fill-up.
    /// Stored outside the main store (and CloudKit record) so large images
    /// don't bloat every row.
    @Attribute(.externalStorage) var receiptImageData: Data?

    var vehicle: Vehicle?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        odometer: Double,
        gallons: Double,
        pricePerGallon: Double,
        isFullTank: Bool = true,
        missedPreviousFillUp: Bool = false,
        fuelGrade: FuelGrade = .regular,
        station: String = "",
        notes: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        receiptImageData: Data? = nil,
        vehicle: Vehicle? = nil
    ) {
        self.id = id
        self.date = date
        self.odometer = odometer
        self.gallons = gallons
        self.pricePerGallon = pricePerGallon
        self.isFullTank = isFullTank
        self.missedPreviousFillUp = missedPreviousFillUp
        self.fuelGradeRaw = fuelGrade.rawValue
        self.station = station
        self.notes = notes
        self.latitude = latitude
        self.longitude = longitude
        self.receiptImageData = receiptImageData
        self.vehicle = vehicle
    }

    var fuelGrade: FuelGrade {
        get { FuelGrade(rawValue: fuelGradeRaw) ?? .other }
        set { fuelGradeRaw = newValue.rawValue }
    }

    var totalCost: Double {
        gallons * pricePerGallon
    }

    /// Presence check for a usable receipt. Empty data counts as none, so a
    /// stray zero-byte blob never shows a paperclip or an empty thumbnail
    /// slot. Whether the bytes actually decode is the viewer's concern.
    var hasReceipt: Bool {
        !(receiptImageData?.isEmpty ?? true)
    }
}
