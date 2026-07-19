import Foundation
import SwiftData
import Testing
@testable import FuelTracker

private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
}

private func makeEntry(
    on date: Date,
    odometer: Double,
    gallons: Double,
    price: Double = 3.50,
    fullTank: Bool = true,
    missedPrevious: Bool = false
) -> FuelEntry {
    FuelEntry(
        date: date,
        odometer: odometer,
        gallons: gallons,
        pricePerGallon: price,
        isFullTank: fullTank,
        missedPreviousFillUp: missedPrevious
    )
}

@MainActor
struct MissedFillUpDetectionTests {
    /// Segments of 30, 31, 32 MPG — then one impossible 66 MPG segment
    /// (the signature of a fill that never got logged).
    private func historyWithOneImpossibleSegment() -> [FuelEntry] {
        [
            makeEntry(on: day(2025, 1, 1), odometer: 10_000, gallons: 10),
            makeEntry(on: day(2025, 1, 10), odometer: 10_300, gallons: 10),   // 30
            makeEntry(on: day(2025, 1, 20), odometer: 10_610, gallons: 10),   // 31
            makeEntry(on: day(2025, 1, 30), odometer: 10_930, gallons: 10),   // 32
            makeEntry(on: day(2025, 2, 10), odometer: 11_590, gallons: 10),   // 66 — suspect
        ]
    }

    // MARK: - Detection

    @Test func impossiblyHighSegmentIsFlaggedAsSuspect() {
        let entries = historyWithOneImpossibleSegment()
        let statistics = FuelStatistics(entries: entries)

        #expect(statistics.suspectEntries.count == 1)
        #expect(statistics.isSuspectSegment(for: entries[4]))
        #expect(!statistics.isSuspectSegment(for: entries[3]))
        #expect(!statistics.isSuspectSegment(for: entries[0]))
    }

    @Test func normalVariationIsNeverFlagged() {
        // 30 / 31 / 32 MPG is ordinary noise, not a missed fill.
        let entries = Array(historyWithOneImpossibleSegment().prefix(4))
        let statistics = FuelStatistics(entries: entries)
        #expect(statistics.suspectEntries.isEmpty)
    }

