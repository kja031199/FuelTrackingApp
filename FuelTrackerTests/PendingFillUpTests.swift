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
}
