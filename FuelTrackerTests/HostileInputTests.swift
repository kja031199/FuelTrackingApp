import Foundation
import SwiftData
import Testing
@testable import FuelTracker

// Tests for inputs the app should never receive from a well-behaved user —
// but could receive from typos, double-taps, clock changes, odometer
// replacements, OCR noise, or synced data from a buggy build. The bar:
// never crash, never divide by zero, never fabricate a statistic.

private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int, hour: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: hour))!
}

private func makeEntry(
    on date: Date = day(2025, 1, 5),
    odometer: Double,
    gallons: Double,
    price: Double,
    fullTank: Bool = true
) -> FuelEntry {
    FuelEntry(date: date, odometer: odometer, gallons: gallons, pricePerGallon: price, isFullTank: fullTank)
}

// MARK: - Statistics under hostile data

@MainActor
struct StatisticsHostileInputTests {
    @Test func zeroGallonFullTankProducesNoMPGButAdvancesBaseline() {
        // A $0.00 / 0-gallon entry can appear from an aborted pump session
        // logged anyway. It must not divide by zero, and the next segment
        // must measure from it, not across it.
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 1_000, gallons: 10, price: 3.0),
            makeEntry(on: day(2025, 1, 5), odometer: 1_300, gallons: 0, price: 3.0),
            makeEntry(on: day(2025, 1, 10), odometer: 1_600, gallons: 10, price: 3.0),
        ]
        let statistics = FuelStatistics(entries: entries)
        #expect(statistics.mpgPoints.count == 1)
        #expect(abs(statistics.mpgPoints[0].mpg - 30.0) < 0.0001)
        #expect(statistics.totalGallons == 20)
    }

    @Test func negativeGallonsNeverProduceAnMPGPoint() {
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 1_000, gallons: 10, price: 3.0),
            makeEntry(on: day(2025, 1, 5), odometer: 1_300, gallons: -5, price: 3.0),
        ]
        let statistics = FuelStatistics(entries: entries)
        // Segment gallons are negative, so the guard must reject the point.
        #expect(statistics.mpgPoints.isEmpty)
        #expect(statistics.averageMPG == nil)
        // Spend after the baseline is negative, so cost/mile must refuse too.
        #expect(statistics.costPerMile == nil)
    }

    @Test func duplicateOdometerEntriesYieldZeroedNotCrashedMetrics() {
        // The same fill logged twice (sync hiccup or double entry).
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 1_000, gallons: 10, price: 3.0),
            makeEntry(on: day(2025, 1, 1), odometer: 1_000, gallons: 10, price: 3.0),
        ]
        let statistics = FuelStatistics(entries: entries)
        #expect(statistics.mpgPoints.isEmpty)
        #expect(statistics.milesTracked == 0)
        #expect(statistics.costPerMile == nil)
        #expect(statistics.averageMilesBetweenFillUps == 0)
        #expect(statistics.totalSpent == 60)
    }

    @Test func clockSkewDatesDoNotAffectOdometerBasedMPG() {
        // Dates running backwards (phone clock fixed between fills) while
        // the odometer marches forward: MPG math follows the odometer.
        let entries = [
            makeEntry(on: day(2025, 3, 10), odometer: 1_000, gallons: 10, price: 3.0),
            makeEntry(on: day(2025, 3, 1), odometer: 1_300, gallons: 10, price: 3.0),
        ]
        let statistics = FuelStatistics(entries: entries)
        #expect(statistics.mpgPoints.count == 1)
        #expect(abs(statistics.mpgPoints[0].mpg - 30.0) < 0.0001)
        // And the price trend follows sorted odometer order without crashing.
        #expect(statistics.pricePoints.count == 2)
    }

    @Test func futureDatedEntriesAreCountedNotDropped() {
        let entries = [
            makeEntry(on: day(2030, 6, 1), odometer: 1_000, gallons: 10, price: 3.0),
        ]
        let statistics = FuelStatistics(entries: entries)
        #expect(statistics.fillUpCount == 1)
        #expect(statistics.monthlyTotals.count == 1)
    }

    @Test func entriesHoursApartHaveNoMonthlySpendExtrapolation() {
        // Two fills six hours apart would extrapolate to an absurd monthly
        // number; the guard requires at least a one-day span.
        let entries = [
            makeEntry(on: day(2025, 1, 1, hour: 8), odometer: 1_000, gallons: 10, price: 3.0),
            makeEntry(on: day(2025, 1, 1, hour: 14), odometer: 1_300, gallons: 10, price: 3.0),
        ]
        #expect(FuelStatistics(entries: entries).averageMonthlySpend == nil)
    }

    @Test func monthlyTotalsSortCorrectlyAcrossAYearBoundary() {
        let entries = [
            makeEntry(on: day(2025, 1, 5), odometer: 1_300, gallons: 10, price: 3.0),
            makeEntry(on: day(2024, 12, 15), odometer: 1_000, gallons: 10, price: 3.0),
        ]
        let statistics = FuelStatistics(entries: entries)
        #expect(statistics.monthlyTotals.count == 2)
        #expect(statistics.monthlyTotals[0].month < statistics.monthlyTotals[1].month)
    }

    @Test func enormousValuesStayFinite() {
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 999_999_000, gallons: 10, price: 9.999),
            makeEntry(on: day(2025, 1, 10), odometer: 999_999_300, gallons: 10, price: 9.999),
        ]
        let statistics = FuelStatistics(entries: entries)
        let average = statistics.averageMPG
        #expect(average != nil && average!.isFinite)
        #expect(statistics.milesTracked == 300)
        #expect(statistics.costPerMile!.isFinite)
    }

    @Test func thousandsOfEntriesComputeWithoutIncident() {
        var entries: [FuelEntry] = []
        var odometer = 10_000.0
        for index in 0..<2_000 {
            let date = Calendar.current.date(byAdding: .day, value: index, to: day(2020, 1, 1))!
            odometer += 300
            entries.append(makeEntry(on: date, odometer: odometer, gallons: 10, price: 3.5))
        }
        let statistics = FuelStatistics(entries: entries)
        #expect(statistics.mpgPoints.count == 1_999)
        #expect(statistics.fillUpCount == 2_000)
        #expect(statistics.monthlyTotals.count > 60)
    }
}

