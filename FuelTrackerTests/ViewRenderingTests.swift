import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import FuelTracker

// MARK: - Rendering harness

/// Hosts a view in a real window and forces layout, so the view's body —
/// including chart content and empty-state branches — actually executes.
@MainActor
private func render(_ view: some View, container: ModelContainer) {
    let hosting = UIHostingController(rootView: AnyView(view.modelContainer(container)))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = hosting
    window.makeKeyAndVisible()
    hosting.view.layoutIfNeeded()
    #expect(hosting.view.bounds.width > 0)
}

// MARK: - Scenarios

@MainActor
private enum Scenario {
    static func empty() -> ModelContainer {
        ModelContainerFactory.makeInMemory()
    }

    static func vehicleOnly() -> (ModelContainer, Vehicle) {
        let container = ModelContainerFactory.makeInMemory()
        let vehicle = Vehicle(name: "Test Car", make: "Honda", model: "Civic", year: 2021)
        container.mainContext.insert(vehicle)
        return (container, vehicle)
    }

    /// A vehicle with six deterministic fill-ups (one partial) spanning
    /// three months, enough to light up every KPI and chart.
    static func populated() -> (ModelContainer, Vehicle) {
        let (container, vehicle) = vehicleOnly()
        var odometer = 10_000.0
        for index in 0..<6 {
            let date = Calendar.current.date(
                from: DateComponents(year: 2025, month: 1 + index / 2, day: index.isMultiple(of: 2) ? 5 : 20)
            )!
            odometer += index == 0 ? 0 : 300
            let entry = FuelEntry(
                date: date,
                odometer: odometer,
                gallons: 10,
                pricePerGallon: 3.0 + Double(index) * 0.1,
                isFullTank: index != 2,
                station: "Shell",
                vehicle: vehicle
            )
            container.mainContext.insert(entry)
        }
        return (container, vehicle)
    }
}

// MARK: - Screens

@MainActor
struct ScreenRenderingTests {
    @Test func contentViewWithNoData() {
        render(ContentView(), container: Scenario.empty())
    }

    @Test func contentViewWithData() {
        let (container, _) = Scenario.populated()
        render(ContentView(), container: container)
    }

    @Test func dashboardWelcomeState() {
        render(
            DashboardView(selectedVehicle: nil, vehicles: [], selectedVehicleID: .constant("")),
            container: Scenario.empty()
        )
    }

    @Test func dashboardNoDataState() {
        let (container, vehicle) = Scenario.vehicleOnly()
        render(
            DashboardView(selectedVehicle: vehicle, vehicles: [vehicle], selectedVehicleID: .constant("")),
            container: container
        )
    }

    @Test func dashboardPopulated() {
        let (container, vehicle) = Scenario.populated()
        render(
            DashboardView(selectedVehicle: vehicle, vehicles: [vehicle], selectedVehicleID: .constant("")),
            container: container
        )
    }

    @Test func fillUpsListStates() {
        render(
            FillUpsListView(selectedVehicle: nil, vehicles: [], selectedVehicleID: .constant("")),
            container: Scenario.empty()
        )

        let (emptyContainer, emptyVehicle) = Scenario.vehicleOnly()
        render(
            FillUpsListView(selectedVehicle: emptyVehicle, vehicles: [emptyVehicle], selectedVehicleID: .constant("")),
            container: emptyContainer
        )

        let (container, vehicle) = Scenario.populated()
        render(
            FillUpsListView(selectedVehicle: vehicle, vehicles: [vehicle], selectedVehicleID: .constant("")),
            container: container
        )
    }

    @Test func addFillUpFormNewAndEditing() {
        let (container, vehicle) = Scenario.populated()
        render(AddEditFillUpView(defaultVehicle: vehicle), container: container)

        let entry = vehicle.fillUps.first!
        render(AddEditFillUpView(entry: entry), container: container)
    }

    @Test func vehiclesScreenStates() {
        render(VehiclesView(selectedVehicleID: .constant("")), container: Scenario.empty())

        let (container, vehicle) = Scenario.populated()
        render(VehiclesView(selectedVehicleID: .constant(vehicle.id.uuidString)), container: container)

        render(AddEditVehicleView(), container: container)
        render(AddEditVehicleView(vehicle: vehicle), container: container)
    }

    @Test func vehiclePickerMenuWithMultipleVehicles() {
        let (container, first) = Scenario.populated()
        let second = Vehicle(name: "Weekend Car")
        container.mainContext.insert(second)
        render(
            VehiclePickerMenu(
                vehicles: [first, second],
                selectedVehicleID: .constant(first.id.uuidString),
                selectedVehicle: first
            ),
            container: container
        )
    }
}

// MARK: - Components

@MainActor
struct ComponentRenderingTests {
    private var points: [DateValuePoint] {
        (0..<5).map { index in
            DateValuePoint(
                id: UUID(),
                date: Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 1 + index * 7))!,
                value: 30.0 + Double(index)
            )
        }
    }

    private var totals: [MonthlyTotal] {
        (1...3).map { month in
            let date = Calendar.current.date(from: DateComponents(year: 2025, month: month, day: 1))!
            return MonthlyTotal(id: date, month: date, totalSpent: 120, totalGallons: 35, miles: 900, fillUpCount: 3)
        }
    }

    @Test func lineChartFullModeWithAverageAndCustomAxis() {
        render(
            MetricLineChart(
                points: points,
                metric: .economy,
                average: 32,
                valueLabel: Format.mpg,
                yAxisLabel: Format.mpg
            ),
            container: Scenario.empty()
        )
    }

    @Test func lineChartCompactMode() {
        render(
            MetricLineChart(points: points, metric: .price, compact: true, valueLabel: Format.fuelPrice),
            container: Scenario.empty()
        )
    }

    @Test func barChartFullAndCompactModes() {
        render(
            MonthlyBarChart(totals: totals, value: \.totalSpent, metric: .spending, yAxisLabel: Format.wholeCurrency),
            container: Scenario.empty()
        )
        render(
            MonthlyBarChart(totals: totals, value: \.miles, metric: .distance, compact: true),
            container: Scenario.empty()
        )
    }

    @Test func kpiCardWithAndWithoutData() {
        let full = KPI(title: "Avg MPG", value: "32.1", detail: "Best: 35.0", icon: "leaf.fill", metric: .economy)
        render(KPICard(kpi: full), container: Scenario.empty())

        let placeholder = KPI(title: "Avg MPG", value: nil, icon: "leaf.fill", metric: .economy)
        render(KPICard(kpi: placeholder), container: Scenario.empty())
    }

    @Test func chartCardFrame() {
        render(
            ChartCard(title: "Title", subtitle: "Subtitle") { Text("Content") },
            container: Scenario.empty()
        )
    }
}
