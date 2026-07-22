import Foundation

/// One row comparing a metric across two vehicles.
struct ShowdownRow: Identifiable {
    enum Winner: Equatable {
        case left, right, tie
        /// Not a contest — either informational, or one side lacks the data.
        /// Deliberately NOT named `none`: that collides with `Optional.none`,
        /// so `someRow?.winner == .none` would silently test for nil instead
        /// of this case.
        case notContested
    }

    let id: String
    let title: String
    let icon: String
    let metric: Metric
    let left: String?
    let right: String?
    let winner: Winner
}

/// A head-to-head comparison of two vehicles: a table of metrics with a
/// winner per contested row, plus each vehicle's MPG series for an overlay.
struct VehicleShowdown {
    let leftName: String
    let rightName: String
    let leftMPGSeries: [DateValuePoint]
    let rightMPGSeries: [DateValuePoint]
    let rows: [ShowdownRow]

    init(leftName: String, leftEntries: [FuelEntry], rightName: String, rightEntries: [FuelEntry]) {
        self.leftName = leftName
        self.rightName = rightName

        let left = FuelStatistics(entries: leftEntries)
        let right = FuelStatistics(entries: rightEntries)
        self.leftMPGSeries = left.mpgSeries
        self.rightMPGSeries = right.mpgSeries

        rows = [
            Self.contest(id: "mpg", title: "Avg MPG", icon: "leaf.fill", metric: .economy,
                         left: left.averageMPG, right: right.averageMPG,
                         lowerIsBetter: false, format: Format.mpg),
            Self.contest(id: "cpm", title: "Cost per Mile", icon: "road.lanes", metric: .spending,
                         left: left.costPerMile, right: right.costPerMile,
                         lowerIsBetter: true, format: Format.costPerMile),
            Self.contest(id: "ppg", title: "Avg Price/Gal", icon: "fuelpump.fill", metric: .price,
                         left: left.averagePricePerGallon, right: right.averagePricePerGallon,
                         lowerIsBetter: true, format: Format.fuelPrice),
            // Informational — lower isn't inherently "better" (it can just mean
            // less driving), so these have no winner.
            Self.info(id: "miles", title: "Miles Tracked",
                      icon: "point.topleft.down.to.point.bottomright.curvepath.fill", metric: .distance,
                      left: left.milesTracked, right: right.milesTracked, format: Format.odometer),
            Self.info(id: "spent", title: "Total Spent", icon: "dollarsign.circle.fill", metric: .spending,
                      left: left.totalSpent, right: right.totalSpent, format: Format.currency),
            Self.info(id: "fills", title: "Fill-Ups", icon: "list.number", metric: .distance,
                      left: Double(left.fillUpCount), right: Double(right.fillUpCount),
                      format: { "\(Int($0))" }),
        ]
    }

    /// Contested rows won by the left / right vehicle, for a verdict line.
    var leftWins: Int { rows.filter { $0.winner == .left }.count }
    var rightWins: Int { rows.filter { $0.winner == .right }.count }

    /// True when at least one contested metric had data on both sides —
    /// lets the verdict tell "too close to call" apart from "no data yet."
    var hasContest: Bool { rows.contains { $0.winner != .notContested } }

    // MARK: - Row builders

    private static func contest(
        id: String, title: String, icon: String, metric: Metric,
        left: Double?, right: Double?, lowerIsBetter: Bool, format: (Double) -> String
    ) -> ShowdownRow {
        let leftText = left.map(format)
        let rightText = right.map(format)
        var outcome = winner(left: left, right: right, lowerIsBetter: lowerIsBetter)
        // If both sides render to the same text, the gap is too small to see.
        // Highlighting one as the winner over a difference the user can't read
        // (e.g. "$3.000" vs "$3.000") is just confusing, so call it a tie.
        if (outcome == .left || outcome == .right), leftText == rightText {
            outcome = .tie
        }
        return ShowdownRow(
            id: id, title: title, icon: icon, metric: metric,
            left: leftText, right: rightText, winner: outcome
        )
    }

    private static func info(
        id: String, title: String, icon: String, metric: Metric,
        left: Double, right: Double, format: (Double) -> String
    ) -> ShowdownRow {
        ShowdownRow(id: id, title: title, icon: icon, metric: metric,
                    left: format(left), right: format(right), winner: .notContested)
    }

    /// Decides a contested row. A missing value on either side means there's
    /// nothing to compare, not a win for the side that has data. Non-finite
    /// values (NaN/±∞ from garbage input) are likewise treated as no contest
    /// rather than silently winning or losing every comparison.
    static func winner(left: Double?, right: Double?, lowerIsBetter: Bool) -> ShowdownRow.Winner {
        guard let left, let right, left.isFinite, right.isFinite else { return .notContested }
        if abs(left - right) < 0.0001 { return .tie }
        let leftBetter = lowerIsBetter ? left < right : left > right
        return leftBetter ? .left : .right
    }
}
