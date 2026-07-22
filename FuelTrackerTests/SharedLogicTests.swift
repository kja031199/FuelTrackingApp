import Foundation
import SwiftData
import Testing
@testable import FuelTracker

// MARK: - Helpers

@MainActor
private func makeContainer() -> ModelContainer {
    ModelContainerFactory.makeInMemory()
}

private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
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

/// Extracts just the digits so assertions hold in any locale
/// (separators and currency symbols vary; the digits don't).
private func digits(_ string: String) -> String {
    string.filter(\.isNumber)
}

// MARK: - Models

@MainActor
struct VehicleTests {
    @Test func displaySubtitleCombinesYearMakeModel() {
        let vehicle = Vehicle(name: "Daily", make: "Honda", model: "Civic", year: 2021)
        #expect(vehicle.displaySubtitle == "2021 Honda Civic")
    }

    @Test func displaySubtitleIsEmptyWithoutMakeAndModel() {
        let vehicle = Vehicle(name: "Daily", year: 2021)
        #expect(vehicle.displaySubtitle.isEmpty)
    }

    @Test func displaySubtitleWithOnlyMakeOmitsTheModel() {
        let vehicle = Vehicle(name: "Daily", make: "Honda", year: 2021)
        #expect(vehicle.displaySubtitle == "2021 Honda")
    }

    @Test func displaySubtitleWithOnlyModelOmitsTheMake() {
        let vehicle = Vehicle(name: "Daily", model: "Civic", year: 2021)
        #expect(vehicle.displaySubtitle == "2021 Civic")
    }

    @Test func fillUpsFallsBackToEmptyWhenRelationshipIsNil() {
        let container = makeContainer()
        let vehicle = Vehicle(name: "Daily")
        container.mainContext.insert(vehicle)
        vehicle.entries = nil
        #expect(vehicle.fillUps.isEmpty)
    }

    @Test func cascadeDeleteRemovesEntries() throws {
        let container = makeContainer()
        let context = container.mainContext
        let vehicle = Vehicle(name: "Daily")
        context.insert(vehicle)
        let entry = FuelEntry(odometer: 2_000, gallons: 10, pricePerGallon: 3.0, vehicle: vehicle)
        context.insert(entry)
        try context.save()

        context.delete(vehicle)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<FuelEntry>())
        #expect(remaining.isEmpty)
    }
}

@MainActor
struct FuelEntryTests {
    @Test func totalCostIsGallonsTimesPrice() {
        let entry = makeEntry(odometer: 1_000, gallons: 12.5, price: 4.00)
        #expect(abs(entry.totalCost - 50.0) < 0.0001)
    }

    @Test func fuelGradeRoundTripsThroughRawStorage() {
        let entry = makeEntry(odometer: 1_000, gallons: 10, price: 3.0)
        entry.fuelGrade = .premium
        #expect(entry.fuelGradeRaw == "Premium")
        #expect(entry.fuelGrade == .premium)
    }

    @Test func unknownStoredGradeFallsBackToOther() {
        let entry = makeEntry(odometer: 1_000, gallons: 10, price: 3.0)
        entry.fuelGradeRaw = "Jet Fuel"
        #expect(entry.fuelGrade == .other)
    }
}

struct FuelGradeTests {
    @Test func hasAllExpectedCases() {
        #expect(FuelGrade.allCases.count == 6)
        #expect(FuelGrade.allCases.first == .regular)
    }

    @Test func idMatchesRawValue() {
        for grade in FuelGrade.allCases {
            #expect(grade.id == grade.rawValue)
        }
    }
}

// MARK: - Statistics edge cases

@MainActor
struct FuelStatisticsEdgeCaseTests {
    @Test func allPartialFillsProduceNoMPG() {
        let entries = [
            makeEntry(odometer: 1_000, gallons: 5, price: 3.0, fullTank: false),
            makeEntry(odometer: 1_200, gallons: 5, price: 3.0, fullTank: false),
        ]
        let statistics = FuelStatistics(entries: entries)
        #expect(statistics.mpgPoints.isEmpty)
        #expect(statistics.averageMPG == nil)
    }

