import Foundation
import Testing
@testable import FuelTracker

// MARK: - Statistics memoization

@MainActor
struct FuelStatisticsMemoTests {
    private func entry(_ odometer: Double, date: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> FuelEntry {
        FuelEntry(date: date, odometer: odometer, gallons: 10, pricePerGallon: 3)
    }

    @Test func recomputesOnlyWhenEntriesChange() {
        let memo = FuelStatisticsMemo()
        let entries = [entry(100), entry(400)]

        _ = memo.statistics(for: entries)
        #expect(memo.recomputeCount == 1)

        _ = memo.statistics(for: entries) // identical input
        #expect(memo.recomputeCount == 1) // served from cache

        _ = memo.statistics(for: entries + [entry(700)]) // a new fill-up
        #expect(memo.recomputeCount == 2)
    }

    @Test func editingAStatAffectingFieldInvalidatesTheCache() {
        let memo = FuelStatisticsMemo()
        let edited = entry(100)
        let entries = [edited, entry(400)]
        _ = memo.statistics(for: entries)

        edited.odometer = 250 // changes MPG/miles
        _ = memo.statistics(for: entries)
        #expect(memo.recomputeCount == 2)
    }

    @Test func editingANonStatFieldDoesNotInvalidate() {
        let memo = FuelStatisticsMemo()
        let edited = entry(100)
        let entries = [edited, entry(400)]
        _ = memo.statistics(for: entries)

        edited.station = "Shell"   // no effect on any statistic
        edited.notes = "topped off"
        _ = memo.statistics(for: entries)
        #expect(memo.recomputeCount == 1)
    }

    @Test func theMemoizedResultMatchesADirectComputation() {
        let entries = [entry(100), entry(400), entry(700)]
        let cached = FuelStatisticsMemo().statistics(for: entries)
        let direct = FuelStatistics(entries: entries)
        #expect(cached.averageMPG == direct.averageMPG)
        #expect(cached.totalSpent == direct.totalSpent)
        #expect(cached.milesTracked == direct.milesTracked)
        #expect(cached.mpgPoints.count == direct.mpgPoints.count)
    }

    @Test func keyTracksStatAffectingFieldsOnly() {
        let edited = entry(100)
        let entries = [edited, entry(400)]
        let original = FuelStatisticsKey(entries)

        edited.station = "Shell"
        #expect(FuelStatisticsKey(entries) == original) // station is irrelevant

        edited.gallons = 12
        #expect(FuelStatisticsKey(entries) != original) // gallons matters
    }
}

// MARK: - Chart downsampling

struct DownsampleTests {
    private func series(_ count: Int) -> [DateValuePoint] {
        (0..<count).map {
            DateValuePoint(id: UUID(), date: Date(timeIntervalSince1970: Double($0) * 86_400), value: Double($0))
        }
    }

    @Test func atOrBelowThresholdTheSeriesIsUnchanged() {
        let points = series(100)
        let result = points.downsampled(max: 500)
        #expect(result.map(\.id) == points.map(\.id))
    }

    @Test func aboveThresholdItStaysBoundedAndKeepsTheEndpoints() {
        let points = series(5_000)
        let result = points.downsampled(max: 500)
        #expect(result.count <= 500)
        #expect(result.count > 1)
        #expect(result.first?.id == points.first?.id)
        #expect(result.last?.id == points.last?.id)
        // A real, strictly increasing subset — no synthetic or out-of-order points.
        #expect(zip(result, result.dropFirst()).allSatisfy { $0.date < $1.date })
    }

    @Test func degenerateBoundsAreSafe() {
        let points = series(10)
        #expect(points.downsampled(max: 1).count == 10)  // max < 2 → unchanged
        #expect(points.downsampled(max: 0).count == 10)
        #expect([DateValuePoint]().downsampled(max: 500).isEmpty)
    }
}
