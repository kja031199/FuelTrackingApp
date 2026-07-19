import Foundation
import Testing
@testable import FuelTracker

struct OdometerScanParserTests {
    // MARK: - Picking the right number off a cluttered dashboard

    @Test func picksTheHistoryConsistentValueAmongDistractors() throws {
        // A real cluster: clock, temperature, trip meter, speed — and the
        // odometer. History says ~42,150 + ~320/fill.
        let lines = ["12:45", "72°F", "TRIP A 234.5", "0 MPH", "42460"]
        let candidate = try #require(OdometerScanParser.parse(
            lines, previousOdometer: 42_150, typicalMilesPerFill: 320
        ))
        #expect(candidate.value == 42_460)
        #expect(candidate.validation == .plausible(milesSinceLast: 310))
    }

    @Test func clockReadoutsNeverBecomeCandidates() {
        // "12:45" must not be read as 1245 — even when it's the only number.
        let candidate = OdometerScanParser.parse(
            ["12:45"], previousOdometer: 1_000, typicalMilesPerFill: 300
        )
        #expect(candidate == nil)
    }

    @Test func temperatureAndPercentageReadoutsAreIgnored() {
        let candidate = OdometerScanParser.parse(
            ["72°F", "80%"], previousOdometer: nil, typicalMilesPerFill: nil
        )
        #expect(candidate == nil)
    }

    @Test func commaGroupedOdometersParse() throws {
        let candidate = try #require(OdometerScanParser.parse(
            ["42,460"], previousOdometer: 42_150, typicalMilesPerFill: 320
        ))
        #expect(candidate.value == 42_460)
    }

    @Test func integerOdometerBeatsDecimalTripMeterWhenBothFit() throws {
        // A trip meter that happens to land in the feasible window must
        // lose to the integer main odometer.
        let lines = ["TRIP 42250.5", "42460"]
        let candidate = try #require(OdometerScanParser.parse(
            lines, previousOdometer: 42_150, typicalMilesPerFill: 320
        ))
        #expect(candidate.value == 42_460)
    }

    @Test func typicalDistanceGuidesTheChoiceBetweenFeasibleValues() throws {
        // Two feasible integers: expected ≈ 42,470 picks the closer one.
        let lines = ["42460", "43900"]
        let candidate = try #require(OdometerScanParser.parse(
            lines, previousOdometer: 42_150, typicalMilesPerFill: 320
        ))
        #expect(candidate.value == 42_460)
    }

    // MARK: - History validation verdicts

    @Test func readingBelowLastIsFlaggedNotHidden() throws {
        let candidate = try #require(OdometerScanParser.parse(
            ["41000"], previousOdometer: 42_150, typicalMilesPerFill: 320
        ))
        #expect(candidate.value == 41_000)
        #expect(candidate.validation == .belowLastReading(last: 42_150))
        #expect(candidate.validation.isWarning)
    }

    @Test func readingImplausiblyFarAheadIsFlagged() throws {
        // 424,600 — a misread with an extra digit — is ~382k miles ahead.
        let candidate = try #require(OdometerScanParser.parse(
            ["424600"], previousOdometer: 42_150, typicalMilesPerFill: 320
        ))
        #expect(candidate.validation == .implausiblyFar(last: 42_150, miles: 382_450))
        #expect(candidate.validation.isWarning)
    }

    @Test func noHistoryPicksTheLargestPlausibleNumber() throws {
        let candidate = try #require(OdometerScanParser.parse(
            ["234.5", "42460"], previousOdometer: nil, typicalMilesPerFill: nil
        ))
        #expect(candidate.value == 42_460)
        #expect(candidate.validation == .noHistory)
        #expect(!candidate.validation.isWarning)
    }

    @Test func sameReadingAsLastFillIsPlausibleZeroMiles() throws {
        // Filling twice without driving (topping off) is legal.
        let candidate = try #require(OdometerScanParser.parse(
            ["42150"], previousOdometer: 42_150, typicalMilesPerFill: 320
        ))
        #expect(candidate.validation == .plausible(milesSinceLast: 0))
    }

    // MARK: - Hostile input

    @Test func excludedPumpValuesAreNeverChosen() {
        // When run on a pump photo's OCR lines, the gallons/price/total
        // already claimed by the pump parser must not become the odometer.
        let candidate = OdometerScanParser.parse(
            ["30.48", "8.712", "3.499"],
            previousOdometer: nil,
            typicalMilesPerFill: nil,
            excluding: [30.48, 8.712, 3.499]
        )
        #expect(candidate == nil)
    }

    @Test func sevenDigitAndTinyNumbersAreOutOfRange() {
        #expect(OdometerScanParser.parse(
            ["1000000"], previousOdometer: nil, typicalMilesPerFill: nil
        ) == nil)
        #expect(OdometerScanParser.parse(
            ["5"], previousOdometer: nil, typicalMilesPerFill: nil
        ) == nil)
    }

    @Test func emptyAndGarbageInputProduceNil() {
        #expect(OdometerScanParser.parse([], previousOdometer: 1_000, typicalMilesPerFill: 300) == nil)
        #expect(OdometerScanParser.parse(
            ["ODO", "MILES", "P R N D"], previousOdometer: 1_000, typicalMilesPerFill: 300
        ) == nil)
    }

    @Test func missingTypicalDistanceFallsBackToADefaultWindow() throws {
        // One prior fill means no average yet; a ~300-mile jump must still
        // validate under the default assumption.
        let candidate = try #require(OdometerScanParser.parse(
            ["42460"], previousOdometer: 42_150, typicalMilesPerFill: nil
        ))
        #expect(candidate.validation == .plausible(milesSinceLast: 310))
    }

    // MARK: - Frame-to-frame preference for live scanning

    @Test func preferredKeepsPlausibleOverLaterWarnings() {
        let plausible = OdometerCandidate(value: 42_460, validation: .plausible(milesSinceLast: 310))
        let warning = OdometerCandidate(value: 41_000, validation: .belowLastReading(last: 42_150))
        #expect(OdometerScanParser.preferred(current: plausible, new: warning) == plausible)
    }

    @Test func preferredUpgradesFromWarningToPlausible() {
        let warning = OdometerCandidate(value: 41_000, validation: .belowLastReading(last: 42_150))
        let plausible = OdometerCandidate(value: 42_460, validation: .plausible(milesSinceLast: 310))
        #expect(OdometerScanParser.preferred(current: warning, new: plausible) == plausible)
    }

    @Test func preferredRefreshesEqualConfidenceAndToleratesNil() {
        let first = OdometerCandidate(value: 42_460, validation: .plausible(milesSinceLast: 310))
        let second = OdometerCandidate(value: 42_461, validation: .plausible(milesSinceLast: 311))
        #expect(OdometerScanParser.preferred(current: first, new: second) == second)
        #expect(OdometerScanParser.preferred(current: first, new: nil) == first)
        #expect(OdometerScanParser.preferred(current: nil, new: first) == first)
        #expect(OdometerScanParser.preferred(current: nil, new: nil) == nil)
    }
}