    @Test func zeroDistanceSegmentIsSkippedButAdvancesBaseline() {
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 1_000, gallons: 10, price: 3.0),
            makeEntry(on: day(2025, 1, 2), odometer: 1_000, gallons: 5, price: 3.0),
            makeEntry(on: day(2025, 1, 10), odometer: 1_300, gallons: 10, price: 3.0),
        ]
        let statistics = FuelStatistics(entries: entries)
        // The equal-odometer fill yields no MPG but becomes the new baseline,
        // so the last segment is 300 miles / 10 gallons.
        #expect(statistics.mpgPoints.count == 1)
        #expect(abs(statistics.mpgPoints[0].mpg - 30.0) < 0.0001)
    }

    @Test func bestWorstAndLastMPG() {
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 1_000, gallons: 10, price: 3.0),
            makeEntry(on: day(2025, 1, 10), odometer: 1_300, gallons: 10, price: 3.0),  // 30
            makeEntry(on: day(2025, 1, 20), odometer: 1_650, gallons: 10, price: 3.0),  // 35
            makeEntry(on: day(2025, 1, 30), odometer: 1_970, gallons: 10, price: 3.0),  // 32
        ]
        let statistics = FuelStatistics(entries: entries)
        #expect(statistics.bestMPG == 35)
        #expect(statistics.worstMPG == 30)
        #expect(statistics.lastMPG == 32)
    }

    @Test func perFillAveragesAndMilesBetweenFillUps() {
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 1_000, gallons: 10, price: 3.0),
            makeEntry(on: day(2025, 1, 10), odometer: 1_300, gallons: 12, price: 3.5),
            makeEntry(on: day(2025, 1, 20), odometer: 1_700, gallons: 14, price: 4.0),
        ]
        let statistics = FuelStatistics(entries: entries)
        #expect(abs(statistics.averageGallonsPerFillUp! - 12.0) < 0.0001)
        #expect(abs(statistics.averageFillUpCost! - (30 + 42 + 56) / 3.0) < 0.0001)
        #expect(abs(statistics.averageMilesBetweenFillUps! - 350.0) < 0.0001)
    }

    @Test func singleEntryHasNoBetweenFillMetrics() {
        let statistics = FuelStatistics(entries: [makeEntry(odometer: 1_000, gallons: 10, price: 3.0)])
        #expect(statistics.averageMilesBetweenFillUps == nil)
        #expect(statistics.costPerMile == nil)
        #expect(statistics.milesTracked == 0)
        #expect(statistics.averageMonthlySpend == nil)
    }

    @Test func emptyEntriesHaveNoAverages() {
        let statistics = FuelStatistics(entries: [])
        #expect(statistics.averageFillUpCost == nil)
        #expect(statistics.averageGallonsPerFillUp == nil)
        #expect(statistics.averagePricePerGallon == nil)
        #expect(statistics.lastPricePerGallon == nil)
        #expect(statistics.bestMPG == nil)
        #expect(statistics.worstMPG == nil)
        #expect(statistics.lastMPG == nil)
    }

    @Test func averageMonthlySpendNormalizesTo30Days() {
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 1_000, gallons: 10, price: 3.0),  // $30
            makeEntry(on: day(2025, 1, 31), odometer: 1_300, gallons: 10, price: 4.0), // $40
        ]
        let statistics = FuelStatistics(entries: entries)
        // 30-day span, so the monthly average equals the total spent.
        #expect(abs(statistics.averageMonthlySpend! - 70.0) < 0.0001)
    }

    @Test func sameDayEntriesHaveNoMonthlySpendAverage() {
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 1_000, gallons: 10, price: 3.0),
            makeEntry(on: day(2025, 1, 1), odometer: 1_300, gallons: 10, price: 3.0),
        ]
        #expect(FuelStatistics(entries: entries).averageMonthlySpend == nil)
    }

    @Test func freeFuelAfterBaselineMeansNoCostPerMile() {
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 1_000, gallons: 10, price: 3.0),
            makeEntry(on: day(2025, 1, 10), odometer: 1_300, gallons: 10, price: 0),
        ]
        #expect(FuelStatistics(entries: entries).costPerMile == nil)
    }

    @Test func mpgLookupForUnknownEntryIsNil() {
        let known = makeEntry(odometer: 1_000, gallons: 10, price: 3.0)
        let statistics = FuelStatistics(entries: [known])
        let stranger = makeEntry(odometer: 9_999, gallons: 9, price: 3.0)
        #expect(statistics.mpg(for: stranger) == nil)
    }

    @Test func entriesAreSortedByOdometerRegardlessOfInputOrder() {
        let entries = [
            makeEntry(on: day(2025, 1, 10), odometer: 1_300, gallons: 10, price: 3.0),
            makeEntry(on: day(2025, 1, 1), odometer: 1_000, gallons: 10, price: 3.0),
        ]
        let statistics = FuelStatistics(entries: entries)
        #expect(statistics.entries.map(\.odometer) == [1_000, 1_300])
        #expect(statistics.mpgPoints.count == 1)
    }
}

// MARK: - KPIs

