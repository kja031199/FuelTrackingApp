import Foundation

/// A candidate odometer reading pulled from OCR text, with a verdict on
/// whether it fits the vehicle's history.
struct OdometerCandidate: Equatable {
    let value: Double
    let validation: OdometerValidation
}

enum OdometerValidation: Equatable {
    /// Fits between the last reading and a plausible distance beyond it.
    case plausible(milesSinceLast: Double)
    /// Nothing recorded yet to check against.
    case noHistory
    /// Odometers never run backwards — almost certainly a misread.
    case belowLastReading(last: Double)
    /// Far beyond a plausible tank-to-tank distance — possibly a misread
    /// (or a long-forgotten logging gap). Worth a human look either way.
    case implausiblyFar(last: Double, miles: Double)

    var isWarning: Bool {
        switch self {
        case .plausible, .noHistory: false
        case .belowLastReading, .implausiblyFar: true
        }
    }
}

/// Finds the odometer reading in OCR text from a dashboard photo, ignoring
/// the other numbers instrument clusters love to show — the clock, the
/// temperature, the trip meter, the speedometer.
enum OdometerScanParser {
    private static let plausibleRange = 10.0...999_999.0
    private static let defaultMilesPerFill = 350.0

    static func parse(
        _ rawLines: [String],
        previousOdometer: Double?,
        typicalMilesPerFill: Double?,
        excluding: [Double] = []
    ) -> OdometerCandidate? {
        var candidates: [(value: Double, isInteger: Bool)] = []
        for line in rawLines {
            candidates.append(contentsOf: extractNumbers(from: normalize(line)))
        }
        candidates = candidates.filter { candidate in
            plausibleRange.contains(candidate.value)
                && !excluding.contains { abs($0 - candidate.value) < 0.001 }
        }
        guard !candidates.isEmpty else { return nil }

        guard let previous = previousOdometer else {
            // Without history the only heuristic left: the odometer is
            // usually the largest number on the cluster.
            let best = candidates.max { $0.value < $1.value }!
            return OdometerCandidate(value: best.value, validation: .noHistory)
        }

        let typical = typicalMilesPerFill ?? defaultMilesPerFill
        let expected = previous + typical
        let upperBound = previous + max(3_000, typical * 8)

        let feasible = candidates.filter { $0.value >= previous && $0.value <= upperBound }
        if !feasible.isEmpty {
            // Main odometers display whole miles; one-decimal values are
            // usually the trip meter. Prefer integers when both fit.
            let pool = feasible.contains(where: \.isInteger) ? feasible.filter(\.isInteger) : feasible
            let best = pool.min { abs($0.value - expected) < abs($1.value - expected) }!
            return OdometerCandidate(
                value: best.value,
                validation: .plausible(milesSinceLast: best.value - previous)
            )
        }

        // Nothing fits: surface the most informative failure. Anything
        // ahead of the last reading is "too far"; otherwise it ran backwards.
        if let ahead = candidates.filter({ $0.value > previous }).min(by: { $0.value < $1.value }) {
            return OdometerCandidate(
                value: ahead.value,
                validation: .implausiblyFar(last: previous, miles: ahead.value - previous)
            )
        }
        let best = candidates.max { $0.value < $1.value }!
        return OdometerCandidate(value: best.value, validation: .belowLastReading(last: previous))
    }

    /// Frame-to-frame merge for live scanning: keep the highest-confidence
    /// candidate seen, letting equal-confidence readings refresh.
    static func preferred(current: OdometerCandidate?, new: OdometerCandidate?) -> OdometerCandidate? {
        guard let new else { return current }
        guard let current else { return new }
        return rank(new.validation) >= rank(current.validation) ? new : current
    }

    private static func rank(_ validation: OdometerValidation) -> Int {
        switch validation {
        case .plausible: 3
        case .noHistory: 2
        case .implausiblyFar: 1
        case .belowLastReading: 0
        }
    }

    private static func normalize(_ line: String) -> String {
        var text = line.uppercased()
        // Clocks: "12:45" must never become 1245.
        text = text.replacingOccurrences(
            of: #"\d{1,2}:\d{2}"#, with: " ", options: .regularExpression
        )
        // Temperatures and percentages: "72°" / "72F" readouts, battery "80%".
        text = text.replacingOccurrences(
            of: #"[0-9]+(\.[0-9]+)?\s?(°F?C?|%)"#, with: " ", options: .regularExpression
        )
        // Digit-grouping commas: "42,150" → "42150".
        text = text.replacingOccurrences(
            of: #"(?<=\d),(?=\d{3}\b)"#, with: "", options: .regularExpression
        )
        return text
    }

    private static func extractNumbers(from line: String) -> [(value: Double, isInteger: Bool)] {
        var results: [(Double, Bool)] = []
        var remainder = Substring(line)
        while let match = remainder.firstMatch(of: #/([0-9]+)(?:\.([0-9]))?/#) {
            let integerPart = match.1
            if let fraction = match.2 {
                if let value = Double("\(integerPart).\(fraction)") {
                    results.append((value, false))
                }
            } else if let value = Double(integerPart) {
                results.append((value, true))
            }
            remainder = remainder[match.range.upperBound...]
        }
        return results
    }
}
