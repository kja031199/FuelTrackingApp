import Testing
@testable import FuelTracker

struct OnboardingGateTests {
    @Test func shownForANewUserWithNoVehicles() {
        #expect(OnboardingGate.shouldOnboard(hasCompleted: false, vehicleCount: 0))
    }

    @Test func notShownOnceCompletedOrSkipped() {
        #expect(!OnboardingGate.shouldOnboard(hasCompleted: true, vehicleCount: 0))
    }

    @Test func notShownWhenVehiclesAlreadyExist() {
        // e.g. a fresh install that synced vehicles from iCloud before the
        // completion flag was ever set on this device.
        #expect(!OnboardingGate.shouldOnboard(hasCompleted: false, vehicleCount: 2))
    }

    @Test func notShownWhenCompletedAndVehiclesExist() {
        #expect(!OnboardingGate.shouldOnboard(hasCompleted: true, vehicleCount: 3))
    }
}
