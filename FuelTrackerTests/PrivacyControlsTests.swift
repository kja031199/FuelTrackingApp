import Foundation
import SwiftData
import Testing
@testable import FuelTracker

// MARK: - Purging saved locations

@MainActor
struct LocationPrivacyTests {
    @Test func purgeClearsCoordinatesButKeepsEntriesAndOtherFields() throws {
        let container = ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = Vehicle(name: "Civic")
        context.insert(vehicle)

        let located = FuelEntry(
            odometer: 1_000, gallons: 10, pricePerGallon: 3, station: "Shell",
            latitude: 37.5, longitude: -122.5, vehicle: vehicle
        )
        let noLocation = FuelEntry(odometer: 1_300, gallons: 9, pricePerGallon: 3.1, vehicle: vehicle)
        context.insert(located)
        context.insert(noLocation)

        let pending = PendingFillUp(
            vehicleID: vehicle.id, odometer: 500, gallons: 8, pricePerGallon: 3,
            latitude: 1, longitude: 2
        )
        context.insert(pending)

        let cleared = LocationPrivacy.purgeSavedLocations(in: context)
        try context.save()

        // One entry + one pending had coordinates.
        #expect(cleared == 2)

        // Coordinates gone, everything else intact.
        #expect(located.latitude == nil)
        #expect(located.longitude == nil)
        #expect(located.station == "Shell")
        #expect(located.gallons == 10)
        #expect(pending.latitude == nil)
        #expect(pending.longitude == nil)

        // No records were deleted.
        #expect(try context.fetch(FetchDescriptor<FuelEntry>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<PendingFillUp>()).count == 1)
    }

    @Test func purgeReturnsZeroWhenNothingHasCoordinates() {
        let container = ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = Vehicle(name: "Civic")
        context.insert(vehicle)
        context.insert(FuelEntry(odometer: 1, gallons: 1, pricePerGallon: 1, vehicle: vehicle))

        #expect(LocationPrivacy.purgeSavedLocations(in: context) == 0)
    }
}

// MARK: - Privacy preference store

struct PrivacySettingsTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.privacy.\(UUID().uuidString)")!
    }

    @Test func defaultsToLocationCaptureOn() {
        // Never-set defaults to on (station detection is consented via iOS).
        #expect(PrivacySettings(defaults: freshDefaults()).locationCaptureEnabled)
    }

    @Test func disablingCapturePersistsAcrossReload() {
        let defaults = freshDefaults()
        let settings = PrivacySettings(defaults: defaults)
        settings.locationCaptureEnabled = false
        // A stored false must survive — distinct from "never set" (→ on).
        #expect(PrivacySettings(defaults: defaults).locationCaptureEnabled == false)
    }
}
