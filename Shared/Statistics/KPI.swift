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
    /// The full KPI set shown on the iPhone dashboard, rendered in the given
    /// units. Titles carry the unit (e.g. "Avg MPG" vs "Avg L/100km"); each KPI
    /// keeps a stable `id` so switching units updates a card in place rather
    /// than replacing it. Defaults to US units, which reproduces the canonical
    /// output exactly.
    func dashboardKPIs(units p: UnitPreferences = .us) -> [KPI] {
        [
            KPI(
                id: "avgEconomy",
                title: "Avg \(p.economy.abbreviation)",
                value: averageMPG.flatMap { Format.economy($0, in: p.economy) },
                icon: "leaf.fill",
                metric: .economy
            ),
            KPI(
                id: "lastEconomy",
                title: "Last \(p.economy.abbreviation)",
                value: lastMPG.flatMap { Format.economy($0, in: p.economy) },
                detail: bestMPG.flatMap { Format.economy($0, in: p.economy) }.map { "Best: \($0)" },
                icon: "gauge.with.dots.needle.67percent",
                metric: .economy
            ),
            KPI(
                id: "totalSpent",
                title: "Total Spent",
                value: Format.currency(totalSpent),
                detail: averageMonthlySpend.map { "\(Format.currency($0))/mo avg" },
                icon: "dollarsign.circle.fill",
                metric: .spending
            ),
            KPI(
                id: "costPerDistance",
                title: "Cost per \(p.distance.singularNoun)",
                value: costPerMile.map { Format.costPerDistance($0, in: p.distance) },
                icon: "road.lanes",
                metric: .spending
            ),
            KPI(
                id: "avgPrice",
                title: "Avg Price/\(p.volume.abbreviation)",
                value: averagePricePerGallon.map { Format.fuelPrice($0, per: p.volume) },
                detail: lastPricePerGallon.map { "Last: \(Format.fuelPrice($0, per: p.volume))" },
                icon: "fuelpump.fill",
                metric: .price
            ),
            KPI(
                id: "distanceTracked",
                title: "\(p.distance.name) Tracked",
                value: Format.distance(milesTracked, in: p.distance),
                detail: averageMilesBetweenFillUps.map { "\(Format.distance($0, in: p.distance)) \(p.distance.abbreviation)/fill avg" },
                icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                metric: .distance
            ),
            KPI(
                id: "fillUps",
                title: "Fill-Ups",
                value: "\(fillUpCount)",
                detail: averageGallonsPerFillUp.map { "\(Format.volume($0, in: p.volume)) \(p.volume.abbreviation) avg" },
                icon: "list.number",
                metric: .distance
            ),
            KPI(
                id: "totalVolume",
                title: "Total \(p.volume.name)",
                value: Format.volume(totalGallons, in: p.volume),
                detail: averageFillUpCost.map { "\(Format.currency($0))/fill avg" },
                icon: "drop.fill",
                metric: .price
            ),
        ]
    }

    /// The condensed KPI set sized for the watch screen, in the given units.
    func compactKPIs(units p: UnitPreferences = .us) -> [KPI] {
        [
            KPI(id: "avgEconomy", title: "Avg \(p.economy.abbreviation)", value: averageMPG.flatMap { Format.economy($0, in: p.economy) }, icon: "leaf.fill", metric: .economy),
            KPI(id: "lastEconomy", title: "Last \(p.economy.abbreviation)", value: lastMPG.flatMap { Format.economy($0, in: p.economy) }, icon: "gauge.with.dots.needle.67percent", metric: .economy),
            KPI(id: "spent", title: "Spent", value: Format.currency(totalSpent), icon: "dollarsign.circle.fill", metric: .spending),
            KPI(id: "costPerDistance", title: "Cost/\(p.distance.abbreviation)", value: costPerMile.map { Format.costPerDistance($0, in: p.distance) }, icon: "road.lanes", metric: .spending),
            KPI(id: "avgPrice", title: "Avg $/\(p.volume.abbreviation)", value: averagePricePerGallon.map { Format.fuelPrice($0, per: p.volume) }, icon: "fuelpump.fill", metric: .price),
            KPI(id: "distanceTracked", title: p.distance.name, value: Format.compactDistance(milesTracked, in: p.distance), icon: "point.topleft.down.to.point.bottomright.curvepath.fill", metric: .distance),
        ]
    }
}