// MARK: - Form model under hostile use

@MainActor
struct FormModelHostileInputTests {
    // The container must be returned and held for the test's lifetime:
    // a deallocated ModelContainer resets its context and destroys every
    // model instance it owned, crashing the next property access.
    private func makeVehicleContext() -> (ModelContainer, Vehicle) {
        let container = ModelContainerFactory.makeInMemory()
        let vehicle = Vehicle(name: "Test")
        container.mainContext.insert(vehicle)
        return (container, vehicle)
    }

    @Test func negativeAndZeroInputsBlockSaving() {
        let form = FillUpFormModel()
        form.odometer = -1
        form.gallons = 10
        form.pricePerGallon = 3.5
        #expect(!form.canSave)

        form.odometer = 12_000
        form.gallons = 0
        #expect(!form.canSave)

        form.gallons = 10
        form.pricePerGallon = -3.5
        #expect(!form.canSave)
    }

    @Test func doubleTappedSaveInsertsExactlyOneEntry() {
        // Regression guard: save() used to insert a duplicate on the
        // second call; it now adopts the inserted entry and updates it.
        let (container, vehicle) = makeVehicleContext()
        let form = FillUpFormModel()
        form.odometer = 12_000
        form.gallons = 10
        form.pricePerGallon = 3.5

        form.save(to: vehicle, in: container.mainContext)
        form.save(to: vehicle, in: container.mainContext)

        #expect(vehicle.fillUps.count == 1)
    }

    @Test func saveResetSaveCreatesTwoDistinctEntries() {
        // The watch quick-entry loop: save, reset, save again must insert
        // a second entry and leave the first untouched.
        let (container, vehicle) = makeVehicleContext()
        let form = FillUpFormModel()
        form.odometer = 12_000
        form.gallons = 10
        form.pricePerGallon = 3.5
        form.save(to: vehicle, in: container.mainContext)

        form.resetForNextEntry()
        form.odometer = 12_300
        form.gallons = 9
        form.pricePerGallon = 3.6
        form.save(to: vehicle, in: container.mainContext)

        #expect(vehicle.fillUps.count == 2)
        let odometers = Set(vehicle.fillUps.map(\.odometer))
        #expect(odometers == [12_000, 12_300])
    }

    @Test func invalidSaveDoesNotAdoptAnEntry() {
        // A failed save must not flip the form into editing mode.
        let (container, vehicle) = makeVehicleContext()
        let form = FillUpFormModel()
        form.gallons = 10
        form.save(to: vehicle, in: container.mainContext)
        #expect(!form.isEditing)
        #expect(vehicle.fillUps.isEmpty)
    }
}

// MARK: - Pump scan parser under hostile OCR