struct KPITests {
    private var populated: FuelStatistics {
        FuelStatistics(entries: [
            makeEntry(on: day(2025, 1, 1), odometer: 1_000, gallons: 10, price: 3.0),
            makeEntry(on: day(2025, 1, 31), odometer: 1_300, gallons: 10, price: 3.5),
        ])
    }

    @Test func dashboardKPIsAreCompleteAndUnique() {
        let kpis = populated.dashboardKPIs
        #expect(kpis.count == 8)
        #expect(Set(kpis.map(\.id)).count == kpis.count)
        #expect(kpis.allSatisfy { $0.value != nil })
    }

    @Test func compactKPIsAreTheWatchSubset() {
        let kpis = populated.compactKPIs
        #expect(kpis.count == 6)
        #expect(Set(kpis.map(\.id)).count == kpis.count)
    }

    @Test func emptyStatisticsShowPlaceholders() {
        let kpis = FuelStatistics(entries: []).dashboardKPIs
        let averageMPG = kpis.first { $0.title == "Avg MPG" }!
        #expect(averageMPG.value == nil)
        let totalSpent = kpis.first { $0.title == "Total Spent" }!
        #expect(totalSpent.value != nil)
        #expect(totalSpent.detail == nil)
    }

    @Test func kpiIdDefaultsToTitleButCanBeOverridden() {
        let defaulted = KPI(title: "T", value: "V", icon: "i", metric: .economy)
        #expect(defaulted.id == "T")
        let custom = KPI(id: "custom", title: "T", value: "V", icon: "i", metric: .economy)
        #expect(custom.id == "custom")
    }
}

// MARK: - Metric colors

struct MetricTests {
    @Test func everyMetricHasADistinctColor() {
        let colors = [Metric.economy, .price, .spending, .distance].map(\.color)
        #expect(Set(colors.map(String.init(describing:))).count == colors.count)
    }
}

// MARK: - Formatters

struct FormatTests {
    @Test func currencyCodeIsNonEmpty() {
        #expect(!Format.currencyCode.isEmpty)
    }

    @Test func mpgUsesOneDecimal() {
        #expect(digits(Format.mpg(32.06)) == "321")
    }

    @Test func fuelPriceKeepsTenthsOfACent() {
        #expect(digits(Format.fuelPrice(3.499)) == "3499")
    }

    @Test func currencyUsesTwoDecimals() {
        #expect(digits(Format.currency(34.99)) == "3499")
    }

    @Test func gallonsAllowUpToThreeDecimals() {
        #expect(digits(Format.gallons(10.1234)) == "10123")
        #expect(digits(Format.gallons(10.0)) == "10")
    }

    @Test func odometerAllowsUpToOneDecimal() {
        // Rounds to one decimal (not truncated to whole, not kept at two).
        #expect(digits(Format.odometer(42_150.26)) == "421503")  // rounds up
        #expect(digits(Format.odometer(42_150.24)) == "421502")  // rounds down
        // An exact half is platform-dependent — half-to-even vs half-away
        // differ across OS versions — so accept either valid rounding rather
        // than pinning the test to one implementation's choice.
        #expect(["421502", "421503"].contains(digits(Format.odometer(42_150.25))))
        // A whole number keeps no fractional digit at all.
        #expect(digits(Format.odometer(42_150)) == "42150")
    }

    @Test func costPerMileAllowsThreeDecimals() {
        #expect(digits(Format.costPerMile(0.1234)) == "0123")
    }

    @Test func compactMilesAbbreviatesThousands() {
        #expect(digits(Format.compactMiles(42_500)) == "425")
    }

    @Test func wholeCurrencyRounds() {
        #expect(digits(Format.wholeCurrency(1_234.56)) == "1235")
    }

    @Test func plainCurrencyUsesTwoDecimals() {
        #expect(digits(Format.plainCurrency(3.5)) == "350")
    }
}

// MARK: - Dashboard time range

struct DashboardTimeRangeTests {
    @Test func allRangeHasNoCutoff() {
        #expect(DashboardTimeRange.all.cutoff == nil)
    }

    @Test func shorterRangesHaveMoreRecentCutoffs() throws {
        let threeMonths = try #require(DashboardTimeRange.threeMonths.cutoff)
        let sixMonths = try #require(DashboardTimeRange.sixMonths.cutoff)
        let year = try #require(DashboardTimeRange.year.cutoff)
        #expect(threeMonths > sixMonths)
        #expect(sixMonths > year)
        #expect(threeMonths < .now)
    }

