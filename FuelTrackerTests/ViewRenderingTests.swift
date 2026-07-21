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

    /// A vehicle whose history is full of data-entry accidents: duplicate
    /// odometers, a zero-gallon fill, a free fill, partial-only stretches,
    /// same-day entries, and a future date. Screens must render it all.
    static func pathological() -> (ModelContainer, Vehicle) {
        let (container, vehicle) = vehicleOnly()
        let entries = [
            FuelEntry(date: day(2025, 1, 5), odometer: 10_000, gallons: 10, pricePerGallon: 3.0, vehicle: vehicle),
            FuelEntry(date: day(2025, 1, 5), odometer: 10_000, gallons: 10, pricePerGallon: 3.0, vehicle: vehicle),
            FuelEntry(date: day(2025, 1, 12), odometer: 10_300, gallons: 0, pricePerGallon: 3.0, vehicle: vehicle),
            FuelEntry(date: day(2025, 1, 20), odometer: 10_500, gallons: 5, pricePerGallon: 0, vehicle: vehicle),
            FuelEntry(date: day(2025, 2, 2), odometer: 10_700, gallons: 4, pricePerGallon: 3.2, isFullTank: false, vehicle: vehicle),
            FuelEntry(date: day(2030, 6, 1), odometer: 11_000, gallons: 9, pricePerGallon: 3.4, vehicle: vehicle),
        ]
        for entry in entries {
            container.mainContext.insert(entry)
        }
        return (container, vehicle)
    }

    private static func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
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

// MARK: - Hostile-data rendering

@MainActor
struct AdversarialRenderingTests {
    @Test func screensSurvivePathologicalHistory() {
        // Duplicate odometers, zero gallons, free fuel, partial-only runs,
        // and future dates — every screen must render without incident.
        let (container, vehicle) = Scenario.pathological()
        render(
            DashboardView(selectedVehicle: vehicle, vehicles: [vehicle], selectedVehicleID: .constant("")),
            container: container
        )
        render(
            FillUpsListView(selectedVehicle: vehicle, vehicles: [vehicle], selectedVehicleID: .constant("")),
            container: container
        )
        render(ContentView(), container: container)
    }

    @Test func dashboardRendersTheMissedFillUpBanner() {
        // Segments of 30/31/32 MPG then an impossible 66 — the suspect
        // banner path must render.
        let (container, vehicle) = Scenario.vehicleOnly()
        let odometers: [Double] = [10_000, 10_300, 10_610, 10_930, 11_590]
        for (index, odometer) in odometers.enumerated() {
            let date = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 1 + index * 9))!
            container.mainContext.insert(
                FuelEntry(date: date, odometer: odometer, gallons: 10, pricePerGallon: 3.5, vehicle: vehicle)
            )
        }
        render(
            DashboardView(selectedVehicle: vehicle, vehicles: [vehicle], selectedVehicleID: .constant("")),
            container: container
        )
    }

    @Test func weekdayPriceChartRenders() {
        let prices = [
            WeekdayPrice(weekday: 3, symbol: "Tue", averagePrice: 3.20, fillUpCount: 4),
            WeekdayPrice(weekday: 5, symbol: "Thu", averagePrice: 3.28, fillUpCount: 2),
            WeekdayPrice(weekday: 6, symbol: "Fri", averagePrice: 3.31, fillUpCount: 3),
        ]
        render(WeekdayPriceChart(prices: prices, cheapestWeekday: 3), container: Scenario.empty())

        // Degenerate: one weekday, and no cheapest to highlight.
        render(
            WeekdayPriceChart(
                prices: [WeekdayPrice(weekday: 3, symbol: "Tue", averagePrice: 3.2, fillUpCount: 1)],
                cheapestWeekday: nil
            ),
            container: Scenario.empty()
        )
    }

    @Test func lineChartRendersWithZeroAndOnePoint() {
        // The dashboard gates charts behind a two-point minimum, but the
        // component itself must tolerate less if a caller forgets.
        render(
            MetricLineChart(points: [], metric: .economy, valueLabel: Format.mpg),
            container: Scenario.empty()
        )
        let single = [DateValuePoint(id: UUID(), date: .now, value: 32)]
        render(
            MetricLineChart(points: single, metric: .economy, average: 32, valueLabel: Format.mpg),
            container: Scenario.empty()
        )
    }

    @Test func barChartRendersWithEmptyAndAllZeroData() {
        render(
            MonthlyBarChart(totals: [], value: \.totalSpent, metric: .spending),
            container: Scenario.empty()
        )
        let zeroed = [MonthlyTotal(id: .now, month: .now, totalSpent: 0, totalGallons: 0, miles: 0, fillUpCount: 0)]
        render(
            MonthlyBarChart(totals: zeroed, value: \.totalSpent, metric: .spending),
            container: Scenario.empty()
        )
    }

    @Test func kpiCardSurvivesAbsurdlyLongStrings() {
        let kpi = KPI(
            title: String(repeating: "Very Long Title ", count: 20),
            value: String(repeating: "9", count: 60),
            detail: String(repeating: "detail ", count: 40),
            icon: "leaf.fill",
            metric: .economy
        )
        render(KPICard(kpi: kpi), container: Scenario.empty())
    }

    @Test func addFillUpFormRendersWithNoVehiclesAtAll() {
        render(AddEditFillUpView(), container: Scenario.empty())
    }

    @Test func pumpScannerFallsBackGracefullyWithoutACamera() {
        // In the Simulator/test host there is no camera, so this executes
        // the ContentUnavailableView branch rather than live scanning.
        render(PumpScannerView { _, _ in }, container: Scenario.empty())
    }

    @Test func receiptViewerRendersValidAndInvalidData() {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 96), format: format).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 96))
        }
        render(ReceiptViewer(imageData: image.jpegData(compressionQuality: 0.8)!), container: Scenario.empty())
        // Unreadable data hits the ContentUnavailableView branch.
        render(ReceiptViewer(imageData: Data([0, 1, 2, 3])), container: Scenario.empty())
    }

    @Test func fillUpFormRendersWithAReceiptAttached() {
        let (container, vehicle) = Scenario.populated()
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40), format: format).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        let entry = vehicle.fillUps.first!
        entry.receiptImageData = image.jpegData(compressionQuality: 0.8)
        render(AddEditFillUpView(entry: entry), container: container)
    }
}
