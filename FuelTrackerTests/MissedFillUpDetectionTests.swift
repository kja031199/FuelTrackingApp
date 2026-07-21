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

    @Test func medianMPGForASingleSegmentIsThatSegment() {
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 10_000, gallons: 10),
            makeEntry(on: day(2025, 1, 10), odometer: 10_300, gallons: 10),
        ]
        #expect(abs(FuelStatistics(entries: entries).medianMPG! - 30.0) < 0.0001)
    }

    // MARK: - Detection thresholds (exact boundaries)

    @Test func exactlyThreeSegmentsEnablesRelativeDetection() {
        // The relative rule needs `points.count >= 3`. Four full tanks make
        // exactly three segments — the inclusive boundary. Median of
        // [30, 31, 66] is 31; 31 × 1.75 = 54.25, so 66 is flagged.
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 10_000, gallons: 10),
            makeEntry(on: day(2025, 1, 10), odometer: 10_300, gallons: 10),   // 30
            makeEntry(on: day(2025, 1, 20), odometer: 10_610, gallons: 10),   // 31
            makeEntry(on: day(2025, 1, 30), odometer: 11_270, gallons: 10),   // 66
        ]
        let statistics = FuelStatistics(entries: entries)
        #expect(statistics.suspectEntries.count == 1)
        #expect(statistics.isSuspectSegment(for: entries[3]))
        #expect(!statistics.isSuspectSegment(for: entries[1]))
    }

    @Test func mpgExactlyAtRelativeThresholdIsNotFlagged() {
        // A segment exactly 1.75× the median must NOT trip the strict `>`.
        // Median of [40, 40, 70] is 40; 40 × 1.75 = 70, and 70 is not > 70.
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 10_000, gallons: 10),
            makeEntry(on: day(2025, 1, 10), odometer: 10_400, gallons: 10),   // 40
            makeEntry(on: day(2025, 1, 20), odometer: 10_800, gallons: 10),   // 40
            makeEntry(on: day(2025, 1, 30), odometer: 11_500, gallons: 10),   // 70 = 1.75 × 40
        ]
        #expect(FuelStatistics(entries: entries).suspectEntries.isEmpty)
    }

    @Test func mpgJustAboveRelativeThresholdIsFlagged() {
        // One mile more than the boundary (71 MPG) crosses it.
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 10_000, gallons: 10),
            makeEntry(on: day(2025, 1, 10), odometer: 10_400, gallons: 10),   // 40
            makeEntry(on: day(2025, 1, 20), odometer: 10_800, gallons: 10),   // 40
            makeEntry(on: day(2025, 1, 30), odometer: 11_510, gallons: 10),   // 71 > 70
        ]
        let statistics = FuelStatistics(entries: entries)
        #expect(statistics.suspectEntries.count == 1)
        #expect(statistics.isSuspectSegment(for: entries[3]))
    }

    @Test func mpgExactlyAtAbsoluteCapIsNotFlagged() {
        // With only two segments the relative rule is off, isolating the
        // absolute 120 MPG cap. Exactly 120 must not trip the strict `>`.
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 10_000, gallons: 10),
            makeEntry(on: day(2025, 1, 10), odometer: 10_300, gallons: 10),   // 30
            makeEntry(on: day(2025, 1, 20), odometer: 11_500, gallons: 10),   // 120
        ]
        #expect(FuelStatistics(entries: entries).suspectEntries.isEmpty)
    }

    @Test func mpgJustAboveAbsoluteCapIsFlaggedWithoutHistory() {
        // 120.1 MPG (one extra mile) crosses the physical cap even with too
        // little history for the relative rule.
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 10_000, gallons: 10),
            makeEntry(on: day(2025, 1, 10), odometer: 10_300, gallons: 10),   // 30
            makeEntry(on: day(2025, 1, 20), odometer: 11_501, gallons: 10),   // 120.1 > 120
        ]
        let statistics = FuelStatistics(entries: entries)
        #expect(statistics.suspectEntries.count == 1)
        #expect(statistics.isSuspectSegment(for: entries[2]))
    }

    // MARK: - Multiple suspects & degenerate detection

    @Test func multipleSuspectsAreAllFlaggedNewestFirst() {
        // Two forgotten fills. The dashboard banner shows suspectEntries.first,
        // so the ordering (newest first) is load-bearing — and the input is
        // deliberately shuffled to prove detection doesn't depend on it.
        let base = makeEntry(on: day(2025, 1, 1), odometer: 10_000, gallons: 10)
        let normalA = makeEntry(on: day(2025, 1, 10), odometer: 10_300, gallons: 10)   // 30
        let normalB = makeEntry(on: day(2025, 1, 20), odometer: 10_610, gallons: 10)   // 31
        let normalC = makeEntry(on: day(2025, 1, 30), odometer: 10_930, gallons: 10)   // 32
        let olderSuspect = makeEntry(on: day(2025, 2, 10), odometer: 11_590, gallons: 10)  // 66
        let newerSuspect = makeEntry(on: day(2025, 2, 20), odometer: 12_250, gallons: 10)  // 66

        let shuffled = [newerSuspect, base, normalC, olderSuspect, normalA, normalB]
        let statistics = FuelStatistics(entries: shuffled)

        #expect(statistics.suspectEntries.count == 2)
        #expect(statistics.suspectEntries.first?.id == newerSuspect.id)
        #expect(statistics.suspectEntries.last?.id == olderSuspect.id)
    }

    @Test func aSegmentTrippingBothRulesIsCountedOnce() {
        // A 200 MPG segment exceeds both median × 1.75 and the 120 cap.
        // The Set of suspect IDs must dedupe it to a single entry.
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 10_000, gallons: 10),
            makeEntry(on: day(2025, 1, 10), odometer: 10_300, gallons: 10),   // 30
            makeEntry(on: day(2025, 1, 20), odometer: 10_610, gallons: 10),   // 31
            makeEntry(on: day(2025, 1, 30), odometer: 12_610, gallons: 10),   // 200
        ]
        let statistics = FuelStatistics(entries: entries)
        #expect(statistics.suspectEntries.count == 1)
        #expect(statistics.isSuspectSegment(for: entries[3]))
    }

    @Test func moderateOutliersEscapeWhenTheyPolluteTheMedianButAbsurdOnesDont() {
        // When outliers dominate, they pull the median up and the relative
        // rule stops flagging the moderate ones — a documented limitation.
        // Median of [30, 30, 66, 130] is 66; 66 × 1.75 = 115.5, so the 66
        // segment slips through, but 130 is still caught (relative + cap).
        let entries = [
            makeEntry(on: day(2025, 1, 1), odometer: 10_000, gallons: 10),
            makeEntry(on: day(2025, 1, 10), odometer: 10_300, gallons: 10),   // 30
            makeEntry(on: day(2025, 1, 20), odometer: 10_600, gallons: 10),   // 30
            makeEntry(on: day(2025, 1, 30), odometer: 11_260, gallons: 10),   // 66 — escapes
            makeEntry(on: day(2025, 2, 10), odometer: 12_560, gallons: 10),   // 130 — caught
        ]
        let statistics = FuelStatistics(entries: entries)
        #expect(statistics.suspectEntries.count == 1)
        #expect(statistics.isSuspectSegment(for: entries[4]))
        #expect(!statistics.isSuspectSegment(for: entries[3]))
    }

    @Test func markingOneOfTwoSuspectsLeavesTheOtherFlagged() {
        // Repairing the newest forgotten fill must not silence the older one.
        let base = makeEntry(on: day(2025, 1, 1), odometer: 10_000, gallons: 10)
        let normalA = makeEntry(on: day(2025, 1, 10), odometer: 10_300, gallons: 10)   // 30
        let normalB = makeEntry(on: day(2025, 1, 20), odometer: 10_610, gallons: 10)   // 31
        let normalC = makeEntry(on: day(2025, 1, 30), odometer: 10_930, gallons: 10)   // 32
        let olderSuspect = makeEntry(on: day(2025, 2, 10), odometer: 11_590, gallons: 10)  // 66
        let newerSuspect = makeEntry(on: day(2025, 2, 20), odometer: 12_250, gallons: 10)  // 66
        let entries = [base, normalA, normalB, normalC, olderSuspect, newerSuspect]

        #expect(FuelStatistics(entries: entries).suspectEntries.count == 2)

        newerSuspect.missedPreviousFillUp = true
        let after = FuelStatistics(entries: entries)
        #expect(after.suspectEntries.count == 1)
        #expect(after.isSuspectSegment(for: olderSuspect))
        #expect(!after.isSuspectSegment(for: newerSuspect))
    }

    @Test func isSuspectSegmentIsFalseForStrangerAndBaselineEntries() {
        let entries = historyWithOneImpossibleSegment()
        let statistics = FuelStatistics(entries: entries)

        // An entry that isn't part of these statistics at all.
        let stranger = makeEntry(on: day(2025, 6, 1), odometer: 99_999, gallons: 10)
        #expect(!statistics.isSuspectSegment(for: stranger))

        // The baseline fill has no segment of its own, so it's never suspect.
        #expect(!statistics.isSuspectSegment(for: entries[0]))
    }

    @Test func detectionIsIndependentOfInputOrder() {
        // The same suspect (odometer 11,590) must be found whether entries
        // arrive sorted, reversed, or shuffled — statistics sorts internally.
        let ordered = historyWithOneImpossibleSegment()
        let arrangements: [[FuelEntry]] = [ordered, Array(ordered.reversed()), ordered.shuffled()]
        for arrangement in arrangements {
            let statistics = FuelStatistics(entries: arrangement)
            #expect(statistics.suspectEntries.count == 1)
            #expect(statistics.suspectEntries.first?.odometer == 11_590)
        }
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
