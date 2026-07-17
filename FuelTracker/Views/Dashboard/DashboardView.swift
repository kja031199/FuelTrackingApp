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
        let all = selectedVehicle?.entries ?? []
        guard let cutoff = timeRange.cutoff else { return all }
        return all.filter { $0.date >= cutoff }
    }

    private var statistics: FuelStatistics {
        FuelStatistics(entries: filteredEntries)
    }

    var body: some View {
        NavigationStack {
            Group {
                if selectedVehicle == nil {
                    ContentUnavailableView(
                        "Welcome to FuelTracker",
                        systemImage: "fuelpump",
                        description: Text("Add a vehicle in the Vehicles tab, then log fill-ups to see your fuel economy and spending here.")
                    )
                } else if filteredEntries.isEmpty {
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
                    dashboardContent
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

    private var dashboardContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Time Range", selection: $timeRange) {
                    ForEach(DashboardTimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                kpiGrid

                if statistics.mpgPoints.count >= 2 {
                    ChartCard(title: "Fuel Economy", subtitle: "MPG per full-tank fill-up") {
                        MPGChart(points: statistics.mpgPoints, average: statistics.averageMPG)
                    }
                } else {
                    mpgHint
                }

                if statistics.pricePoints.count >= 2 {
                    ChartCard(title: "Gas Price", subtitle: "Price per gallon you paid") {
                        PriceChart(points: statistics.pricePoints)
                    }
                }

                if statistics.monthlyTotals.count >= 2 {
                    ChartCard(title: "Monthly Spending", subtitle: "Total fuel cost by month") {
                        MonthlySpendChart(totals: statistics.monthlyTotals)
                    }

                    ChartCard(title: "Monthly Distance", subtitle: "Miles driven by month") {
                        MonthlyMilesChart(totals: statistics.monthlyTotals)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            KPICard(
                title: "Avg MPG",
                value: statistics.averageMPG.map(Format.mpg),
                icon: "leaf.fill",
                color: .blue
            )
            KPICard(
                title: "Last MPG",
                value: statistics.lastMPG.map(Format.mpg),
                detail: statistics.bestMPG.map { "Best: \(Format.mpg($0))" },
                icon: "gauge.with.dots.needle.67percent",
                color: .blue
            )
            KPICard(
                title: "Total Spent",
                value: Format.currency(statistics.totalSpent),
                detail: statistics.averageMonthlySpend.map { "\(Format.currency($0))/mo avg" },
                icon: "dollarsign.circle.fill",
                color: .purple
            )
            KPICard(
                title: "Cost per Mile",
                value: statistics.costPerMile.map { $0.formatted(.currency(code: Format.currencyCode).precision(.fractionLength(2...3))) },
                icon: "road.lanes",
                color: .purple
            )
            KPICard(
                title: "Avg Price/Gal",
                value: statistics.averagePricePerGallon.map(Format.fuelPrice),
                detail: statistics.lastPricePerGallon.map { "Last: \(Format.fuelPrice($0))" },
                icon: "fuelpump.fill",
                color: .orange
            )
            KPICard(
                title: "Miles Tracked",
                value: Format.odometer(statistics.milesTracked),
                detail: statistics.averageMilesBetweenFillUps.map { "\(Format.odometer($0)) mi/fill avg" },
                icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                color: .teal
            )
            KPICard(
                title: "Fill-Ups",
                value: "\(statistics.fillUpCount)",
                detail: statistics.averageGallonsPerFillUp.map { "\(Format.gallons($0)) gal avg" },
                icon: "list.number",
                color: .teal
            )
            KPICard(
                title: "Total Gallons",
                value: Format.gallons(statistics.totalGallons),
                detail: statistics.averageFillUpCost.map { "\(Format.currency($0))/fill avg" },
                icon: "drop.fill",
                color: .orange
            )
        }
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
