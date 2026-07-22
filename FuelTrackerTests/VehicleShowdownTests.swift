import Foundation
import Testing
@testable import FuelTracker

private func day(_ dayOfMonth: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: dayOfMonth))!
}

private func mk(_ dayOfMonth: Int, _ odometer: Double, _ gallons: Double, _ price: Double) -> FuelEntry {
    FuelEntry(date: day(dayOfMonth), odometer: odometer, gallons: gallons, pricePerGallon: price)
}

/// ~40 MPG history (two 400-mile / 10-gal segments) at the given price.
private func efficient(price: Double) -> [FuelEntry] {
    [mk(1, 10_000, 10, price), mk(10, 10_400, 10, price), mk(20, 10_800, 10, price)]
}

/// ~25 MPG history (two 250-mile / 10-gal segments) at the given price.
private func thirsty(price: Double) -> [FuelEntry] {
    [mk(1, 20_000, 10, price), mk(10, 20_250, 10, price), mk(20, 20_500, 10, price)]
}

private extension VehicleShowdown {
    func row(_ id: String) -> ShowdownRow? { rows.first { $0.id == id } }
}

struct VehicleShowdownTests {
    // MARK: - The winner helper (directions, ties, missing data)

    @Test func winnerHelperResolvesDirectionsTiesAndMissingData() {
        // Higher is better.
        #expect(VehicleShowdown.winner(left: 40, right: 25, lowerIsBetter: false) == .left)
        #expect(VehicleShowdown.winner(left: 25, right: 40, lowerIsBetter: false) == .right)
        // Lower is better.
        #expect(VehicleShowdown.winner(left: 0.08, right: 0.10, lowerIsBetter: true) == .left)
        #expect(VehicleShowdown.winner(left: 0.10, right: 0.08, lowerIsBetter: true) == .right)
        // Ties, including within the epsilon.
        #expect(VehicleShowdown.winner(left: 30, right: 30, lowerIsBetter: false) == .tie)
        #expect(VehicleShowdown.winner(left: 30, right: 30.00005, lowerIsBetter: false) == .tie)
        // A missing side is no contest, not a win for the side with data.
        #expect(VehicleShowdown.winner(left: nil, right: 30, lowerIsBetter: false) == .notContested)
        #expect(VehicleShowdown.winner(left: 30, right: nil, lowerIsBetter: false) == .notContested)
        #expect(VehicleShowdown.winner(left: nil, right: nil, lowerIsBetter: false) == .notContested)
    }

    // MARK: - Row-level outcomes

    @Test func higherMPGAndLowerCostPerMileWinTheirRows() {
        let showdown = VehicleShowdown(
            leftName: "Eff", leftEntries: efficient(price: 3.00),
            rightName: "Guzzler", rightEntries: thirsty(price: 3.00)
        )
        #expect(showdown.row("mpg")?.winner == .left)   // 40 > 25
        #expect(showdown.row("cpm")?.winner == .left)   // 0.075 < 0.12
        #expect(showdown.row("ppg")?.winner == .tie)    // both $3.00
        #expect(showdown.leftWins == 2)
        #expect(showdown.rightWins == 0)
        #expect(showdown.hasContest)
    }

    @Test func aSplitDecisionCountsWinsPerSide() {
        // Efficient but pricey vs thirsty but cheap: the cheap one wins on
        // price and cost-per-mile, the efficient one only on MPG.
        let showdown = VehicleShowdown(
            leftName: "Eff", leftEntries: efficient(price: 3.60),
            rightName: "Cheap", rightEntries: thirsty(price: 2.00)
        )
        #expect(showdown.row("mpg")?.winner == .left)    // 40 > 25
        #expect(showdown.row("ppg")?.winner == .right)   // $2.00 < $3.60
        #expect(showdown.row("cpm")?.winner == .right)   // 0.08 < 0.09
        #expect(showdown.leftWins == 1)
        #expect(showdown.rightWins == 2)
    }

    @Test func informationalRowsNeverHaveAWinner() {
        let showdown = VehicleShowdown(
            leftName: "Eff", leftEntries: efficient(price: 3.00),
            rightName: "Guzzler", rightEntries: thirsty(price: 3.00)
        )
        // Miles, spending, and fill-ups differ between the two, but none is a
        // "win" — lower isn't inherently better.
        #expect(showdown.row("miles")?.winner == .notContested)
        #expect(showdown.row("spent")?.winner == .notContested)
        #expect(showdown.row("fills")?.winner == .notContested)
    }

    @Test func missingDataMeansNoContestForThatRow() {
        // Right vehicle has a single fill: no MPG, no cost-per-mile, but it
        // does have a price. Only the price row is a contest.
        let showdown = VehicleShowdown(
            leftName: "Eff", leftEntries: efficient(price: 3.00),
            rightName: "New", rightEntries: [mk(1, 30_000, 10, 3.10)]
        )
        #expect(showdown.row("mpg")?.winner == .notContested)
        #expect(showdown.row("cpm")?.winner == .notContested)
        #expect(showdown.row("ppg")?.winner == .left)   // $3.00 < $3.10
        #expect(showdown.leftWins == 1)
        #expect(showdown.hasContest)
    }

    // MARK: - Degenerate & hostile

    @Test func twoEmptyVehiclesHaveNoContest() {
        let showdown = VehicleShowdown(leftName: "A", leftEntries: [], rightName: "B", rightEntries: [])
        #expect(showdown.rows.count == 6)
        #expect(showdown.rows.allSatisfy { $0.winner == .notContested })
        #expect(!showdown.hasContest)
        #expect(showdown.leftWins == 0)
        #expect(showdown.rightWins == 0)
        #expect(showdown.leftMPGSeries.isEmpty)
    }

    @Test func identicalVehiclesTieEveryContestedRowWithNoWinner() {
        let showdown = VehicleShowdown(
            leftName: "A", leftEntries: efficient(price: 3.00),
            rightName: "B", rightEntries: efficient(price: 3.00)
        )
        #expect(showdown.row("mpg")?.winner == .tie)
        #expect(showdown.row("cpm")?.winner == .tie)
        #expect(showdown.row("ppg")?.winner == .tie)
        #expect(showdown.leftWins == 0)
        #expect(showdown.rightWins == 0)
        #expect(showdown.hasContest)   // there IS data — just no winner
    }

    // MARK: - Formatting, series, and structure

    @Test func rowValuesAreFormatted() {
        let showdown = VehicleShowdown(
            leftName: "Eff", leftEntries: efficient(price: 3.00),
            rightName: "Guzzler", rightEntries: thirsty(price: 3.20)
        )
        #expect(showdown.row("mpg")?.left == Format.mpg(40.0))
        #expect(showdown.row("mpg")?.right == Format.mpg(25.0))
        #expect(showdown.row("ppg")?.right == Format.fuelPrice(3.20))
    }

    @Test func mpgSeriesAreExposedPerVehicle() {
        let showdown = VehicleShowdown(
            leftName: "Eff", leftEntries: efficient(price: 3.00),
            rightName: "Guzzler", rightEntries: thirsty(price: 3.00)
        )
        #expect(showdown.leftMPGSeries.count == 2)
        #expect(showdown.rightMPGSeries.count == 2)
    }

    @Test func rowsHaveStableIdsAndOrder() {
        let showdown = VehicleShowdown(
            leftName: "A", leftEntries: efficient(price: 3.00),
            rightName: "B", rightEntries: thirsty(price: 3.00)
        )
        #expect(showdown.rows.map(\.id) == ["mpg", "cpm", "ppg", "miles", "spent", "fills"])
    }
}
