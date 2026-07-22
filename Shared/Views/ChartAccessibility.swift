import Foundation

/// Spoken overviews of chart data for VoiceOver. Per-mark labels let a user
/// navigate individual points; this gives them the gist of the whole series
/// first — its range, average, latest value, and overall direction.
enum ChartAccessibility {
    static func summary(
        _ points: [DateValuePoint],
        unit: String,
        format: (Double) -> String
    ) -> String? {
        guard let first = points.first, let last = points.last else { return nil }
        let values = points.map(\.value)
        guard let low = values.min(), let high = values.max() else { return nil }

        if points.count == 1 {
            return "One point, \(format(last.value)) \(unit)."
        }

        let average = values.reduce(0, +) / Double(values.count)
        let trend: String
        if last.value > first.value * 1.02 {
            trend = "trending up"
        } else if last.value < first.value * 0.98 {
            trend = "trending down"
        } else {
            trend = "roughly flat"
        }

        return "\(points.count) points, from \(format(low)) to \(format(high)) \(unit), "
            + "averaging \(format(average)), latest \(format(last.value)), \(trend)."
    }
}
