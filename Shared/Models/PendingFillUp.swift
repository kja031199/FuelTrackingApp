import Foundation
import SwiftData

/// A fill-up submitted by someone else — e.g. a family member who filled the
/// car and sent it in — waiting for the owner to review and approve.
///
/// It mirrors the `FuelEntry` fields plus who submitted it and when, and it
/// targets a vehicle by **id** rather than a relationship so a submission can
/// arrive and live independently of the owner's `Vehicle` objects — the shape a
/// shared/synced record needs. Approving it turns it into a real `FuelEntry`
/// through the same `FuelEntryDraft` validation every entry passes, so a
/// submission from an outside person can't bypass the checks.
///
/// The delivery mechanism (a shared link over CloudKit) is deliberately not
/// part of this type — this is the local model and review flow that runs today;
/// the transport plugs in later without changing how a submission is reviewed.
@Model
final class PendingFillUp {
    var id: UUID = UUID()
    var submittedAt: Date = Date.now
    var submitterName: String = ""
    var vehicleID: UUID = UUID()

    var date: Date = Date.now
    var odometer: Double = 0
    var gallons: Double = 0
    var pricePerGallon: Double = 0
    var isFullTank: Bool = true
    var fuelGradeRaw: String = FuelGrade.regular.rawValue
    var station: String = ""
    var notes: String = ""
    var latitude: Double?
    var longitude: Double?
    @Attribute(.externalStorage) var receiptImageData: Data?

    init(
        id: UUID = UUID(),
        submittedAt: Date = .now,
        submitterName: String = "",
        vehicleID: UUID,
        date: Date = .now,
        odometer: Double = 0,
        gallons: Double = 0,
        pricePerGallon: Double = 0,
        isFullTank: Bool = true,
        fuelGrade: FuelGrade = .regular,
        station: String = "",
        notes: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        receiptImageData: Data? = nil
    ) {
        self.id = id
        self.submittedAt = submittedAt
        self.submitterName = submitterName
        self.vehicleID = vehicleID
        self.date = date
        self.odometer = odometer
        self.gallons = gallons
        self.pricePerGallon = pricePerGallon
        self.isFullTank = isFullTank
        self.fuelGradeRaw = fuelGrade.rawValue
        self.station = station
        self.notes = notes
        self.latitude = latitude
        self.longitude = longitude
        self.receiptImageData = receiptImageData
    }

    /// Builds a pending submission from a validated draft.
    static func from(draft: FuelEntryDraft, submitterName: String, vehicleID: UUID, submittedAt: Date = .now) -> PendingFillUp {
        PendingFillUp(
            submittedAt: submittedAt,
            submitterName: submitterName,
            vehicleID: vehicleID,
            date: draft.date,
            odometer: draft.odometer,
            gallons: draft.gallons,
            pricePerGallon: draft.pricePerGallon,
            isFullTank: draft.isFullTank,
            fuelGrade: draft.fuelGrade,
            station: draft.station,
            notes: draft.notes,
            latitude: draft.latitude,
            longitude: draft.longitude,
            receiptImageData: draft.receiptImageData
        )
    }

    var fuelGrade: FuelGrade {
        get { FuelGrade(rawValue: fuelGradeRaw) ?? .other }
        set { fuelGradeRaw = newValue.rawValue }
    }

    var totalCost: Double { gallons * pricePerGallon }

    var hasReceipt: Bool { !(receiptImageData?.isEmpty ?? true) }

    /// The submission re-validated as a draft — nil if it doesn't pass the same
    /// checks a real entry must (positive odometer, gallons, and price).
    var draft: FuelEntryDraft? {
        FuelEntryDraft(
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
            receiptImageData: receiptImageData
        )
    }

    /// Promotes the reviewed submission into a real fill-up on `vehicle` and
    /// removes it from the queue. Returns the created entry, or nil if it fails
    /// validation (in which case it's left in the queue).
    @discardableResult
    func approve(onto vehicle: Vehicle, in context: ModelContext) -> FuelEntry? {
        guard let draft else { return nil }
        let entry = draft.makeEntry(vehicle: vehicle)
        context.insert(entry)
        context.delete(self)
        return entry
    }
}
