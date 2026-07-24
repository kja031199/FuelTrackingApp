import Foundation

/// A cheap fingerprint of the entries that feed `FuelStatistics`. Two entry
/// arrays with the same key produce identical statistics, so the key decides
/// when the memo must recompute.
///
/// Only the fields the statistics actually depend on are hashed — editing a
/// station name or notes (which don't affect any stat) intentionally does *not*
/// invalidate the cache.
struct FuelStatisticsKey: Equatable {
    let count: Int
    let digest: Int

    init(_ entries: [FuelEntry]) {
        count = entries.count
        var hasher = Hasher()
        for entry in entries {
            hasher.combine(entry.id)
            hasher.combine(entry.date)
            hasher.combine(entry.odometer)
            hasher.combine(entry.gallons)
            hasher.combine(entry.pricePerGallon)
            hasher.combine(entry.isFullTank)
            hasher.combine(entry.missedPreviousFillUp)
            hasher.combine(entry.fuelGradeRaw)
        }
        digest = hasher.finalize()
    }
}

/// Memoizes `FuelStatistics` so it's rebuilt only when the underlying entries
/// change, not on every SwiftUI render.
///
/// Held in a view's `@State` as a plain (non-observable) reference: reading
/// `statistics(for:)` in `body` mutates only its private cache, never any state
/// SwiftUI observes, so it doesn't trigger re-renders or "modifying state during
/// update" warnings. Computing the key is a single cheap pass; the win is
/// skipping the multi-pass statistics build when nothing changed.
final class FuelStatisticsMemo {
    private let compute: ([FuelEntry]) -> FuelStatistics
    private var key: FuelStatisticsKey?
    private var value: FuelStatistics?

    /// How many times the statistics were actually (re)built — for tests.
    private(set) var recomputeCount = 0

    init(compute: @escaping ([FuelEntry]) -> FuelStatistics = { FuelStatistics(entries: $0) }) {
        self.compute = compute
    }

    func statistics(for entries: [FuelEntry]) -> FuelStatistics {
        let newKey = FuelStatisticsKey(entries)
        if newKey == key, let value {
            return value
        }
        let statistics = compute(entries)
        key = newKey
        value = statistics
        recomputeCount += 1
        return statistics
    }
}
