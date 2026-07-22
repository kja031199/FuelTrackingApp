import Foundation
import Testing
@testable import FuelTracker

/// Tests for the pure text the UI hands to VoiceOver. The label composition is
/// where the real logic lives; the view modifiers that apply it are exercised
/// by the render tests.
struct AccessibilityTests {
    // MARK: - KPI cards

    @Test func kpiLabelCombinesTitleValueAndDetailIntoOnePhrase() {
        let full = KPI(title: "Avg MPG", value: "32.1", detail: "Best: 35.0", icon: "leaf.fill", metric: .economy)
        #expect(full.accessibilityLabel == "Avg MPG, 32.1, Best: 35.0")

        let noDetail = KPI(title: "Cost per Mile", value: "$0.12", icon: "road.lanes", metric: .spending)
        #expect(noDetail.accessibilityLabel == "Cost per Mile, $0.12")
    }

    @Test func kpiLabelSpeaksAPlaceholderWhenThereIsNoValue() {
        let empty = KPI(title: "Avg MPG", value: nil, icon: "leaf.fill", metric: .economy)
        #expect(empty.accessibilityLabel == "Avg MPG, no data yet")
    }

    // MARK: - Showdown rows (winner stated in words, not by color)

    @Test func showdownRowNamesTheWinner() {
        let left = ShowdownRow(id: "mpg", title: "Avg MPG", icon: "leaf.fill", metric: .economy,
                               left: "40.0", right: "25.0", winner: .left)
        #expect(left.accessibilityLabel(leftName: "Prius", rightName: "Truck")
                == "Avg MPG. Prius: 40.0. Truck: 25.0. Prius wins.")

        let right = ShowdownRow(id: "cpm", title: "Cost per Mile", icon: "road.lanes", metric: .spending,
                                left: "$0.12", right: "$0.08", winner: .right)
        #expect(right.accessibilityLabel(leftName: "A", rightName: "B")
                == "Cost per Mile. A: $0.12. B: $0.08. B wins.")
    }

    @Test func showdownRowSpeaksTiesAndInformationalRows() {
        let tie = ShowdownRow(id: "ppg", title: "Avg Price/Gal", icon: "fuelpump.fill", metric: .price,
                              left: "$3.000", right: "$3.000", winner: .tie)
        #expect(tie.accessibilityLabel(leftName: "A", rightName: "B")
                == "Avg Price/Gal. A: $3.000. B: $3.000. Tie.")

        // Informational rows and one-sided data carry no winner clause.
        let info = ShowdownRow(id: "miles", title: "Miles Tracked", icon: "point", metric: .distance,
                               left: "800", right: nil, winner: .notContested)
        #expect(info.accessibilityLabel(leftName: "A", rightName: "B")
                == "Miles Tracked. A: 800. B: no data.")
    }

    // MARK: - Chart summaries (spoken overview of a series)

    private func series(_ values: [Double]) -> [DateValuePoint] {
        values.enumerated().map { index, value in
            DateValuePoint(id: UUID(), date: Date(timeIntervalSince1970: Double(index) * 86_400), value: value)
        }
    }

    private let whole: (Double) -> String = { String(format: "%.0f", $0) }

    @Test func chartSummaryIsNilForEmptyData() {
        #expect(ChartAccessibility.summary([], unit: "MPG", format: whole) == nil)
    }

    @Test func chartSummaryDescribesASinglePoint() {
        #expect(ChartAccessibility.summary(series([24]), unit: "MPG", format: whole)
                == "One point, 24 MPG.")
    }

    @Test func chartSummaryReportsRangeAverageLatestAndUpwardTrend() {
        #expect(ChartAccessibility.summary(series([20, 25, 30]), unit: "MPG", format: whole)
                == "3 points, from 20 to 30 MPG, averaging 25, latest 30, trending up.")
    }

    @Test func chartSummaryDetectsDownwardAndFlatTrends() {
        #expect(ChartAccessibility.summary(series([30, 25, 20]), unit: "MPG", format: whole)?
            .contains("trending down") == true)
        #expect(ChartAccessibility.summary(series([25, 24, 25]), unit: "MPG", format: whole)?
            .contains("roughly flat") == true)
    }
}
