import Foundation
import SwiftUI
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

// MARK: - Contrast (WCAG 2.2 AA)

/// The contrast audit, as an executable guarantee rather than a note in a doc.
///
/// `AccessiblePalette` stores colors as components precisely so these ratios can
/// be recomputed on every CI run. A future palette tweak that drops a color
/// below the threshold fails here instead of shipping.
struct ContrastTests {
    private let schemes: [ColorScheme] = [.light, .dark]

    /// WCAG 2.2 AA for body text. The palette targets a higher internal margin;
    /// this asserts the standard itself, which is what actually matters.
    private let requirement = 4.5

    @Test(arguments: AccentHue.allCases)
    func accentColorsAreReadableOnEverySurfaceTheyLandOn(hue: AccentHue) {
        for scheme in schemes {
            let foreground = AccessiblePalette.components(hue, in: scheme)
            let surfaces: [(String, RGBComponents)] = [
                ("card", AccessiblePalette.cardBackground(in: scheme)),
                ("grouped", AccessiblePalette.groupedBackground(in: scheme)),
                // The capsule case: the hue's own 15% wash sits behind the hue
                // as text, which is the tightest pairing in the app.
                ("tint wash", AccessiblePalette.tintedBackground(hue, in: scheme))
            ]
            for (surface, background) in surfaces {
                let ratio = AccessiblePalette.contrastRatio(foreground, background)
                #expect(
                    ratio >= requirement,
                    "\(hue.rawValue) on \(surface) in \(scheme) mode is \(ratio):1, below \(requirement):1"
                )
            }
        }
    }

    @Test func everyMetricMapsToAHueAndASpokenName() {
        // The hue mapping is what carries "blue means fuel economy" across
        // screens; the name is what VoiceOver announces for a chart that isn't
        // given a specific title.
        let metrics: [Metric] = [.economy, .price, .spending, .distance]
        let hues = metrics.map(\.hue)
        #expect(Set(hues).count == metrics.count, "two metrics share a hue — they'd be indistinguishable")
        #expect(hues == [.blue, .orange, .purple, .teal])

        let names = metrics.map(\.accessibilityName)
        #expect(Set(names).count == metrics.count)
        #expect(names.allSatisfy { !$0.isEmpty })
    }

    @Test func metricColorsResolveThroughTheAccessiblePalette() {
        // Guards the indirection itself: if a metric ever went back to a stock
        // `Color`, this would stop matching.
        for scheme in schemes {
            #expect(Metric.price.color(in: scheme) == AccessiblePalette.color(.orange, in: scheme))
            #expect(Metric.economy.color(in: scheme) == AccessiblePalette.color(.blue, in: scheme))
        }
    }

    @Test func theInternalMarginSitsAboveTheStandard() {
        #expect(AccessiblePalette.minimumTextContrast >= requirement)
    }

    @Test func contrastMathMatchesTheWCAGReferencePoints() {
        let black = RGBComponents(red: 0, green: 0, blue: 0)
        let white = RGBComponents(red: 1, green: 1, blue: 1)

        // The two anchors the formula is defined by.
        #expect(abs(AccessiblePalette.contrastRatio(black, white) - 21) < 0.01)
        #expect(abs(AccessiblePalette.contrastRatio(white, white) - 1) < 0.0001)
        // Ratio is symmetric — a foreground/background mix-up can't hide a fail.
        #expect(AccessiblePalette.contrastRatio(black, white)
                == AccessiblePalette.contrastRatio(white, black))
    }

    /// Documents *why* the palette exists: Apple's stock light-mode values fail
    /// the same check this suite now enforces. If a future refactor is tempted
    /// to "simplify" back to `.orange`, this is the reason not to.
    @Test func appleStockLightModeColorsWouldFailTheSameCheck() {
        let white = RGBComponents(red: 1, green: 1, blue: 1)
        let stockOrange = RGBComponents(red: 1.0, green: 0.5843, blue: 0.0)      // #FF9500
        let stockTeal = RGBComponents(red: 0.1882, green: 0.6902, blue: 0.7804)  // #30B0C7

        #expect(AccessiblePalette.contrastRatio(stockOrange, white) < requirement)
        #expect(AccessiblePalette.contrastRatio(stockTeal, white) < requirement)
    }

    @Test func aTintWashIsLighterThanItsInkSoTheTwoStayDistinguishable() {
        for scheme in schemes {
            for hue in AccentHue.allCases {
                let ink = AccessiblePalette.relativeLuminance(AccessiblePalette.components(hue, in: scheme))
                let wash = AccessiblePalette.relativeLuminance(AccessiblePalette.tintedBackground(hue, in: scheme))
                #expect(ink != wash, "\(hue.rawValue) in \(scheme) has no separation from its wash")
            }
        }
    }
}

// MARK: - Chart audio graphs

