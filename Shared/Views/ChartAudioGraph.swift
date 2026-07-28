import Foundation
import SwiftUI

#if os(iOS)
import Accessibility
#endif

/// One sonified sample: a position on each axis plus what VoiceOver reads out.
struct ChartAudioGraphPoint: Equatable, Sendable {
    /// X position. For a time series this is `timeIntervalSinceReferenceDate`.
    let x: Double
    let y: Double
    /// Spoken description when the user lands on this point.
    let label: String
}

/// Everything VoiceOver's **audio graph** needs to play a chart as sound.
///
/// Deliberately free of `AXChartDescriptor` and of SwiftUI: it's plain data, so
/// the interesting part — which points survive, what the axis bounds come out
/// as, whether a hostile series is rejected — is unit-testable without a
/// simulator or an accessibility session. The iOS-only bridge below turns it
/// into the real descriptor.
struct ChartAudioGraphData: Equatable, Sendable {
    let title: String
    let xAxisLabel: String
    let yAxisLabel: String
    let xRange: ClosedRange<Double>
    let yRange: ClosedRange<Double>
    let points: [ChartAudioGraphPoint]
}

extension ChartAudioGraphData {
    /// Builds the audio graph for a date/value series.
    ///
    /// Returns `nil` when there is nothing meaningful to play — an empty
    /// series, or one whose values are all non-finite. That matters: an audio
    /// graph built on `NaN` bounds is not a degraded experience, it's a chart
    /// VoiceOver can crash or go silent on, and silence is indistinguishable
    /// from a bug. Better to expose no audio graph and leave the per-mark
    /// labels and the spoken summary, which still work.
    static func series(
        title: String,
        xAxisLabel: String = "Date",
        yAxisLabel: String,
        points: [DateValuePoint],
        describeValue: (Double) -> String
    ) -> ChartAudioGraphData? {
        // Non-finite values are filtered rather than clamped: a NaN MPG is
        // missing data, and inventing a position for it would put a tone
        // somewhere the user's finger says there is no reading.
        let usable = points.filter { $0.value.isFinite }
        guard !usable.isEmpty else { return nil }

        let xs = usable.map(\.date.timeIntervalSinceReferenceDate)
        let ys = usable.map(\.value)
        guard let xSpan = Self.span(xs), let ySpan = Self.span(ys) else { return nil }

        return ChartAudioGraphData(
            title: title,
            xAxisLabel: xAxisLabel,
            yAxisLabel: yAxisLabel,
            xRange: xSpan,
            yRange: ySpan,
            points: usable.map { point in
                ChartAudioGraphPoint(
                    x: point.date.timeIntervalSinceReferenceDate,
                    y: point.value,
                    label: "\(Self.describe(point.date)), \(describeValue(point.value))"
                )
            }
        )
    }

    /// Builds the audio graph for a monthly bar chart.
    static func monthly(
        title: String,
        xAxisLabel: String = "Month",
        yAxisLabel: String,
        totals: [MonthlyTotal],
        value: KeyPath<MonthlyTotal, Double>,
        describeValue: (Double) -> String
    ) -> ChartAudioGraphData? {
        let points = totals.map { DateValuePoint(id: UUID(), date: $0.month, value: $0[keyPath: value]) }
        return series(
            title: title,
            xAxisLabel: xAxisLabel,
            yAxisLabel: yAxisLabel,
            points: points,
            describeValue: describeValue
        )
    }

    /// A non-degenerate range covering `values`.
    ///
    /// A flat series (every fill-up at the same price) would otherwise produce
    /// `x...x`, and an axis with no width gives the audio graph nowhere to put
    /// a tone. Padding keeps it playable — as a steady note, which is the
    /// honest rendering of flat data.
    private static func span(_ values: [Double]) -> ClosedRange<Double>? {
        guard let low = values.min(), let high = values.max(), low.isFinite, high.isFinite else {
            return nil
        }
        guard low == high else { return low...high }
        let padding = low == 0 ? 1 : abs(low) * 0.05
        return (low - padding)...(high + padding)
    }

    private static func describe(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

// MARK: - Bridge to VoiceOver

#if os(iOS)

/// Adapts ``ChartAudioGraphData`` to the `AXChartDescriptor` VoiceOver wants.
///
/// iOS-only by necessity, not by choice: `AXChartDescriptor` and the whole
/// audio-graph feature are unavailable on watchOS, so this whole section is
/// compiled out there. `Shared/` still holds it because the *data* half is
/// shared; only this bridge is platform-bound.
struct MetricChartDescriptor: AXChartDescriptorRepresentable {
    let data: ChartAudioGraphData
    let describeX: (Double) -> String
    let describeY: (Double) -> String

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXNumericDataAxisDescriptor(
            title: data.xAxisLabel,
            range: data.xRange,
            gridlinePositions: [],
            valueDescriptionProvider: describeX
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: data.yAxisLabel,
            range: data.yRange,
            gridlinePositions: [],
            valueDescriptionProvider: describeY
        )
        let series = AXDataSeriesDescriptor(
            name: data.title,
            isContinuous: true,
            dataPoints: data.points.map {
                AXDataPoint(x: $0.x, y: $0.y, additionalValues: [], label: $0.label)
            }
        )
        return AXChartDescriptor(
            title: data.title,
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        // The descriptor is rebuilt from `data` whenever the view updates, so
        // there is no separately-held state to reconcile here.
    }
}

#endif

/// Attaches an audio graph when there's one worth attaching.
///
/// A no-op on watchOS, and a no-op anywhere when `data` is `nil` — see
/// ``ChartAudioGraphData/series(title:xAxisLabel:yAxisLabel:points:describeValue:)``
/// for when that happens.
struct ChartAudioGraph: ViewModifier {
    let data: ChartAudioGraphData?
    var describeX: (Double) -> String = { value in
        Date(timeIntervalSinceReferenceDate: value)
            .formatted(.dateTime.month(.abbreviated).day().year())
    }
    let describeY: (Double) -> String

    func body(content: Content) -> some View {
        #if os(iOS)
        if let data {
            content.accessibilityChartDescriptor(
                MetricChartDescriptor(data: data, describeX: describeX, describeY: describeY)
            )
        } else {
            content
        }
        #else
        content
        #endif
    }
}
