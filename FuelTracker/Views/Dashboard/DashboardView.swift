import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    let selectedVehicle: Vehicle?
    let vehicles: [Vehicle]
    @Binding var selectedVehicleID: String

    @State private var timeRange: DashboardTimeRange = .all
    @State private var showingAddSheet = false
    @State private var entryBeingReviewed: FuelEntry?
    @State private var statsMemo = FuelStatisticsMemo()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(UnitSettings.self) private var unitSettings: UnitSettings?

    private var units: UnitPreferences { unitSettings?.preferences ?? .us }

    /// Two columns normally; a single column at accessibility text sizes so
    /// each card has full width to grow into instead of clipping.
    private var kpiColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    private var filteredEntries: [FuelEntry] {
        let all = selectedVehicle?.fillUps ?? []
        guard let cutoff = timeRange.cutoff else { return all }
        return all.filter { $0.date >= cutoff }
    }

    var body: some View {
        // Memoized: rebuilt only when the filtered entries actually change, not
        // on every render (e.g. a unit switch leaves the canonical stats alone).
        let statistics = statsMemo.statistics(for: filteredEntries)

        NavigationStack {
            Group {
                if selectedVehicle == nil {
                    ContentUnavailableView(
                        "Welcome to FuelTracker",
                        systemImage: "fuelpump",
                        description: Text("Add a vehicle in the Vehicles tab, then log fill-ups to see your fuel economy and spending here.")
                    )
                } else if statistics.fillUpCount == 0 {
                    ContentUnavailableView {
                        Label("No Data Yet", systemImage: "chart.xyaxis.line")
                    } description: {
                        Text(timeRange == .all
                             ? "Log a few fill-ups to see \(units.economy.abbreviation), spending, and price trends."
                             : "No fill-ups in this time range. Try a longer range.")
                    } actions: {
                        if timeRange == .all {
                            Button("Log Fill-Up") { showingAddSheet = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    dashboardContent(statistics)
                }
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VehiclePickerMenu(
                        vehicles: vehicles,
                        selectedVehicleID: $selectedVehicleID,
                        selectedVehicle: selectedVehicle
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Fill-Up")
                    .disabled(selectedVehicle == nil)
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddEditFillUpView(defaultVehicle: selectedVehicle)
            }
            .sheet(item: $entryBeingReviewed) { entry in
                AddEditFillUpView(entry: entry)
            }
        }
    }

    private func dashboardContent(_ statistics: FuelStatistics) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Time Range", selection: $timeRange) {
                    ForEach(DashboardTimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                if let suspect = statistics.suspectEntries.first {
                    suspectBanner(for: suspect, statistics: statistics)
                }

                LazyVGrid(columns: kpiColumns, spacing: 12) {
                    ForEach(statistics.dashboardKPIs(units: units)) { kpi in
                        KPICard(kpi: kpi)
                    }
                }

                if statistics.mpgPoints.count >= 2 {
                    // Economy is non-linear across units (L/100km inverts MPG),
                    // so the series itself is converted, not just relabeled.
                    let economySeries = statistics.mpgSeries.mapValues { units.economy.fromMPG($0) ?? $0 }
                    let economyAbbr = units.economy.abbreviation
                    ChartCard(
                        title: "Fuel Economy",
                        subtitle: "\(economyAbbr) per full-tank fill-up",
                        accessibilitySummary: ChartAccessibility.summary(
                            economySeries, unit: economyAbbr,
                            format: { $0.formatted(.number.precision(.fractionLength(1))) }
                        )
                    ) {
                        MetricLineChart(
                            points: economySeries,
                            metric: .economy,
                            accessibilityTitle: "Fuel Economy",
                            average: statistics.averageMPG.flatMap { units.economy.fromMPG($0) },
                            valueLabel: { "\($0.formatted(.number.precision(.fractionLength(1)))) \(economyAbbr)" }
                        )
                    }
                } else {
                    mpgHint
                }

                if statistics.pricePoints.count >= 2 {
                    // Price is linear across volume units, so the canonical
                    // series is plotted and the labels convert per unit.
                    ChartCard(
                        title: "Gas Price",
                        subtitle: "Price per \(units.volume.singularNoun.lowercased()) you paid",
                        accessibilitySummary: ChartAccessibility.summary(
                            statistics.priceSeries, unit: "per \(units.volume.abbreviation)",
                            format: { Format.fuelPrice($0, per: units.volume) }
                        )
                    ) {
                        MetricLineChart(
                            points: statistics.priceSeries,
                            metric: .price,
                            accessibilityTitle: "Gas Price",
                            valueLabel: { Format.fuelPrice($0, per: units.volume) },
                            yAxisLabel: { Format.plainCurrency($0 / units.volume.fromGallons(1)) }
                        )
                    }
                }

                if statistics.weekdayPrices.count >= 2 {
                    weekdayPriceCard(statistics)
                }

                if statistics.odometerPoints.count >= 2 {
                    ChartCard(
                        title: "Odometer",
                        subtitle: "\(units.distance.name) recorded at each fill-up",
                        accessibilitySummary: ChartAccessibility.summary(
                            statistics.odometerSeries, unit: units.distance.abbreviation,
                            format: { Format.distance($0, in: units.distance) }
                        )
                    ) {
                        MetricLineChart(
                            points: statistics.odometerSeries,
                            metric: .distance,
                            accessibilityTitle: "Odometer",
                            valueLabel: { "\(Format.distance($0, in: units.distance)) \(units.distance.abbreviation)" },
                            yAxisLabel: { Format.compactDistance($0, in: units.distance) }
                        )
                    }
                }

                if statistics.monthlyTotals.count >= 2 {
                    ChartCard(title: "Monthly Spending", subtitle: "Total fuel cost by month") {
                        MonthlyBarChart(
                            totals: statistics.monthlyTotals,
                            value: \.totalSpent,
                            metric: .spending,
                            accessibilityTitle: "Monthly Spending",
                            yAxisLabel: Format.wholeCurrency
                        )
                    }

                    ChartCard(title: "Monthly Distance", subtitle: "\(units.distance.name) driven by month") {
                        MonthlyBarChart(
                            totals: statistics.monthlyTotals,
                            value: \.miles,
                            metric: .distance,
                            accessibilityTitle: "Monthly Distance",
                            yAxisLabel: { Format.compactDistance($0, in: units.distance) }
                        )
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    /// "Price by Day" card: the weekday insight headline above a dot plot of
    /// average price per gallon by weekday. Its own layout (rather than the
    /// fixed-height ChartCard) so the headline and chart both get room.
    private func weekdayPriceCard(_ statistics: FuelStatistics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Price by Day")
                    .font(.headline)
                Text("Average price per \(units.volume.singularNoun.lowercased()) by weekday")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let insight = statistics.weekdayPriceInsight(units: units) {
                Label(insight, systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }

            WeekdayPriceChart(
                prices: statistics.weekdayPrices,
                cheapestWeekday: statistics.cheapestWeekday?.weekday,
                units: units
            )
            .frame(height: 180)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Nudge shown when a segment's MPG suggests an unlogged fill-up.
    private func suspectBanner(for entry: FuelEntry, statistics: FuelStatistics) -> some View {
        Button {
            entryBeingReviewed = entry
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label("Possible missed fill-up", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AccessiblePalette.color(.orange, in: colorScheme))

                Text(suspectMessage(for: entry, statistics: statistics))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)

                Text("Review Entry")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                AccessiblePalette.color(.orange, in: colorScheme)
                    .opacity(AccessiblePalette.tintOpacity),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func suspectMessage(for entry: FuelEntry, statistics: FuelStatistics) -> String {
        let date = entry.date.formatted(date: .abbreviated, time: .omitted)
        guard let mpg = statistics.mpg(for: entry) else {
            return "The fill-up on \(date) produced an implausible fuel-economy reading. If you skipped logging a fill before it, mark it on the entry to keep your stats honest."
        }
        let mpgText = Format.economy(mpg, in: units.economy) ?? Format.mpg(mpg)
        let abbr = units.economy.abbreviation
        if let median = statistics.medianMPG, let medianText = Format.economy(median, in: units.economy) {
            return "The fill-up on \(date) computed \(mpgText) \(abbr) — far from your typical \(medianText). If you skipped logging a fill before it, mark it on the entry to keep your stats honest."
        }
        return "The fill-up on \(date) computed \(mpgText) \(abbr), which looks physically impossible. If you skipped logging a fill before it, mark it on the entry to keep your stats honest."
    }

    private var mpgHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("\(units.economy.abbreviation) needs at least two full-tank fill-ups")
                .font(.subheadline.weight(.medium))
            Text("Fill the tank completely and log it — from your second full tank on, \(units.economy.abbreviation) is calculated automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
        .environment(UnitSettings())
        .environment(PrivacySettings())
        .environment(AppLock(authenticator: BiometricAuthenticator()))
}
