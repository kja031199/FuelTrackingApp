import Foundation
import Testing
@testable import FuelTracker

private func day(_ dayOfMonth: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: dayOfMonth))!
}

private func mk(_ dayOfMonth: Int, _ odometer: Double, _ gallons: Double, _ price: Double) -> FuelEntry {
    FuelEntry(date: day(dayOfMonth), odometer: odometer, gallons: gallons, pricePerGallon: price)
}

/// Like `mk`, but lets a test set the full-tank flag (partial fills produce
/// no MPG segment of their own).
private func mk2(_ dayOfMonth: Int, _ odometer: Double, _ gallons: Double, _ price: Double, full: Bool) -> FuelEntry {
    FuelEntry(date: day(dayOfMonth), odometer: odometer, gallons: gallons, pricePerGallon: price, isFullTank: full)
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

    // MARK: - Non-finite & boundary inputs to the winner helper

    @Test func winnerHelperTreatsNonFiniteValuesAsNoContest() {
        // Garbage stats (NaN / ±∞) must not silently win or lose every
        // comparison — they're "no contest," same as missing data.
        #expect(VehicleShowdown.winner(left: .nan, right: 25, lowerIsBetter: false) == .notContested)
        #expect(VehicleShowdown.winner(left: 25, right: .nan, lowerIsBetter: false) == .notContested)
        #expect(VehicleShowdown.winner(left: .nan, right: .nan, lowerIsBetter: true) == .notContested)
        #expect(VehicleShowdown.winner(left: .infinity, right: 25, lowerIsBetter: true) == .notContested)
        #expect(VehicleShowdown.winner(left: 0.1, right: -.infinity, lowerIsBetter: true) == .notContested)
    }

    @Test func winnerHelperEpsilonHasAConsistentBoundary() {
        // Clearly inside the epsilon → tie; clearly outside → a real winner.
        #expect(VehicleShowdown.winner(left: 30.0, right: 30.00001, lowerIsBetter: false) == .tie)
        #expect(VehicleShowdown.winner(left: 30.0, right: 30.001, lowerIsBetter: false) == .right)
        #expect(VehicleShowdown.winner(left: 30.0, right: 30.001, lowerIsBetter: true) == .left)
        // Negative garbage still resolves by direction without crashing.
        #expect(VehicleShowdown.winner(left: -5, right: -3, lowerIsBetter: true) == .left)
    }

    // MARK: - Display-precision ties

    @Test func differencesTooSmallToSeeAreShownAsTies() {
        // Two vehicles whose price differs only in the 4th decimal. Both
        // render as "$3.000", so highlighting one as the winner would be
        // confusing — the row must read as a tie, not a win.
        let showdown = VehicleShowdown(
            leftName: "A", leftEntries: [mk(1, 10_000, 10, 3.0001)],
            rightName: "B", rightEntries: [mk(1, 20_000, 10, 3.0003)]
        )
        let ppg = showdown.row("ppg")
        #expect(ppg?.left == ppg?.right)       // identical as displayed
        #expect(ppg?.winner == .tie)           // ...so nobody "wins"
        #expect(showdown.leftWins == 0)
        #expect(showdown.rightWins == 0)
    }

    // MARK: - Asymmetric data availability

    @Test func costPerMileCanContestEvenWhenMPGCannot() {
        // A partial-tank-only history yields no full-tank MPG, but it still
        // has miles and spending — so cost-per-mile is a real contest while
        // MPG is not.
        let partialOnly = [
            mk2(1, 10_000, 10, 3.00, full: false),
            mk2(10, 10_300, 10, 3.00, full: false),
            mk2(20, 10_600, 10, 3.00, full: false),
        ]
        let showdown = VehicleShowdown(
            leftName: "Partial", leftEntries: partialOnly,
            rightName: "Normal", rightEntries: thirsty(price: 3.20)
        )
        #expect(showdown.row("mpg")?.left == nil)             // no full-tank MPG
        #expect(showdown.row("mpg")?.winner == .notContested)
        #expect(showdown.row("cpm")?.left != nil)             // but cost/mile exists
        #expect(showdown.row("cpm")?.winner != .notContested) // and it's contested
    }

    @Test func twoBrandNewVehiclesContestOnlyOnPrice() {
        // A single fill each: no MPG, no distance (so no cost/mile), but both
        // have a pump price — only that row is a contest.
        let showdown = VehicleShowdown(
            leftName: "A", leftEntries: [mk(1, 10_000, 10, 3.00)],
            rightName: "B", rightEntries: [mk(1, 20_000, 10, 3.50)]
        )
        #expect(showdown.row("mpg")?.winner == .notContested)
        #expect(showdown.row("cpm")?.winner == .notContested)
        #expect(showdown.row("ppg")?.winner == .left)   // $3.00 < $3.50
        #expect(showdown.hasContest)
        #expect(showdown.leftWins + showdown.rightWins == 1)
    }

    // MARK: - Order independence & duplicate/garbage data

    @Test func resultIsIndependentOfEntryOrder() {
        let ordered = efficient(price: 3.10)
        let arrangements: [[FuelEntry]] = [ordered, Array(ordered.reversed()), ordered.shuffled()]
        let outcomes: [[ShowdownRow.Winner]] = arrangements.map { entries in
            VehicleShowdown(
                leftName: "A", leftEntries: entries,
                rightName: "B", rightEntries: thirsty(price: 3.10)
            ).rows.map(\.winner)
        }
        // However the caller shuffles the entries, the verdict is the same.
        #expect(outcomes.dropFirst().allSatisfy { $0 == outcomes.first })
    }

    @Test func duplicateOdometerReadingsDoNotCrownAPhantomWinner() {
        // Two entries share an odometer (a zero-mile "segment"). It must be
        // skipped, not divide-by-zero into an infinite/NaN MPG that wins.
        let dupes = [
            mk(1, 10_000, 10, 3.00),
            mk(2, 10_000, 10, 3.00),   // same odometer as above
            mk(10, 10_400, 10, 3.00),
        ]
        let showdown = VehicleShowdown(
            leftName: "Dupes", leftEntries: dupes,
            rightName: "Normal", rightEntries: thirsty(price: 3.00)
        )
        // A finite MPG (or none) — never an infinite/NaN one dressed as a win.
        if let mpg = showdown.row("mpg")?.left {
            #expect(!mpg.contains("inf") && !mpg.lowercased().contains("nan"))
        }
        #expect(showdown.leftWins + showdown.rightWins <= 3)
    }

    @Test func winCountsNeverExceedTheThreeContestedRows() {
        // Structural invariant: only mpg/cpm/ppg can be won, so the two win
        // counts together can never exceed three, on any input.
        let showdown = VehicleShowdown(
            leftName: "A", leftEntries: efficient(price: 3.60),
            rightName: "B", rightEntries: thirsty(price: 2.00)
        )
        #expect(showdown.leftWins <= 3)
        #expect(showdown.rightWins <= 3)
        #expect(showdown.leftWins + showdown.rightWins <= 3)
    }
}
