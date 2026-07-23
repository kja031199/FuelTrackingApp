import SwiftUI
import SwiftData

/// Chronological history of fill-ups for the selected vehicle.
struct FillUpsListView: View {
    @Environment(\.modelContext) private var modelContext

    let selectedVehicle: Vehicle?
    let vehicles: [Vehicle]
    @Binding var selectedVehicleID: String

    @State private var showingAddSheet = false
    @State private var entryBeingEdited: FuelEntry?
    @State private var filter = FillUpFilter()
    @Environment(UnitSettings.self) private var unitSettings: UnitSettings?

    private var units: UnitPreferences { unitSettings?.preferences ?? .us }

    private var entries: [FuelEntry] {
        (selectedVehicle?.fillUps ?? []).sorted { $0.date > $1.date }
    }

    private var filteredEntries: [FuelEntry] {
        filter.apply(to: entries)
    }

    /// Distinct non-empty station names in this vehicle's history, for the
    /// station filter menu.
    private var stationOptions: [String] {
        Array(Set(entries.map(\.station))).filter { !$0.isEmpty }.sorted()
    }

    var body: some View {
        // Computed once per render and shared by every row.
        let statistics = FuelStatistics(entries: selectedVehicle?.fillUps ?? [])

        NavigationStack {
            Group {
                if selectedVehicle == nil {
                    ContentUnavailableView(
                        "No Vehicle Yet",
                        systemImage: "car",
                        description: Text("Add a vehicle in the Vehicles tab to start logging fill-ups.")
                    )
                } else if entries.isEmpty {
                    ContentUnavailableView {
                        Label("No Fill-Ups Yet", systemImage: "fuelpump")
                    } description: {
                        Text("Log your first fill-up to start tracking fuel economy and costs.")
                    } actions: {
                        Button("Log Fill-Up") { showingAddSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(filteredEntries) { entry in
                            Button {
                                entryBeingEdited = entry
                            } label: {
                                FillUpRow(
                                    entry: entry,
                                    mpg: statistics.mpg(for: entry),
                                    isSuspect: statistics.isSuspectSegment(for: entry),
                                    units: units
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: deleteEntries)
                    }
                    .searchable(text: $filter.searchText, prompt: "Station or notes")
                    .overlay {
                        if filteredEntries.isEmpty {
                            noMatchesView
                        }
                    }
                }
            }
            .navigationTitle("Fill-Ups")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VehiclePickerMenu(
                        vehicles: vehicles,
                        selectedVehicleID: $selectedVehicleID,
                        selectedVehicle: selectedVehicle
                    )
                }
                if let selectedVehicle, !selectedVehicle.fillUps.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        filterMenu
                    }
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
            .sheet(item: $entryBeingEdited) { entry in
                AddEditFillUpView(entry: entry)
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Date Range", selection: $filter.range) {
                ForEach(DashboardTimeRange.allCases) { range in
                    Text(rangeLabel(range)).tag(range)
                }
            }

            Picker("Fuel Grade", selection: $filter.fuelGrade) {
                Text("All Grades").tag(FuelGrade?.none)
                ForEach(FuelGrade.allCases) { grade in
                    Text(grade.rawValue).tag(Optional(grade))
                }
            }

            if !stationOptions.isEmpty {
                Picker("Station", selection: $filter.station) {
                    Text("All Stations").tag(String?.none)
                    ForEach(stationOptions, id: \.self) { station in
                        Text(station).tag(Optional(station))
                    }
                }
            }

            if filter.isActive {
                Divider()
                Button("Clear Filters", systemImage: "xmark.circle") {
                    filter = FillUpFilter()
                }
            }
        } label: {
            Label(
                "Filter",
                systemImage: filter.isActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
    }

    private var noMatchesView: some View {
        ContentUnavailableView {
            Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No fill-ups match your search and filters.")
        } actions: {
            Button("Clear Filters") { filter = FillUpFilter() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func rangeLabel(_ range: DashboardTimeRange) -> String {
        switch range {
        case .threeMonths: "Last 3 Months"
        case .sixMonths: "Last 6 Months"
        case .year: "Last Year"
        case .all: "All Time"
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        let toDelete = offsets.map { filteredEntries[$0] }
        for entry in toDelete {
            modelContext.delete(entry)
        }
    }
}

struct FillUpRow: View {
    let entry: FuelEntry
    let mpg: Double?
    var isSuspect = false
    var units: UnitPreferences = .us

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.headline)
                Spacer()
                Text(Format.currency(entry.totalCost))
                    .font(.headline)
            }

            HStack(spacing: 12) {
                Label(
                    "\(Format.volume(entry.gallons, in: units.volume, withUnit: true)) @ \(Format.fuelPrice(entry.pricePerGallon, per: units.volume))",
                    systemImage: "fuelpump"
                )
                Spacer()
                Label(Format.distance(entry.odometer, in: units.distance, withUnit: true), systemImage: "gauge.open.with.lines.needle.33percent")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if let mpg, let economyText = Format.economy(mpg, in: units.economy) {
                    Text("\(economyText) \(units.economy.abbreviation)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.blue.opacity(0.15), in: Capsule())
                        .foregroundStyle(.blue)
                }
                if isSuspect {
                    Label("Missed a fill?", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
                if entry.missedPreviousFillUp {
                    Text("Missed fill before")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                if !entry.isFullTank {
                    Text("Partial")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                if !entry.station.isEmpty {
                    Text(entry.station)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if entry.hasReceipt {
                    Image(systemName: "paperclip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Has a receipt photo")
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
