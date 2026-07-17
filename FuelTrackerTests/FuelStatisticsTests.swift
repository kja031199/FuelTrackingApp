import Foundation
import SwiftData
import Testing
@testable import FuelTracker

/// Keeps an in-memory SwiftData container alive for a test's model objects.
@MainActor
private struct TestStore {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() {
        container = ModelContainerFactory.makeInMemory()
    }

    func insert(_ entries: [FuelEntry]) {
        for entry in entries {
            context.insert(entry)
        }
    }
}

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
}

private func entry(
    _ year: Int, _ month: Int, _ day: Int,
    odometer: Double,
    gallons: Double,
    price: Double,
    fullTank: Bool = true
) -> FuelEntry {
    FuelEntry(
        date: date(year, month, day),
        odometer: odometer,
        gallons: gallons,
        pricePerGallon: price,
        isFullTank: fullTank
    )
}

@MainActor
struct FuelStatisticsTests {
    /// Three full tanks: baseline, then 300 mi / 10 gal, then 400 mi / 12.5 gal.
    private func standardEntries() -> [FuelEntry] {
        [
            entry(2025, 1, 5, odometer: 10_000, gallons: 12, price: 3.00),
            entry(2025, 1, 20, odometer: 10_300, gallons: 10, price: 3.50),
            entry(2025, 2, 3, odometer: 10_700, gallons: 12.5, price: 4.00),
        ]
    }

    @Test func emptyEntriesProduceNoStatistics() {
        let statistics = FuelStatistics(entries: [])
        #expect(statistics.fillUpCount == 0)
        #expect(statistics.totalSpent == 0)
        #expect(statistics.averageMPG == nil)
        #expect(statistics.costPerMile == nil)
        #expect(statistics.mpgPoints.isEmpty)
        #expect(statistics.monthlyTotals.isEmpty)
    }

    @Test func mpgIsComputedBetweenConsecutiveFullTanks() {
        let store = TestStore()
        let entries = standardEntries()
        store.insert(entries)

        let statistics = FuelStatistics(entries: entries)

        #expect(statistics.mpgPoints.count == 2)
        #expect(abs(statistics.mpgPoints[0].mpg - 30.0) < 0.0001)
        #expect(abs(statistics.mpgPoints[1].mpg - 32.0) < 0.0001)
    }

    @Test func firstFillUpIsBaselineWithoutItsOwnMPG() {
        let store = TestStore()
        let entries = standardEntries()
        store.insert(entries)

        let statistics = FuelStatistics(entries: entries)

        #expect(statistics.mpg(for: entries[0]) == nil)
        #expect(statistics.mpg(for: entries[1]) != nil)
    }

    @Test func partialFillGallonsRollIntoNextFullTankSegment() {
        let store = TestStore()
        let entries = [
            entry(2025, 3, 1, odometer: 10_000, gallons: 10, price: 3.00),
            entry(2025, 3, 8, odometer: 10_200, gallons: 4, price: 3.00, fullTank: false),
            entry(2025, 3, 15, odometer: 10_400, gallons: 6, price: 3.00),
        ]
        store.insert(entries)

        let statistics = FuelStatistics(entries: entries)

        // One segment: 400 miles on 4 + 6 gallons = 40 MPG. The partial fill
        // never gets an MPG of its own.
        #expect(statistics.mpgPoints.count == 1)
        #expect(abs(statistics.mpgPoints[0].mpg - 40.0) < 0.0001)
        #expect(statistics.mpg(for: entries[1]) == nil)
    }

    @Test func averageMPGIsTotalMilesOverTotalGallonsNotAnAverageOfAverages() throws {
        let store = TestStore()
        let entries = standardEntries()
        store.insert(entries)

        let statistics = FuelStatistics(entries: entries)

        // 700 miles / 22.5 gallons ≈ 31.111, not (30 + 32) / 2 = 31.
        let average = try #require(statistics.averageMPG)
        #expect(abs(average - 700.0 / 22.5) < 0.0001)
    }

    @Test func spendingTotalsAndWeightedAveragePrice() throws {
        let store = TestStore()
        let entries = standardEntries()
        store.insert(entries)

        let statistics = FuelStatistics(entries: entries)

        // 12×3.00 + 10×3.50 + 12.5×4.00 = 36 + 35 + 50 = 121
        #expect(abs(statistics.totalSpent - 121.0) < 0.0001)
        #expect(abs(statistics.totalGallons - 34.5) < 0.0001)

        let averagePrice = try #require(statistics.averagePricePerGallon)
        #expect(abs(averagePrice - 121.0 / 34.5) < 0.0001)

        // Latest entry by date, not by list order.
        #expect(statistics.lastPricePerGallon == 4.00)
    }