    @Test func relativeDetectionNeedsEnoughHistory() {
        // Two segments (30, then 66): with so little history, 66 MPG could
        // be a hybrid on a highway trip — no flag.
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 10_000, gallons: 10),
            makeEntry(on: day(2025, 1, 10), odometer: 10_300, gallons: 10),
            makeEntry(on: day(2025, 1, 20), odometer: 10_960, gallons: 10),
        ]
        #expect(FuelStatistics(entries: entries).suspectEntries.isEmpty)
    }

    @Test func physicallyAbsurdMPGIsFlaggedEvenWithoutHistory() {
        // 150 MPG needs no context to be wrong for a gas car.
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 10_000, gallons: 10),
            makeEntry(on: day(2025, 1, 10), odometer: 11_500, gallons: 10),
        ]
        let statistics = FuelStatistics(entries: entries)
        #expect(statistics.suspectEntries.count == 1)
        #expect(statistics.isSuspectSegment(for: entries[1]))
    }

    // MARK: - The marker breaks the chain

    @Test func markedEntryProducesNoSegmentAndBecomesTheNewBaseline() {
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 10_000, gallons: 10),
            makeEntry(on: day(2025, 1, 10), odometer: 10_600, gallons: 12, missedPrevious: true),
            makeEntry(on: day(2025, 1, 20), odometer: 10_900, gallons: 10),
        ]
        let statistics = FuelStatistics(entries: entries)

        // No 600/12 segment; the marked entry re-anchors the chain, so the
        // only segment is 300 miles / 10 gallons from it to the next fill.
        #expect(statistics.mpgPoints.count == 1)
        #expect(statistics.mpg(for: entries[1]) == nil)
        #expect(abs(statistics.mpg(for: entries[2])! - 30.0) < 0.0001)
    }

    @Test func markedPartialFillClearsTheBaselineUntilTheNextFullTank() {
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 1_000, gallons: 10),
            makeEntry(on: day(2025, 1, 8), odometer: 1_400, gallons: 5, fullTank: false, missedPrevious: true),
            makeEntry(on: day(2025, 1, 15), odometer: 1_600, gallons: 8),
            makeEntry(on: day(2025, 1, 22), odometer: 1_900, gallons: 10),
        ]
        let statistics = FuelStatistics(entries: entries)

        // The marked partial can't anchor anything; the next full tank
        // re-anchors silently, and only the final segment computes.
        #expect(statistics.mpgPoints.count == 1)
        #expect(statistics.mpg(for: entries[2]) == nil)
        #expect(abs(statistics.mpg(for: entries[3])! - 30.0) < 0.0001)
    }

    @Test func markingTheSuspectClearsTheFlagAndRepairsTheAverage() {
        let entries = historyWithOneImpossibleSegment()
        let before = FuelStatistics(entries: entries)
        #expect(abs(before.averageMPG! - 1_590.0 / 40.0) < 0.0001)   // polluted: 39.75

        entries[4].missedPreviousFillUp = true
        let after = FuelStatistics(entries: entries)

        #expect(after.suspectEntries.isEmpty)
        #expect(abs(after.averageMPG! - 930.0 / 30.0) < 0.0001)      // honest: 31.0
    }

    @Test func spendingAndGallonTotalsIgnoreTheFlag() {
        let entries = historyWithOneImpossibleSegment()
        let before = FuelStatistics(entries: entries)
        entries[4].missedPreviousFillUp = true
        let after = FuelStatistics(entries: entries)

        #expect(before.totalSpent == after.totalSpent)
        #expect(before.totalGallons == after.totalGallons)
        #expect(before.fillUpCount == after.fillUpCount)
    }

    // MARK: - Hostile usage

    @Test func flagOnTheVeryFirstEntryIsJustABaseline() {
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 10_000, gallons: 10, missedPrevious: true),
            makeEntry(on: day(2025, 1, 10), odometer: 10_300, gallons: 10),
        ]
        let statistics = FuelStatistics(entries: entries)
        #expect(statistics.mpgPoints.count == 1)
        #expect(abs(statistics.mpgPoints[0].mpg - 30.0) < 0.0001)
    }

    @Test func everyEntryFlaggedProducesNoSegmentsAndNoCrash() {
        let entries = (0..<5).map { index in
            makeEntry(
                on: day(2025, 1, 1 + index * 7),
                odometer: 10_000 + Double(index) * 300,
                gallons: 10,
                missedPrevious: true
            )
        }
        let statistics = FuelStatistics(entries: entries)
        #expect(statistics.mpgPoints.isEmpty)
        #expect(statistics.averageMPG == nil)
        #expect(statistics.totalSpent > 0)
    }

    @Test func medianMPGIsSteadyAndNilWhenEmpty() {
        #expect(FuelStatistics(entries: []).medianMPG == nil)

        let statistics = FuelStatistics(entries: historyWithOneImpossibleSegment())
        // Median of [30, 31, 32, 66] (upper median) is 32 — the outlier
        // barely moves it, which is exactly why detection uses it.
        #expect(abs(statistics.medianMPG! - 32.0) < 0.0001)
    }

    // MARK: - Form model round trip

    @Test func formModelRoundTripsTheMissedFlag() {
        let container = ModelContainerFactory.makeInMemory()
        let vehicle = Vehicle(name: "Test")
        container.mainContext.insert(vehicle)

        let form = FillUpFormModel()
        form.odometer = 12_000
        form.gallons = 10
        form.pricePerGallon = 3.5
        form.missedPreviousFillUp = true
        form.save(to: vehicle, in: container.mainContext)

        let saved = vehicle.fillUps.first!
        #expect(saved.missedPreviousFillUp)

        let editForm = FillUpFormModel(entry: saved)
        #expect(editForm.missedPreviousFillUp)

        editForm.missedPreviousFillUp = false
        editForm.save(to: vehicle, in: container.mainContext)
        #expect(!saved.missedPreviousFillUp)

        let fresh = FillUpFormModel()
        fresh.missedPreviousFillUp = true
        fresh.resetForNextEntry()
        #expect(!fresh.missedPreviousFillUp)
    }
}