/// The data half of VoiceOver's audio graph. Deliberately testable without a
/// simulator: `ChartAudioGraphData` holds no `AXChartDescriptor`, so the parts
/// that can actually be wrong — which points survive, what the axis bounds come
/// out as, whether garbage is rejected — are checked here.
struct ChartAudioGraphTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: Double(offset) * 86_400)
    }

    private func series(_ values: [Double]) -> [DateValuePoint] {
        values.enumerated().map { DateValuePoint(id: UUID(), date: day($0.offset), value: $0.element) }
    }

    private func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    // MARK: Happy path

    @Test func buildsAxisBoundsFromTheDataAndOnePointPerSample() throws {
        let graph = try #require(ChartAudioGraphData.series(
            title: "Fuel Economy", yAxisLabel: "MPG",
            points: series([30, 24, 36]), describeValue: whole
        ))

        #expect(graph.title == "Fuel Economy")
        #expect(graph.points.count == 3)
        #expect(graph.yRange.lowerBound == 24)
        #expect(graph.yRange.upperBound == 36)
        #expect(graph.xRange.lowerBound == day(0).timeIntervalSinceReferenceDate)
        #expect(graph.xRange.upperBound == day(2).timeIntervalSinceReferenceDate)
    }

    @Test func eachPointIsSpokenWithItsDateAndFormattedValue() throws {
        let graph = try #require(ChartAudioGraphData.series(
            title: "Gas Price", yAxisLabel: "per gallon",
            points: series([3]), describeValue: { "$\(self.whole($0))" }
        ))
        let label = try #require(graph.points.first?.label)
        #expect(label.contains("$3"))
        #expect(label.contains("2001"))  // the reference date's year
    }

    @Test func monthlyBuilderReadsTheRequestedKeyPath() throws {
        let totals = (0..<3).map { index in
            MonthlyTotal(
                id: day(index * 30), month: day(index * 30),
                totalSpent: Double(index) * 10, totalGallons: 1, miles: Double(index) * 100, fillUpCount: 1
            )
        }
        let spending = try #require(ChartAudioGraphData.monthly(
            title: "Monthly Spending", yAxisLabel: "spent",
            totals: totals, value: \.totalSpent, describeValue: whole
        ))
        #expect(spending.yRange.upperBound == 20)

        let distance = try #require(ChartAudioGraphData.monthly(
            title: "Monthly Distance", yAxisLabel: "miles",
            totals: totals, value: \.miles, describeValue: whole
        ))
        #expect(distance.yRange.upperBound == 200)
    }

    // MARK: Hostile input

    @Test func emptySeriesProducesNoAudioGraphRatherThanAnEmptyOne() {
        #expect(ChartAudioGraphData.series(
            title: "Empty", yAxisLabel: "MPG", points: [], describeValue: whole
        ) == nil)
        #expect(ChartAudioGraphData.monthly(
            title: "Empty", yAxisLabel: "spent", totals: [], value: \.totalSpent, describeValue: whole
        ) == nil)
    }

    @Test func aSeriesOfNothingButNonFiniteValuesIsRejected() {
        let junk = series([.nan, .infinity, -.infinity])
        #expect(ChartAudioGraphData.series(
            title: "Junk", yAxisLabel: "MPG", points: junk, describeValue: whole
        ) == nil)
    }

    @Test func nonFiniteValuesAreDroppedRatherThanPlacedOnTheAxis() throws {
        // A NaN MPG is missing data. Keeping it would put a tone somewhere the
        // user's finger says there is no reading, and an infinite bound would
        // make the whole axis meaningless.
        let graph = try #require(ChartAudioGraphData.series(
            title: "Mixed", yAxisLabel: "MPG",
            points: series([30, .nan, 20, .infinity, 25]), describeValue: whole
        ))
        #expect(graph.points.count == 3)
        #expect(graph.yRange.lowerBound == 20)
        #expect(graph.yRange.upperBound == 30)
        #expect(graph.yRange.lowerBound.isFinite && graph.yRange.upperBound.isFinite)
    }

    @Test func aFlatSeriesStillGetsAPlayableAxis() throws {
        // Every fill-up at the same price is real data, not an error — but a
        // zero-width range gives the audio graph nowhere to put a tone.
        let graph = try #require(ChartAudioGraphData.series(
            title: "Flat", yAxisLabel: "MPG",
            points: series([32, 32, 32]), describeValue: whole
        ))
        #expect(graph.yRange.lowerBound < graph.yRange.upperBound)
        #expect(graph.points.count == 3)
    }

    @Test func aFlatSeriesAtZeroIsPaddedByAFixedAmountNotByAFractionOfZero() throws {
        // Percentage padding of 0 is still 0, which would leave the range
        // degenerate — the one case the proportional rule can't handle.
        let graph = try #require(ChartAudioGraphData.series(
            title: "Zeroes", yAxisLabel: "MPG",
            points: series([0, 0]), describeValue: whole
        ))
        #expect(graph.yRange.lowerBound == -1)
        #expect(graph.yRange.upperBound == 1)
    }

    @Test func aSinglePointIsEnoughToSonify() throws {
        let graph = try #require(ChartAudioGraphData.series(
            title: "One", yAxisLabel: "MPG",
            points: series([42]), describeValue: whole
        ))
        #expect(graph.points.count == 1)
        #expect(graph.xRange.lowerBound < graph.xRange.upperBound)
        #expect(graph.yRange.lowerBound < graph.yRange.upperBound)
    }

    @Test func negativeValuesKeepTheirOrderingRatherThanBeingClamped() throws {
        // Not physically meaningful for MPG, but the builder must not invert or
        // swallow them — a bad range is a crash risk downstream.
        let graph = try #require(ChartAudioGraphData.series(
            title: "Negative", yAxisLabel: "MPG",
            points: series([-10, -30, -20]), describeValue: whole
        ))
        #expect(graph.yRange.lowerBound == -30)
        #expect(graph.yRange.upperBound == -10)
    }
}
