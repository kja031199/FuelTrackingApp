import SwiftUI
import Charts

/// Compact KPI grid shown below the fill-up form, built from the same
/// shared KPI definitions as the iPhone dashboard.
struct WatchKPISection: View {
    let statistics: FuelStatistics
    @Environment(UnitSettings.self) private var unitSettings: UnitSettings?

    private var units: UnitPreferences { unitSettings?.preferences ?? .us }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Stats")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(statistics.compactKPIs(units: units)) { kpi in
                    WatchKPICell(kpi: kpi)
                }
            }
        }
    }
}

struct WatchKPICell: View {
    let kpi: KPI

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(kpi.title)
                .font(.system(size: 11))
                .foregroundStyle(kpi.metric.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(kpi.value ?? "—")
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color.gray.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Compact charts using the shared metric chart components.
struct WatchChartsSection: View {
    let statistics: FuelStatistics
    @Environment(UnitSettings.self) private var unitSettings: UnitSettings?

    private var units: UnitPreferences { unitSettings?.preferences ?? .us }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if statistics.mpgPoints.count >= 2 {
                let economySeries = statistics.mpgSeries.mapValues { units.economy.fromMPG($0) ?? $0 }
                let economyAbbr = units.economy.abbreviation
                chartCard(economyAbbr) {
                    MetricLineChart(
                        points: economySeries,
                        metric: .economy,
                        compact: true,
                        valueLabel: { "\($0.formatted(.number.precision(.fractionLength(1)))) \(economyAbbr)" }
                    )
                }
            }

            if statistics.pricePoints.count >= 2 {
                chartCard("Gas Price") {
                    MetricLineChart(
                        points: statistics.priceSeries,
                        metric: .price,
                        compact: true,
                        valueLabel: { Format.fuelPrice($0, per: units.volume) }
                    )
                }
            }

            if statistics.monthlyTotals.count >= 2 {
                chartCard("Monthly Spend") {
                    MonthlyBarChart(
                        totals: statistics.monthlyTotals,
                        value: \.totalSpent,
                        metric: .spending,
                        compact: true
                    )
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
