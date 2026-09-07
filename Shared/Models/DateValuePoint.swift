import Foundation

/// A single (date, value) sample in a metric's time series.
///
/// Lives in the model layer, not alongside the charts that draw it: the
/// statistics layer produces these (`FuelStatistics.mpgSeries`,
/// `VehicleShowdown.leftMPGSeries`), and a domain type that only compiles
/// because a SwiftUI file happens to declare it is a layering accident. Keeping
/// it here means `Statistics/` depends on nothing above `Models/`, which is the
/// rule `ARCHITECTURE.md` states and the reason the watch target builds.
struct DateValuePoint: Identifiable {
    let id: UUID
    let date: Date
    let value: Double
}

extension Array where Element == DateValuePoint {
    /// The series with each value passed through `transform`, preserving ids
    /// and dates. Used to convert a canonical series (e.g. MPG) into a
    /// non-linear display unit (e.g. L/100km), where relabeling the axis isn't
    /// enough because the curve's shape changes.
    func mapValues(_ transform: (Double) -> Double) -> [DateValuePoint] {
        map { DateValuePoint(id: $0.id, date: $0.date, value: transform($0.value)) }
    }

    /// Evenly reduces the series to at most `max` points for **display**,
    /// always keeping the first and last and picking real samples (no synthetic
    /// averaging), so a chart isn't handed thousands of marks. Returns the
    /// series unchanged when it's already at or under `max`. Statistics are
    /// computed from the full set elsewhere and are unaffected.
    func downsampled(max: Int) -> [DateValuePoint] {
        guard max >= 2, count > max else { return self }
        let step = Double(count - 1) / Double(max - 1)
        var result: [DateValuePoint] = []
        result.reserveCapacity(max)
        var lastIndex = -1
        for i in 0..<max {
            let index = Int((Double(i) * step).rounded())
            if index != lastIndex {
                result.append(self[index])
                lastIndex = index
            }
        }
        return result
    }
}
