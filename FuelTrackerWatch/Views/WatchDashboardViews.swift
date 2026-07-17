import SwiftUI
import Charts

/// Compact KPI grid shown below the fill-up form.
struct WatchKPISection: View {
    let statistics: FuelStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Stats")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                WatchKPICell(title: "Avg MPG", value: statistics.averageMPG.map(Format.mpg), color: .blue)
                WatchKPICell(title: "Last MPG", value: statistics.lastMPG.map(Format.mpg), color: .blue)
                WatchKPICell(title: "Spent", value: Format.currency(statistics.totalSpent), color: .purple)
                WatchKPICell(
                    title: "Cost/Mi",
                    value: statistics.costPerMile.map {
                        $0.formatted(.currency(code: Format.currencyCode).precision(.fractionLength(2)))
                    },
                    color: .purple
                )
                WatchKPICell(title: "Avg $/Gal", value: statistics.averagePricePerGallon.map(Format.fuelPrice), color: .orange)
                WatchKPICell(
                    title: "Miles",
                    value: statistics.milesTracked.formatted(.number.notation(.compactName).precision(.fractionLength(0...1))),
                    color: .teal
                )
            }
        }
    }
}

struct WatchKPICell: View {
    let title: String
    let value: String?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value ?? "—")
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color.gray.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Simplified single-series charts sized for the watch screen.
struct WatchChartsSection: View {
    let statistics: FuelStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if statistics.mpgPoints.count >= 2 {
                chartCard("MPG") {
                    Chart(statistics.mpgPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("MPG", point.mpg)
                        )
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis(.hidden)
                }
            }

            if statistics.pricePoints.count >= 2 {
                chartCard("Gas Price") {
                    Chart(statistics.pricePoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Price", point.pricePerGallon)
                        )
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis(.hidden)
                }
            }

            if statistics.monthlyTotals.count >= 2 {
                chartCard("Monthly Spend") {
                    Chart(statistics.monthlyTotals) { total in
                        BarMark(
                            x: .value("Month", total.month, unit: .month),
                            y: .value("Spent", total.totalSpent)
                        )
                        .foregroundStyle(.purple)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2))
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .month)) { _ in
                            AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                        }
                    }
                }
            }
        }
    }

    private func chartCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
                .frame(height: 80)
        }
    }
}

#Preview {
    ScrollView {
        let statistics = FuelStatistics(entries: [])
        WatchKPISection(statistics: statistics)
    }
}
