import SwiftUI
import SwiftData
import Charts

enum DashboardTimeRange: String, CaseIterable, Identifiable {
    case threeMonths = "3M"
    case sixMonths = "6M"
    case year = "1Y"
    case all = "All"

    var id: String { rawValue }

    var cutoff: Date? {
        let calendar = Calendar.current
        switch self {
        case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: .now)
        case .sixMonths: return calendar.date(byAdding: .month, value: -6, to: .now)
        case .year: return calendar.date(byAdding: .year, value: -1, to: .now)
        case .all: return nil
        }
    }
}

struct DashboardView: View {
    let selectedVehicle: Vehicle?
    let vehicles: [Vehicle]
    @Binding var selectedVehicleID: String

    @State private var timeRange: DashboardTimeRange = .all
    @State private var showingAddSheet = false
    @State private var entryBeingReviewed: FuelEntry?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        // Computed once per render; every KPI and chart reads from this.
        let statistics = FuelStatistics(entries: filteredEntries)

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
                             ? "Log a few fill-ups to see MPG, spending, and price trends."
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
                    ForEach(statistics.dashboardKPIs) { kpi in
                        KPICard(kpi: kpi)
                    }
                }

                if statistics.mpgPoints.count >= 2 {
                    ChartCard(title: "Fuel Economy", subtitle: "MPG per full-tank fill-up") {
                        MetricLineChart(
                            points: statistics.mpgSeries,
                            metric: .economy,
                            average: statistics.averageMPG,
                            valueLabel: { "\(Format.mpg($0)) MPG" }
                        )
                    }
                } else {
                    mpgHint
                }

                if statistics.pricePoints.count >= 2 {
                    ChartCard(title: "Gas Price", subtitle: "Price per gallon you paid") {
                        MetricLineChart(
                            points: statistics.priceSeries,
                            metric: .price,
                            valueLabel: Format.fuelPrice,
                            yAxisLabel: Format.plainCurrency
                        )
                    }
                }

                if statistics.weekdayPrices.count >= 2 {
                    weekdayPriceCard(statistics)
                }

                if statistics.odometerPoints.count >= 2 {
                    ChartCard(title: "Odometer", subtitle: "Mileage recorded at each fill-up") {
                        MetricLineChart(
                            points: statistics.odometerSeries,
                            metric: .distance,
                            valueLabel: { "\(Format.odometer($0)) mi" },
                            yAxisLabel: Format.compactMiles
                        )
                    }
                }

                if statistics.monthlyTotals.count >= 2 {
                    ChartCard(title: "Monthly Spending", subtitle: "Total fuel cost by month") {
                        MonthlyBarChart(
                            totals: statistics.monthlyTotals,
                            value: \.totalSpent,
                            metric: .spending,
                            yAxisLabel: Format.wholeCurrency
                        )
                    }

                    ChartCard(title: "Monthly Distance", subtitle: "Miles driven by month") {
                        MonthlyBarChart(
                            totals: statistics.monthlyTotals,
                            value: \.miles,
                            metric: .distance
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
                Text("Average price per gallon by weekday")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let insight = statistics.weekdayPriceInsight {
                Label(insight, systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }

            WeekdayPriceChart(
                prices: statistics.weekdayPrices,
                cheapestWeekday: statistics.cheapestWeekday?.weekday
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
                    .foregroundStyle(.orange)

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
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func suspectMessage(for entry: FuelEntry, statistics: FuelStatistics) -> String {
        let date = entry.date.formatted(date: .abbreviated, time: .omitted)
        guard let mpg = statistics.mpg(for: entry) else {
            return "The fill-up on \(date) produced an unusually high MPG. If you skipped logging a fill before it, mark it on the entry to keep your stats honest."
        }
        if let median = statistics.medianMPG {
            return "The fill-up on \(date) computed \(Format.mpg(mpg)) MPG — far above your typical \(Format.mpg(median)). If you skipped logging a fill before it, mark it on the entry to keep your stats honest."
        }
        return "The fill-up on \(date) computed \(Format.mpg(mpg)) MPG, which looks physically impossible. If you skipped logging a fill before it, mark it on the entry to keep your stats honest."
    }

    private var mpgHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("MPG needs at least two full-tank fill-ups")
                .font(.subheadline.weight(.medium))
            Text("Fill the tank completely and log it — from your second full tank on, MPG is calculated automatically.")
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
}