struct ParserHostileInputTests {
    @Test func integersWithoutDecimalPointsAreInvisible() {
        // Pump numbers always carry decimals; bare integers (octane "87",
        // pump "#4", "TOTAL 35") must never be mistaken for readings.
        let reading = PumpScanParser.parse(["TOTAL 35", "GALLONS 10", "OCTANE 87"])
        #expect(reading == PumpReading())
    }

    @Test func conflictingLabeledValuesKeepTheFirst() {
        // OCR sometimes re-reads a line differently; first stable read wins.
        let reading = PumpScanParser.parse(["TOTAL 30.48", "TOTAL 99.99"])
        #expect(reading.totalCost == 30.48)
    }

    @Test func derivesPriceFromTotalAndGallons() {
        let reading = PumpScanParser.parse(["GALLONS 10.000", "TOTAL $35.00"])
        #expect(reading.pricePerGallon == 3.5)
    }

    @Test func extraDecimalDigitsTruncateToThree() {
        let reading = PumpScanParser.parse(["PRICE/GAL 3.4999"])
        #expect(reading.pricePerGallon == 3.499)
    }

    @Test func outOfRangeNumbersAreNeverAssigned() {
        // 555.123 exceeds the gallons cap, 0.001 sits below every range,
        // and 999.99 exceeds the $500 total plausibility cap.
        let reading = PumpScanParser.parse(["#7 STATION 555.1234", "0.001", "999.99"])
        #expect(reading == PumpReading())
    }

    @Test func loneThreeDecimalNumberInGallonsRangeIsPickedUpButIncomplete() {
        // Documented tradeoff: a 12.345-style stray can be read as gallons,
        // but without a price the reading stays incomplete and unusable.
        let reading = PumpScanParser.parse(["PUMP ID 12.345"])
        #expect(reading.gallons == 12.345)
        #expect(!reading.isComplete)
    }

    @Test func hundredsOfNoiseLinesDoNotConfuseOrHang() {
        var lines: [String] = []
        for index in 0..<300 {
            lines.append("WELCOME MEMBER \(index)")
            lines.append("LOYALTY PTS 0.\(index % 10)")
        }
        lines.append(contentsOf: ["GALLONS 8.712", "PRICE/GAL 3.499"])
        let reading = PumpScanParser.parse(lines)
        #expect(reading.gallons == 8.712)
        #expect(reading.pricePerGallon == 3.499)
    }

    @Test func mergeWithEmptyNewReadingKeepsEverything() {
        let current = PumpReading(gallons: 8.712, pricePerGallon: 3.499, totalCost: 30.48)
        #expect(PumpScanParser.merge(current: current, new: PumpReading()) == current)
    }
}

// MARK: - Formatters under hostile values

struct FormatterHostileInputTests {
    private func digits(_ string: String) -> String {
        string.filter(\.isNumber)
    }

    @Test func negativeAmountsFormatWithoutCrashing() {
        #expect(digits(Format.currency(-12.34)) == "1234")
        #expect(digits(Format.mpg(-5.05)) == "50" || digits(Format.mpg(-5.05)) == "51")
        #expect(!Format.odometer(-100).isEmpty)
    }

    @Test func zeroFormatsCleanly() {
        #expect(digits(Format.currency(0)) == "000")
        #expect(digits(Format.gallons(0)) == "0")
        #expect(digits(Format.compactMiles(0)) == "0")
    }

    @Test func hugeValuesFormatCompletely() {
        #expect(digits(Format.odometer(999_999_999)) == "999999999")
        #expect(digits(Format.compactMiles(1_500_000)) == "15")
    }
}

// MARK: - KPIs with sparse data

struct KPISparseDataTests {
    @Test func singleEntryProducesFullKPIListWithHonestPlaceholders() {
        let statistics = FuelStatistics(entries: [
            makeEntry(odometer: 1_000, gallons: 10, price: 3.0),
        ])
        let kpis = statistics.dashboardKPIs
        #expect(kpis.count == 8)
        #expect(kpis.first { $0.title == "Avg MPG" }!.value == nil)
        #expect(kpis.first { $0.title == "Cost per Mile" }!.value == nil)
        #expect(kpis.first { $0.title == "Total Spent" }!.value != nil)
        #expect(kpis.first { $0.title == "Fill-Ups" }!.value == "1")
    }
}

// MARK: - Container factory fallback

@MainActor
struct ContainerFallbackTests {
    @Test func sharedContainerIsUsableWithoutICloudEntitlement() throws {
        // With entitlements shipped empty, makeShared() must fall back to
        // (or succeed with) a local store and return a working container.
        let container = ModelContainerFactory.makeShared()
        let count = try container.mainContext.fetchCount(FetchDescriptor<Vehicle>())
        #expect(count >= 0)
    }
}
