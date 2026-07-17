import Foundation

/// A computed MPG data point for one full-tank fill-up.
struct MPGPoint: Identifiable {
    let id: UUID
    let date: Date
    let mpg: Double
    let miles: Double
    let gallons: Double
}

/// A month's worth of aggregated fill-up data.
struct MonthlyTotal: Identifiable {
    let id: Date
    let month: Date
    let totalSpent: Double
    let totalGallons: Double
    let miles: Double
    let fillUpCount: Int
}

/// A point on the price-per-gallon trend.
struct PricePoint: Identifiable {
    let id: UUID
    let date: Date
    let pricePerGallon: Double
}

/// An odometer reading recorded at a fill-up.
struct OdometerPoint: Identifiable {
    let id: UUID
    let date: Date
    let odometer: Double
}

/// All dashboard statistics, computed once from a set of fuel entries.
///
/// MPG is calculated the way Fuelly does it: distance driven between two
/// full-tank fill-ups divided by all fuel added in that span. Partial fills
/// contribute their gallons to the next full-tank segment rather than
/// producing a (misleading) MPG number of their own.
struct FuelStatistics {
    let entries: [FuelEntry]

    let mpgPoints: [MPGPoint]
    let pricePoints: [PricePoint]
    let odometerPoints: [OdometerPoint]
    let monthlyTotals: [MonthlyTotal]

    /// MPG for a specific entry, if it completed a full-tank segment.
    private let mpgByEntryID: [UUID: Double]

    init(entries: [FuelEntry]) {
        let sorted = entries.sorted { $0.odometer < $1.odometer }
        self.entries = sorted

        // MPG segments between full-tank fills.
        var points: [MPGPoint] = []
        var byID: [UUID: Double] = [:]
        var baseline: FuelEntry?
        var gallonsSinceBaseline = 0.0

        for entry in sorted {
            if let base = baseline {
                gallonsSinceBaseline += entry.gallons
                if entry.isFullTank {
                    let miles = entry.odometer - base.odometer
                    if miles > 0, gallonsSinceBaseline > 0 {
                        let mpg = miles / gallonsSinceBaseline
                        points.append(MPGPoint(
                            id: entry.id,
                            date: entry.date,
                            mpg: mpg,
                            miles: miles,
                            gallons: gallonsSinceBaseline
                        ))
                        byID[entry.id] = mpg
                    }
                    baseline = entry
                    gallonsSinceBaseline = 0
                }
            } else if entry.isFullTank {
                // First full tank is the baseline; it has no MPG of its own.
                baseline = entry
                gallonsSinceBaseline = 0
            }
        }
        self.mpgPoints = points
        self.mpgByEntryID = byID

        self.pricePoints = sorted.map {
            PricePoint(id: $0.id, date: $0.date, pricePerGallon: $0.pricePerGallon)
        }

        self.odometerPoints = sorted
            .sorted { $0.date < $1.date }
            .map { OdometerPoint(id: $0.id, date: $0.date, odometer: $0.odometer) }

        // Aggregate by calendar month for the spending / distance charts.
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sorted) { entry in
            calendar.date(from: calendar.dateComponents([.year, .month], from: entry.date)) ?? entry.date
        }
        self.monthlyTotals = grouped
            .map { month, monthEntries in
                let odometers = monthEntries.map(\.odometer)
                let span = (odometers.max() ?? 0) - (odometers.min() ?? 0)
                return MonthlyTotal(
                    id: month,
                    month: month,
                    totalSpent: monthEntries.reduce(0) { $0 + $1.totalCost },
                    totalGallons: monthEntries.reduce(0) { $0 + $1.gallons },
                    miles: span,
                    fillUpCount: monthEntries.count
                )
            }
            .sorted { $0.month < $1.month }
    }

    func mpg(for entry: FuelEntry) -> Double? {
        mpgByEntryID[entry.id]
    }

    // MARK: - KPIs

    var fillUpCount: Int { entries.count }

    var totalSpent: Double {
        entries.reduce(0) { $0 + $1.totalCost }
    }

    var totalGallons: Double {
        entries.reduce(0) { $0 + $1.gallons }
    }

    /// Overall average MPG across every completed full-tank segment
    /// (total miles / total gallons, not an average of averages).
    var averageMPG: Double? {
        let miles = mpgPoints.reduce(0) { $0 + $1.miles }
        let gallons = mpgPoints.reduce(0) { $0 + $1.gallons }
        guard gallons > 0 else { return nil }
        return miles / gallons
    }

    var lastMPG: Double? { mpgPoints.last?.mpg }

    var bestMPG: Double? { mpgPoints.map(\.mpg).max() }

    var worstMPG: Double? { mpgPoints.map(\.mpg).min() }

    /// Gallon-weighted average price paid per gallon.
    var averagePricePerGallon: Double? {
        guard totalGallons > 0 else { return nil }
        return totalSpent / totalGallons
    }

    var lastPricePerGallon: Double? {
        entries.max { $0.date < $1.date }?.pricePerGallon
    }

    /// Distance covered from the first to the last recorded odometer reading.
    var milesTracked: Double {
        guard let first = entries.first, let last = entries.last else { return 0 }
        return last.odometer - first.odometer
    }

    var costPerMile: Double? {
        guard milesTracked > 0 else { return nil }
        // Fuel that moved the car across the tracked span is everything
        // after the first (baseline) fill.
        let spent = entries.dropFirst().reduce(0) { $0 + $1.totalCost }
        guard spent > 0 else { return nil }
        return spent / milesTracked
    }

    var averageFillUpCost: Double? {
        guard fillUpCount > 0 else { return nil }
        return totalSpent / Double(fillUpCount)
    }

    var averageGallonsPerFillUp: Double? {
        guard fillUpCount > 0 else { return nil }
        return totalGallons / Double(fillUpCount)
    }

    /// Average spend per 30 days across the span of recorded entries.
    var averageMonthlySpend: Double? {
        let dates = entries.map(\.date)
        guard let first = dates.min(), let last = dates.max(), first < last else { return nil }
        let days = last.timeIntervalSince(first) / 86_400
        guard days >= 1 else { return nil }
        return totalSpent / days * 30
    }

    /// Average miles driven between fill-ups.
    var averageMilesBetweenFillUps: Double? {
        guard entries.count > 1 else { return nil }
        return milesTracked / Double(entries.count - 1)
    }
}