    @Test func costPerMileExcludesTheBaselineFill() throws {
        let store = TestStore()
        let entries = standardEntries()
        store.insert(entries)

        let statistics = FuelStatistics(entries: entries)

        // The first fill's fuel was burned before tracking started, so cost
        // per mile only counts fuel bought after the baseline: (35 + 50) / 700.
        let costPerMile = try #require(statistics.costPerMile)
        #expect(abs(costPerMile - 85.0 / 700.0) < 0.0001)
        #expect(statistics.milesTracked == 700)
    }

    @Test func monthlyTotalsGroupByCalendarMonth() {
        let store = TestStore()
        let entries = standardEntries()
        store.insert(entries)

        let statistics = FuelStatistics(entries: entries)

        #expect(statistics.monthlyTotals.count == 2)

        let january = statistics.monthlyTotals[0]
        #expect(january.fillUpCount == 2)
        #expect(abs(january.totalSpent - 71.0) < 0.0001)
        #expect(january.miles == 300)

        let february = statistics.monthlyTotals[1]
        #expect(february.fillUpCount == 1)
        #expect(abs(february.totalSpent - 50.0) < 0.0001)
    }

    @Test func chartSeriesMatchTheirSourcePoints() {
        let store = TestStore()
        let entries = standardEntries()
        store.insert(entries)

        let statistics = FuelStatistics(entries: entries)

        #expect(statistics.mpgSeries.map(\.value) == statistics.mpgPoints.map(\.mpg))
        #expect(statistics.priceSeries.map(\.value) == statistics.pricePoints.map(\.pricePerGallon))
        #expect(statistics.odometerSeries.map(\.value) == statistics.odometerPoints.map(\.odometer))
    }
}

@MainActor
struct FillUpFormModelTests {
    @Test func totalCostIsGallonsTimesPrice() {
        let form = FillUpFormModel()
        form.gallons = 10
        form.pricePerGallon = 3.499
        #expect(abs(form.totalCost - 34.99) < 0.0001)
    }

    @Test func canSaveRequiresAllNumericFields() {
        let form = FillUpFormModel()
        #expect(!form.canSave)
        form.odometer = 12_000
        form.gallons = 10
        #expect(!form.canSave)
        form.pricePerGallon = 3.50
        #expect(form.canSave)
    }

    @Test func saveInsertsANewEntryForTheVehicle() throws {
        let store = TestStore()
        let vehicle = Vehicle(name: "Test Car")
        store.context.insert(vehicle)

        let form = FillUpFormModel()
        form.odometer = 12_000
        form.gallons = 10
        form.pricePerGallon = 3.50
        form.station = "Costco"
        form.save(to: vehicle, in: store.context)

        #expect(vehicle.fillUps.count == 1)
        let saved = try #require(vehicle.fillUps.first)
        #expect(saved.odometer == 12_000)
        #expect(abs(saved.totalCost - 35.0) < 0.0001)
        #expect(saved.station == "Costco")
    }

    @Test func editingPopulatesAndUpdatesTheExistingEntry() {
        let store = TestStore()
        let vehicle = Vehicle(name: "Test Car")
        store.context.insert(vehicle)
        let existing = FuelEntry(odometer: 12_000, gallons: 10, pricePerGallon: 3.50, vehicle: vehicle)
        store.context.insert(existing)

        let form = FillUpFormModel(entry: existing)
        #expect(form.isEditing)
        #expect(form.odometer == 12_000)

        form.gallons = 11
        form.save(to: vehicle, in: store.context)

        #expect(vehicle.fillUps.count == 1)
        #expect(existing.gallons == 11)
    }

    @Test func odometerWarningComparesAgainstTheVehiclesLatestReading() {
        let store = TestStore()
        let vehicle = Vehicle(name: "Test Car")
        store.context.insert(vehicle)
        store.context.insert(FuelEntry(odometer: 12_000, gallons: 10, pricePerGallon: 3.50, vehicle: vehicle))

        let form = FillUpFormModel()
        form.odometer = 11_500
        #expect(form.odometerLooksWrong(for: vehicle))
        form.odometer = 12_300
        #expect(!form.odometerLooksWrong(for: vehicle))
    }

    @Test func resetClearsFieldsForTheNextQuickEntry() {
        let form = FillUpFormModel()
        form.odometer = 12_000
        form.gallons = 10
        form.pricePerGallon = 3.50
        form.isFullTank = false
        form.resetForNextEntry()

        #expect(form.odometer == nil)
        #expect(form.gallons == nil)
        #expect(form.pricePerGallon == nil)
        #expect(form.isFullTank)
    }
}