    @Test func casesAndIdsAreStable() {
        #expect(DashboardTimeRange.allCases.count == 4)
        for range in DashboardTimeRange.allCases {
            #expect(range.id == range.rawValue)
        }
    }
}

// MARK: - Container factory & preview data

@MainActor
struct ModelContainerFactoryTests {
    @Test func schemaContainsBothModels() {
        #expect(ModelContainerFactory.schema.entities.count == 2)
    }

    @Test func inMemoryContainerStoresAndFetches() throws {
        let container = ModelContainerFactory.makeInMemory()
        container.mainContext.insert(Vehicle(name: "Test"))
        let vehicles = try container.mainContext.fetch(FetchDescriptor<Vehicle>())
        #expect(vehicles.count == 1)
    }
}

@MainActor
struct PreviewDataTests {
    @Test func seedsOneVehicleWithTwelveFillUps() throws {
        let context = PreviewData.container.mainContext
        let vehicles = try context.fetch(FetchDescriptor<Vehicle>())
        #expect(vehicles.count == 1)
        let entries = try context.fetch(FetchDescriptor<FuelEntry>())
        #expect(entries.count == 12)

        // Twelve sequential full tanks produce eleven MPG segments.
        let statistics = FuelStatistics(entries: vehicles[0].fillUps)
        #expect(statistics.mpgPoints.count == 11)
    }
}

// MARK: - Form model edge cases

@MainActor
struct FillUpFormModelEdgeCaseTests {
    @Test func saveDoesNothingWhenInvalid() throws {
        let container = makeContainer()
        let vehicle = Vehicle(name: "Test")
        container.mainContext.insert(vehicle)

        let form = FillUpFormModel()
        form.gallons = 10   // odometer and price still missing
        form.save(to: vehicle, in: container.mainContext)

        #expect(vehicle.fillUps.isEmpty)
    }

    @Test func previousOdometerIsNilWhileEditing() {
        let container = makeContainer()
        let vehicle = Vehicle(name: "Test")
        container.mainContext.insert(vehicle)
        let entry = FuelEntry(odometer: 5_000, gallons: 10, pricePerGallon: 3.0, vehicle: vehicle)
        container.mainContext.insert(entry)

        let form = FillUpFormModel(entry: entry)
        #expect(form.previousOdometer(for: vehicle) == nil)
        #expect(!form.odometerLooksWrong(for: vehicle))
    }

    @Test func odometerWarningNeedsAnOdometerAndAVehicleWithHistory() {
        let container = makeContainer()
        let vehicle = Vehicle(name: "Test")
        container.mainContext.insert(vehicle)

        let form = FillUpFormModel()
        #expect(!form.odometerLooksWrong(for: vehicle))   // no odometer typed
        form.odometer = 1_000
        #expect(!form.odometerLooksWrong(for: vehicle))   // vehicle has no history
        #expect(!form.odometerLooksWrong(for: nil))       // no vehicle at all
    }

    @Test func initFromEntryCopiesEveryField() {
        let entry = FuelEntry(
            date: day(2025, 2, 14),
            odometer: 5_000,
            gallons: 11.5,
            pricePerGallon: 3.75,
            isFullTank: false,
            fuelGrade: .diesel,
            station: "Shell",
            notes: "Road trip"
        )
        let form = FillUpFormModel(entry: entry)
        #expect(form.date == day(2025, 2, 14))
        #expect(form.odometer == 5_000)
        #expect(form.gallons == 11.5)
        #expect(form.pricePerGallon == 3.75)
        #expect(!form.isFullTank)
        #expect(form.fuelGrade == .diesel)
        #expect(form.station == "Shell")
        #expect(form.notes == "Road trip")
    }

    @Test func savingAnEditCanMoveTheEntryToAnotherVehicle() {
        let container = makeContainer()
        let context = container.mainContext
        let first = Vehicle(name: "First")
        let second = Vehicle(name: "Second")
        context.insert(first)
        context.insert(second)
        let entry = FuelEntry(odometer: 5_000, gallons: 10, pricePerGallon: 3.0, vehicle: first)
        context.insert(entry)

        let form = FillUpFormModel(entry: entry)
        form.save(to: second, in: context)

        #expect(entry.vehicle === second)
        #expect(first.fillUps.isEmpty)
        #expect(second.fillUps.count == 1)
    }

    @Test func resetAlsoClearsStationNotesAndDate() {
        let form = FillUpFormModel()
        form.station = "Shell"
        form.notes = "note"
        let oldDate = day(2020, 1, 1)
        form.date = oldDate
        form.resetForNextEntry()
        #expect(form.station.isEmpty)
        #expect(form.notes.isEmpty)
        #expect(form.date > oldDate)
    }
}
