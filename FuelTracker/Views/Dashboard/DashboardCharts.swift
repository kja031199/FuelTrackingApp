import SwiftUI
import Charts

// Each chart plots a single series and keeps a fixed color per metric across
// the whole app: blue = fuel economy, orange = gas price, purple = spending,
// teal = distance. Titles live on the enclosing ChartCard.

/// Fuel economy over time, with a dashed average rule line.
struct MPGChart: View {
    let points: [MPGPoint]
    let average: Double?

    @State private var selectedDate: Date?

    private var selectedPoint: MPGPoint? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("MPG", point.mpg)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("MPG", point.mpg)
                )
                .foregroundStyle(.blue)
                .symbolSize(selectedPoint?.id == point.id ? 100 : 36)
            }

            if let average {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg \(Format.mpg(average))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.date))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        selectionCallout(
                            title: selectedPoint.date.formatted(.dateTime.month(.abbreviated).day()),
                            value: "\(Format.mpg(selectedPoint.mpg)) MPG"
                        )
                    }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXSelection(value: $selectedDate)
    }
}

/// Price per gallon paid at each fill-up.
struct PriceChart: View {
    let points: [PricePoint]

    @State private var selectedDate: Date?

    private var selectedPoint: PricePoint? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Price", point.pricePerGallon)
                )
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Price", point.pricePerGallon)
                )
                .foregroundStyle(.orange)
                .symbolSize(selectedPoint?.id == point.id ? 100 : 36)
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.date))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        selectionCallout(
                            title: selectedPoint.date.formatted(.dateTime.month(.abbreviated).day()),
                            value: Format.fuelPrice(selectedPoint.pricePerGallon)
                        )
                    }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let price = value.as(Double.self) {
                        Text(price.formatted(.currency(code: Format.currencyCode).precision(.fractionLength(2))))
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
    }
}

/// Total fuel spending aggregated by calendar month.
struct MonthlySpendChart: View {
    let totals: [MonthlyTotal]

    var body: some View {
        Chart(totals) { total in
            BarMark(
                x: .value("Month", total.month, unit: .month),
                y: .value("Spent", total.totalSpent)
            )
            .foregroundStyle(.purple)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount.formatted(.currency(code: Format.currencyCode).precision(.fractionLength(0))))
                    }
                }
            }
        }
    }
}

/// Miles driven per calendar month (odometer span within the month).
struct MonthlyMilesChart: View {
    let totals: [MonthlyTotal]

    var body: some View {
        Chart(totals) { total in
            BarMark(
                x: .value("Month", total.month, unit: .month),
                y: .value("Miles", total.miles)
            )
            .foregroundStyle(.teal)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
            }
        }
    }
}

/// Small tooltip shown above the selection rule on line charts.
private func selectionCallout(title: String, value: String) -> some View {
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
    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))
}
