import Foundation

/// Values read off a gas pump display.
struct PumpReading: Equatable {
    var gallons: Double?
    var pricePerGallon: Double?
    var totalCost: Double?

    /// Gallons and price are what the fill-up form needs; total is derived.
    var isComplete: Bool {
        gallons != nil && pricePerGallon != nil
    }
}

/// Turns raw OCR text lines from a pump display into a PumpReading.
///
/// Strategy, in order of trust:
/// 1. Labels — lines like "GALLONS 8.712" or "PRICE/GAL" followed by a value.
/// 2. Arithmetic consistency — a (total, gallons, price) triple where
///    gallons × price ≈ total identifies all three even with no labels.
/// 3. Derivation — any two of the three yield the missing one.
/// 4. Decimal heuristics — pumps show price and gallons with three decimals;
///    used only when a lone candidate is unambiguous.
enum PumpScanParser {
    private static let gallonsRange = 0.3...60.0
    private static let priceRange = 1.5...9.999
    private static let totalRange = 1.0...500.0

    private enum Label {
        case gallons, price, total
    }

    static func parse(_ rawLines: [String]) -> PumpReading {
        var reading = PumpReading()
        var numbers: [(value: Double, fractionDigits: Int)] = []
        var pendingLabel: Label?

        for rawLine in rawLines {
            let line = normalize(rawLine)
            let lineNumbers = extractNumbers(from: line)
            numbers.append(contentsOf: lineNumbers)

            if let label = label(in: line) {
                if let first = lineNumbers.first {
                    assign(first.value, label: label, into: &reading)
                    pendingLabel = nil
                } else {
                    // Pumps often put the label and the value on separate
                    // display lines; remember the label for the next number.
                    pendingLabel = label
                }
            } else if let pending = pendingLabel, let first = lineNumbers.first {
                assign(first.value, label: pending, into: &reading)
                pendingLabel = nil
            } else if !lineNumbers.isEmpty {
                pendingLabel = nil
            }
        }

        applyConsistentTriple(numbers.map(\.value), into: &reading)
        deriveMissingValue(into: &reading)
        applyDecimalHeuristics(numbers, into: &reading)
        deriveMissingValue(into: &reading)

        return reading
    }

    /// Field-wise overlay so a live scan keeps the best values seen so far
    /// instead of flickering as OCR results come and go.
    static func merge(current: PumpReading, new: PumpReading) -> PumpReading {
        PumpReading(
            gallons: new.gallons ?? current.gallons,
            pricePerGallon: new.pricePerGallon ?? current.pricePerGallon,
            totalCost: new.totalCost ?? current.totalCost
        )
    }

    // MARK: - Steps

    private static func normalize(_ line: String) -> String {
        // "3.49 9/10" — the fraction-of-a-cent notation — means 3.499.
        line.uppercased()
            .replacingOccurrences(of: " 9/10", with: "9")
            .replacingOccurrences(of: "9/10", with: "9")
    }

    private static func extractNumbers(from line: String) -> [(value: Double, fractionDigits: Int)] {
        var results: [(Double, Int)] = []
        var remainder = Substring(line)
        while let match = remainder.firstMatch(of: #/([0-9]+)\.([0-9]{1,3})/#) {
            if let value = Double("\(match.1).\(match.2)") {
                results.append((value, match.2.count))
            }
            remainder = remainder[match.range.upperBound...]
        }
        return results
    }

    private static func label(in line: String) -> Label? {
        if line.contains("/GAL") || line.contains("PER GAL") || line.contains("PRICE") {
            return .price
        }
        if line.contains("GALLON") || line.contains("GAL") {
            return .gallons
        }
        if line.contains("TOTAL") || line.contains("SALE") || line.contains("AMOUNT") {
            return .total
        }
        return nil
    }

    private static func assign(_ value: Double, label: Label, into reading: inout PumpReading) {
        switch label {
        case .gallons where gallonsRange.contains(value):
            reading.gallons = reading.gallons ?? value
        case .price where priceRange.contains(value):
            reading.pricePerGallon = reading.pricePerGallon ?? value
        case .total where totalRange.contains(value):
            reading.totalCost = reading.totalCost ?? value
        default:
            break
        }
    }

    private static func applyConsistentTriple(_ values: [Double], into reading: inout PumpReading) {
        guard !reading.isComplete || reading.totalCost == nil else { return }

        var best: (gallons: Double, price: Double, total: Double, error: Double)?
        for (i, total) in values.enumerated() where totalRange.contains(total) {
            for (j, gallons) in values.enumerated() where j != i && gallonsRange.contains(gallons) {
                for (k, price) in values.enumerated() where k != i && k != j && priceRange.contains(price) {
                    let error = abs(gallons * price - total)
                    let tolerance = max(0.05, total * 0.01)
                    if error <= tolerance, error < (best?.error ?? .infinity) {
                        best = (gallons, price, total, error)
                    }
                }
            }
        }

        if let best {
            reading.gallons = reading.gallons ?? best.gallons
            reading.pricePerGallon = reading.pricePerGallon ?? best.price
            reading.totalCost = reading.totalCost ?? best.total
        }
    }

    private static func deriveMissingValue(into reading: inout PumpReading) {
        if reading.gallons == nil, let total = reading.totalCost, let price = reading.pricePerGallon, price > 0 {
            let gallons = round3(total / price)
            if gallonsRange.contains(gallons) {
                reading.gallons = gallons
            }
        }
        if reading.pricePerGallon == nil, let total = reading.totalCost, let gallons = reading.gallons, gallons > 0 {
            let price = round3(total / gallons)
            if priceRange.contains(price) {
                reading.pricePerGallon = price
            }
        }
        if reading.totalCost == nil, let gallons = reading.gallons, let price = reading.pricePerGallon {
            reading.totalCost = (gallons * price * 100).rounded() / 100
        }
    }

    private static func applyDecimalHeuristics(
        _ numbers: [(value: Double, fractionDigits: Int)],
        into reading: inout PumpReading
    ) {
        // Pumps display price and gallons with three decimals. Only trust
        // this when exactly one candidate fits, otherwise it's a guess.
        if reading.pricePerGallon == nil {
            let candidates = numbers.filter { $0.fractionDigits == 3 && priceRange.contains($0.value) }
            if candidates.count == 1 {
                reading.pricePerGallon = candidates[0].value
            }
        }
        if reading.gallons == nil {
            let candidates = numbers.filter {
                $0.fractionDigits == 3 && gallonsRange.contains($0.value) && $0.value != reading.pricePerGallon
            }
            if candidates.count == 1 {
                reading.gallons = candidates[0].value
            }
        }
    }

    private static func round3(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }
}
