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
                    .disabled(selectedVehicle == nil)
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddEditFillUpView(defaultVehicle: selectedVehicle)
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

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
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
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
