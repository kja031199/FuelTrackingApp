import Foundation

/// A formatted dashboard stat, ready for display on any platform.
struct KPI: Identifiable {
    let id: String
    let title: String
    let value: String?
    let detail: String?
    let icon: String
    let metric: Metric

    init(
        id: String? = nil,
        title: String,
        value: String?,
        detail: String? = nil,
        icon: String,
        metric: Metric
    ) {
        self.id = id ?? title
        self.title = title
        self.value = value
        self.detail = detail
        self.icon = icon
        self.metric = metric
    }

    /// One spoken phrase combining title, value, and detail, so VoiceOver
    /// reads the card as a single coherent stat rather than three fragments.
    var accessibilityLabel: String {
        var parts = [title, value ?? "no data yet"]
        if let detail { parts.append(detail) }
        return parts.joined(separator: ", ")
    }
}

extension FuelStatistics {
    /// The full KPI set shown on the iPhone dashboard.
    var dashboardKPIs: [KPI] {
        [
            KPI(
                title: "Avg MPG",
                value: averageMPG.map(Format.mpg),
                icon: "leaf.fill",
                metric: .economy
            ),
            KPI(
                title: "Last MPG",
                value: lastMPG.map(Format.mpg),
                detail: bestMPG.map { "Best: \(Format.mpg($0))" },
                icon: "gauge.with.dots.needle.67percent",
                metric: .economy
            ),
            KPI(
                title: "Total Spent",
                value: Format.currency(totalSpent),
                detail: averageMonthlySpend.map { "\(Format.currency($0))/mo avg" },
                icon: "dollarsign.circle.fill",
                metric: .spending
            ),
            KPI(
                title: "Cost per Mile",
                value: costPerMile.map(Format.costPerMile),
                icon: "road.lanes",
                metric: .spending
            ),
            KPI(
                title: "Avg Price/Gal",
                value: averagePricePerGallon.map(Format.fuelPrice),
                detail: lastPricePerGallon.map { "Last: \(Format.fuelPrice($0))" },
                icon: "fuelpump.fill",
                metric: .price
            ),
            KPI(
                title: "Miles Tracked",
                value: Format.odometer(milesTracked),
                detail: averageMilesBetweenFillUps.map { "\(Format.odometer($0)) mi/fill avg" },
                icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                metric: .distance
            ),
            KPI(
                title: "Fill-Ups",
                value: "\(fillUpCount)",
                detail: averageGallonsPerFillUp.map { "\(Format.gallons($0)) gal avg" },
                icon: "list.number",
                metric: .distance
            ),
            KPI(
                title: "Total Gallons",
                value: Format.gallons(totalGallons),
                detail: averageFillUpCost.map { "\(Format.currency($0))/fill avg" },
                icon: "drop.fill",
                metric: .price
            ),
        ]
    }

    /// The condensed KPI set sized for the watch screen.
    var compactKPIs: [KPI] {
        [
            KPI(title: "Avg MPG", value: averageMPG.map(Format.mpg), icon: "leaf.fill", metric: .economy),
            KPI(title: "Last MPG", value: lastMPG.map(Format.mpg), icon: "gauge.with.dots.needle.67percent", metric: .economy),
            KPI(title: "Spent", value: Format.currency(totalSpent), icon: "dollarsign.circle.fill", metric: .spending),
            KPI(title: "Cost/Mi", value: costPerMile.map(Format.costPerMile), icon: "road.lanes", metric: .spending),
            KPI(title: "Avg $/Gal", value: averagePricePerGallon.map(Format.fuelPrice), icon: "fuelpump.fill", metric: .price),
            KPI(title: "Miles", value: Format.compactMiles(milesTracked), icon: "point.topleft.down.to.point.bottomright.curvepath.fill", metric: .distance),
        ]
    }
}
