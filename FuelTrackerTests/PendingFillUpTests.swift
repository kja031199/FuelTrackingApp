import Foundation
import SwiftData
import Testing
@testable import FuelTracker

@MainActor
struct PendingFillUpTests {
    private func makeContainer() -> ModelContainer { ModelContainerFactory.makeInMemory() }

    // MARK: - Building from a validated draft

    @Test func fromDraftCopiesEveryField() throws {
        let draft = try #require(FuelEntryDraft(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            odometer: 12_345, gallons: 9.5, pricePerGallon: 3.2,
            isFullTank: false, fuelGrade: .premium, station: "Shell", notes: "topped off",
            latitude: 1, longitude: 2, receiptImageData: Data([1, 2, 3])
        ))
        let vehicleID = UUID()
        let pending = PendingFillUp.from(draft: draft, submitterName: "Alex", vehicleID: vehicleID)

        #expect(pending.submitterName == "Alex")
        #expect(pending.vehicleID == vehicleID)
        #expect(pending.odometer == 12_345)
        #expect(pending.gallons == 9.5)
        #expect(pending.pricePerGallon == 3.2)
        #expect(pending.isFullTank == false)
        #expect(pending.fuelGrade == .premium)
        #expect(pending.station == "Shell")
        #expect(pending.notes == "topped off")
        #expect(pending.receiptImageData == Data([1, 2, 3]))
        #expect(pending.hasReceipt)
        #expect(pending.totalCost == 9.5 * 3.2)
    }

    // MARK: - Validation on review

    @Test func draftIsNilForAnIncompleteSubmission() {
        // A submission with the default zeros can't be promoted to a real entry.
        let bad = PendingFillUp(vehicleID: UUID())
        #expect(bad.draft == nil)
    }

    // MARK: - Approving

    @Test func approvingCreatesAFuelEntryAndClearsTheSubmission() throws {
        let container = makeContainer()
        let vehicle = Vehicle(name: "Civic")
        container.mainContext.insert(vehicle)

        let draft = try #require(FuelEntryDraft(date: .now, odometer: 500, gallons: 12, pricePerGallon: 4, station: "BP"))
        let pending = PendingFillUp.from(draft: draft, submitterName: "Sam", vehicleID: vehicle.id)
        container.mainContext.insert(pending)

        let entry = try #require(pending.approve(onto: vehicle, in: container.mainContext))
        try container.mainContext.save()

        #expect(entry.vehicle?.id == vehicle.id)
        #expect(entry.odometer == 500)
        #expect(entry.gallons == 12)
        #expect(entry.station == "BP")

        // Exactly one real entry, and the submission is gone from the queue.
        #expect(try container.mainContext.fetch(FetchDescriptor<FuelEntry>()).count == 1)
        #expect(try container.mainContext.fetch(FetchDescriptor<PendingFillUp>()).isEmpty)
    }

    @Test func approvingAnInvalidSubmissionDoesNothing() throws {
        let container = makeContainer()
        let vehicle = Vehicle(name: "Civic")
        container.mainContext.insert(vehicle)

        let bad = PendingFillUp(vehicleID: vehicle.id) // zeros → fails validation
        container.mainContext.insert(bad)

        #expect(bad.approve(onto: vehicle, in: container.mainContext) == nil)
        try container.mainContext.save()

        // No entry written, and the bad submission is left in the queue.
        #expect(try container.mainContext.fetch(FetchDescriptor<FuelEntry>()).isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<PendingFillUp>()).count == 1)
    }

    @Test func approveCarriesEveryFieldOntoTheNewEntry() throws {
        // Approval must preserve the whole submission, not just the numbers —
        // grade, fill flag, station, notes, coordinates, and the receipt.
        let container = makeContainer()
        let vehicle = Vehicle(name: "Civic")
        container.mainContext.insert(vehicle)

        let receipt = Data([9, 8, 7])
        let draft = try #require(FuelEntryDraft(
            date: Date(timeIntervalSince1970: 1_600_000_000),
            odometer: 30_000, gallons: 14.25, pricePerGallon: 4.10,
            isFullTank: false, fuelGrade: .diesel, station: "Costco",
            notes: "diesel run", latitude: 47.6, longitude: -122.3,
            receiptImageData: receipt
        ))
        let pending = PendingFillUp.from(draft: draft, submitterName: "Robin", vehicleID: vehicle.id)
        container.mainContext.insert(pending)

        let entry = try #require(pending.approve(onto: vehicle, in: container.mainContext))
        #expect(entry.date == draft.date)
        #expect(entry.odometer == 30_000)
        #expect(entry.gallons == 14.25)
        #expect(entry.pricePerGallon == 4.10)
        #expect(entry.isFullTank == false)
        #expect(entry.fuelGrade == .diesel)
        #expect(entry.station == "Costco")
        #expect(entry.notes == "diesel run")
        #expect(entry.latitude == 47.6)
        #expect(entry.longitude == -122.3)
        #expect(entry.receiptImageData == receipt)
    }

    @Test func approvingOneSubmissionLeavesTheRestOfTheQueue() throws {
        let container = makeContainer()
        let vehicle = Vehicle(name: "Civic")
        container.mainContext.insert(vehicle)

        let first = PendingFillUp.from(
            draft: try #require(FuelEntryDraft(date: .now, odometer: 100, gallons: 8, pricePerGallon: 3)),
            submitterName: "First", vehicleID: vehicle.id
        )
        let second = PendingFillUp.from(
            draft: try #require(FuelEntryDraft(date: .now, odometer: 200, gallons: 9, pricePerGallon: 3)),
            submitterName: "Second", vehicleID: vehicle.id
        )
        container.mainContext.insert(first)
        container.mainContext.insert(second)

        first.approve(onto: vehicle, in: container.mainContext)
        try container.mainContext.save()

        let remaining = try container.mainContext.fetch(FetchDescriptor<PendingFillUp>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.submitterName == "Second")
        #expect(try container.mainContext.fetch(FetchDescriptor<FuelEntry>()).count == 1)
    }

    // MARK: - from(draft:) fidelity

    @Test func fromPreservesAnExplicitSubmittedAt() throws {
        let when = Date(timeIntervalSince1970: 1_234_567_890)
        let draft = try #require(FuelEntryDraft(date: .now, odometer: 100, gallons: 5, pricePerGallon: 3))
        let pending = PendingFillUp.from(draft: draft, submitterName: "X", vehicleID: UUID(), submittedAt: when)
        #expect(pending.submittedAt == when)
    }

    // MARK: - Fuel grade round-trip

    @Test func fuelGradeGetterFallsBackToOtherForAnUnrecognizedRawValue() {
        // A grade string from a buggy or hostile source must degrade to a
        // known case rather than trapping when the picker reads it back.
        let pending = PendingFillUp(vehicleID: UUID())
        pending.fuelGradeRaw = "Plutonium"
        #expect(pending.fuelGrade == .other)
    }

    @Test func fuelGradeSetterWritesThroughToTheRawValue() {
        let pending = PendingFillUp(vehicleID: UUID())
        pending.fuelGrade = .e85
        #expect(pending.fuelGradeRaw == "E85")
        #expect(pending.fuelGrade == .e85)
    }

    // MARK: - Receipt presence

    @Test func hasReceiptIsFalseForNoDataAndForEmptyData() {
        #expect(!PendingFillUp(vehicleID: UUID()).hasReceipt)
        // A stray zero-byte blob must not count as a receipt.
        #expect(!PendingFillUp(vehicleID: UUID(), receiptImageData: Data()).hasReceipt)
    }

    // MARK: - Hostile numeric fields

    @Test(arguments: [
        (odometer: 0.0, gallons: 10.0, price: 3.0),
        (odometer: -1.0, gallons: 10.0, price: 3.0),
        (odometer: 12_000.0, gallons: 0.0, price: 3.0),
        (odometer: 12_000.0, gallons: -5.0, price: 3.0),
        (odometer: 12_000.0, gallons: 10.0, price: 0.0),
        (odometer: 12_000.0, gallons: 10.0, price: -3.0),
        (odometer: Double.nan, gallons: 10.0, price: 3.0),
        (odometer: 12_000.0, gallons: Double.nan, price: 3.0),
        (odometer: 12_000.0, gallons: 10.0, price: Double.nan),
        (odometer: Double.infinity, gallons: 10.0, price: 3.0),
        (odometer: 12_000.0, gallons: Double.infinity, price: 3.0),
        (odometer: 12_000.0, gallons: 10.0, price: Double.infinity),
    ])
    func draftAndApproveRejectAnyInvalidNumber(
        _ input: (odometer: Double, gallons: Double, price: Double)
    ) throws {
        // A crafted or corrupted record with a non-positive, NaN, or infinite
        // number must never become a real entry, and must stay in the queue.
        let container = makeContainer()
        let vehicle = Vehicle(name: "Civic")
        container.mainContext.insert(vehicle)

        let bad = PendingFillUp(
            vehicleID: vehicle.id,
            odometer: input.odometer, gallons: input.gallons, pricePerGallon: input.price
        )
        container.mainContext.insert(bad)

        #expect(bad.draft == nil)
        #expect(bad.approve(onto: vehicle, in: container.mainContext) == nil)
        try container.mainContext.save()
        #expect(try container.mainContext.fetch(FetchDescriptor<FuelEntry>()).isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<PendingFillUp>()).count == 1)
    }

    @Test func approveDropsAnOversizedReceiptAtTheWriteBoundary() throws {
        // A blob past the 4 MB ceiling can only come from a bypassed intake
        // path or a bad sync. The record may still claim a receipt, but
        // promotion must drop the unbounded blob rather than persist it.
        let container = makeContainer()
        let vehicle = Vehicle(name: "Civic")
        container.mainContext.insert(vehicle)

        let oversized = Data(count: FuelEntryDraft.maxReceiptBytes + 1)
        let pending = PendingFillUp(
            vehicleID: vehicle.id, odometer: 100, gallons: 8, pricePerGallon: 3,
            receiptImageData: oversized
        )
        container.mainContext.insert(pending)
        #expect(pending.hasReceipt)

        let entry = try #require(pending.approve(onto: vehicle, in: container.mainContext))
        #expect(entry.receiptImageData == nil)
    }
}
