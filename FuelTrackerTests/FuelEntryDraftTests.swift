import Foundation
import SwiftData
import Testing
@testable import FuelTracker

@MainActor
struct FuelEntryDraftTests {
    private func makeVehicle() -> (ModelContainer, Vehicle) {
        let container = ModelContainerFactory.makeInMemory()
        let vehicle = Vehicle(name: "Test")
        container.mainContext.insert(vehicle)
        return (container, vehicle)
    }

    // MARK: - Validation

    @Test func requiresPositiveOdometerGallonsAndPrice() {
        // A missing or non-positive required field means no draft — and so no
        // way to write the entry.
        #expect(FuelEntryDraft(date: .now, odometer: nil, gallons: 10, pricePerGallon: 3) == nil)
        #expect(FuelEntryDraft(date: .now, odometer: 100, gallons: nil, pricePerGallon: 3) == nil)
        #expect(FuelEntryDraft(date: .now, odometer: 100, gallons: 10, pricePerGallon: nil) == nil)
        #expect(FuelEntryDraft(date: .now, odometer: 0, gallons: 10, pricePerGallon: 3) == nil)
        #expect(FuelEntryDraft(date: .now, odometer: 100, gallons: -1, pricePerGallon: 3) == nil)
        #expect(FuelEntryDraft(date: .now, odometer: 100, gallons: 10, pricePerGallon: 0) == nil)
    }

    @Test func acceptsAValidFillUp() throws {
        let draft = try #require(FuelEntryDraft(date: .now, odometer: 100, gallons: 10, pricePerGallon: 3))
        #expect(draft.odometer == 100)
        #expect(draft.gallons == 10)
        #expect(draft.pricePerGallon == 3)
    }

    // MARK: - Mapping (the single field list)

    @Test func makeEntryProducesAFullyPopulatedEntry() throws {
        let (container, vehicle) = makeVehicle()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let draft = try #require(FuelEntryDraft(
            date: date, odometer: 12_345, gallons: 9.5, pricePerGallon: 3.2,
            isFullTank: false, missedPreviousFillUp: true, fuelGrade: .premium,
            station: "Shell", notes: "topped off", latitude: 1, longitude: 2,
            receiptImageData: Data([1, 2, 3])
        ))
        let entry = draft.makeEntry(vehicle: vehicle)
        container.mainContext.insert(entry)

        #expect(entry.vehicle?.id == vehicle.id)
        #expect(entry.date == date)
        #expect(entry.odometer == 12_345)
        #expect(entry.gallons == 9.5)
        #expect(entry.pricePerGallon == 3.2)
        #expect(entry.isFullTank == false)
        #expect(entry.missedPreviousFillUp == true)
        #expect(entry.fuelGrade == .premium)
        #expect(entry.station == "Shell")
        #expect(entry.notes == "topped off")
        #expect(entry.latitude == 1)
        #expect(entry.longitude == 2)
        #expect(entry.receiptImageData == Data([1, 2, 3]))
    }

    @Test func applyOverwritesEveryFieldOnAnExistingEntry() throws {
        let (container, vehicle) = makeVehicle()
        let entry = FuelEntry(odometer: 1, gallons: 1, pricePerGallon: 1, station: "Old")
        container.mainContext.insert(entry)

        let draft = try #require(FuelEntryDraft(
            date: .now, odometer: 500, gallons: 12, pricePerGallon: 4,
            fuelGrade: .diesel, station: "New", notes: "changed"
        ))
        draft.apply(to: entry, vehicle: vehicle)

        #expect(entry.odometer == 500)
        #expect(entry.gallons == 12)
        #expect(entry.pricePerGallon == 4)
        #expect(entry.fuelGrade == .diesel)
        #expect(entry.station == "New")
        #expect(entry.notes == "changed")
        #expect(entry.vehicle?.id == vehicle.id)
    }

    // MARK: - Receipt size ceiling (defence in depth)

    @Test func dropsAnOversizeReceiptButKeepsANormalOne() throws {
        let normal = Data(repeating: 0xAB, count: 1_000)
        let kept = try #require(FuelEntryDraft(date: .now, odometer: 1, gallons: 1, pricePerGallon: 1, receiptImageData: normal))
        #expect(kept.receiptImageData == normal)

        let huge = Data(repeating: 0xAB, count: FuelEntryDraft.maxReceiptBytes + 1)
        let trimmed = try #require(FuelEntryDraft(date: .now, odometer: 1, gallons: 1, pricePerGallon: 1, receiptImageData: huge))
        #expect(trimmed.receiptImageData == nil)
    }
}
