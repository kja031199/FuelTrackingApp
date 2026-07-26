import SwiftUI
import Charts

/// A single (date, value) sample in a metric's time series.
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

/// Line chart for one metric over time, shared by both platforms.
///
/// Full mode (iPhone) shows point marks, axes, an optional dashed average
/// rule, and tap/drag-to-inspect selection. Compact mode (watch) draws just
/// the line with a y-axis, sized for a small screen.
struct MetricLineChart: View {
    let points: [DateValuePoint]
    let metric: Metric
    var average: Double? = nil
    var compact = false
    /// Formats a value for the selection callout and average label.
    let valueLabel: (Double) -> String
    /// Optional custom y-axis label formatting; default axis otherwise.
    var yAxisLabel: ((Double) -> String)? = nil
    /// Above this many points, the plotted series is downsampled for display.
    var downsampleThreshold = 500
    /// Title VoiceOver announces for the audio graph. Falls back to the
    /// metric's generic name, which is enough on the watch (no audio graphs
    /// there) but vague on a dashboard with two distance charts.
    var accessibilityTitle: String? = nil

    @State private var selectedDate: Date?
    @Environment(\.colorScheme) private var colorScheme

    /// The audio graph is built from the **displayed** points so the tones line
    /// up with the marks a sighted user sees. Statistics still come from the
    /// full history.
    private var audioGraph: ChartAudioGraphData? {
        ChartAudioGraphData.series(
            title: accessibilityTitle ?? metric.accessibilityName,
            yAxisLabel: accessibilityTitle ?? metric.accessibilityName,
            points: displayPoints,
            describeValue: valueLabel
        )
    }

    /// The points actually drawn — downsampled for very long histories. The
    /// average rule still comes from statistics over the full dataset.
    private var displayPoints: [DateValuePoint] {
        points.downsampled(max: downsampleThreshold)
    }

    private var selectedPoint: DateValuePoint? {
        guard !compact, let selectedDate else { return nil }
        return displayPoints.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        Chart {
            ForEach(displayPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(metric.color(in: colorScheme))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
                .accessibilityLabel(point.date.formatted(.dateTime.month(.abbreviated).day()))
                .accessibilityValue(valueLabel(point.value))

                if !compact {
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(metric.color(in: colorScheme))
                    .symbolSize(selectedPoint?.id == point.id ? 100 : 36)
                    .accessibilityHidden(true)
                }
            }

            if let average, !compact {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg \(valueLabel(average))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityHidden(true)
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.date))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        SelectionCallout(
                            title: selectedPoint.date.formatted(.dateTime.month(.abbreviated).day()),
                            value: valueLabel(selectedPoint.value)
                        )
                    }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .modifier(MetricYAxis(label: yAxisLabel))
        .modifier(ChartSelection(enabled: !compact, selectedDate: $selectedDate))
        .modifier(CompactXAxis(hidden: compact))
        .modifier(ChartAudioGraph(data: audioGraph, describeY: valueLabel))
    }
}

/// Bar chart of one monthly-aggregated value, shared by both platforms.
struct MonthlyBarChart: View {
    let totals: [MonthlyTotal]
    let value: KeyPath<MonthlyTotal, Double>
    let metric: Metric
    var compact = false
    var yAxisLabel: ((Double) -> String)? = nil
    /// Title VoiceOver announces for the audio graph.
    var accessibilityTitle: String? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var describeValue: (Double) -> String {
        yAxisLabel ?? { $0.formatted() }
    }

    private var audioGraph: ChartAudioGraphData? {
        ChartAudioGraphData.monthly(
            title: accessibilityTitle ?? metric.accessibilityName,
            yAxisLabel: accessibilityTitle ?? metric.accessibilityName,
            totals: totals,
            value: value,
            describeValue: describeValue
        )
    }

    var body: some View {
        Chart(totals) { total in
            BarMark(
                x: .value("Month", total.month, unit: .month),
                y: .value("Value", total[keyPath: value])
            )
            .foregroundStyle(metric.color(in: colorScheme))
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: compact ? 2 : 4,
                topTrailingRadius: compact ? 2 : 4,
                style: .continuous
            ))
            .accessibilityLabel(total.month.formatted(.dateTime.month(.wide).year()))
            .accessibilityValue(describeValue(total[keyPath: value]))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
            }
        }
        .modifier(MetricYAxis(label: yAxisLabel))
        .modifier(ChartAudioGraph(data: audioGraph, describeY: describeValue))
    }
}

/// Tooltip shown above the selection rule on line charts.
private struct SelectionCallout: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct MetricYAxis: ViewModifier {
    let label: ((Double) -> String)?

    func body(content: Content) -> some View {
        if let label {
            content.chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(label(number))
                        }
                    }
                }
            }
        } else {
            content
        }
    }
}

private struct ChartSelection: ViewModifier {
    let enabled: Bool
    @Binding var selectedDate: Date?

    func body(content: Content) -> some View {
        if enabled {
            content.chartXSelection(value: $selectedDate)
        } else {
            content
        }
    }
}

private struct CompactXAxis: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        if hidden {
            content.chartXAxis(.hidden)
        } else {
            content
        }
    }
}
