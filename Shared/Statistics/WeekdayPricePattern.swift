import Foundation

/// Average price per gallon for one day of the week.
struct WeekdayPrice: Identifiable {
    /// Calendar weekday: 1 = Sunday ... 7 = Saturday.
    let weekday: Int
    /// Localized short symbol for the chart axis, e.g. "Mon".
    let symbol: String
    /// Simple mean of the price per gallon paid on this weekday. A plain
    /// average (not gallon-weighted) answers "what price do I tend to catch
    /// on this day," which is the question the pattern is about.
    let averagePrice: Double
    let fillUpCount: Int

    var id: Int { weekday }
}

extension FuelStatistics {
    /// Average price paid per gallon grouped by day of the week, ordered from
    /// the locale's first weekday. Only weekdays with at least one fill appear.
    var weekdayPrices: [WeekdayPrice] {
        let calendar = Calendar.current
        let symbols = DateFormatter().shortWeekdaySymbols ?? Self.fallbackShortSymbols   // index 0 = Sunday

        let grouped = Dictionary(grouping: entries) {
            calendar.component(.weekday, from: $0.date)
        }

        // 1...7 rotated so the week reads from the locale's first day.
        let firstWeekday = calendar.firstWeekday
        let order = (0..<7).map { ((firstWeekday - 1 + $0) % 7) + 1 }

        return order.compactMap { weekday in
            guard let fills = grouped[weekday], !fills.isEmpty else { return nil }
            let average = fills.reduce(0) { $0 + $1.pricePerGallon } / Double(fills.count)
            return WeekdayPrice(
                weekday: weekday,
                symbol: symbols[weekday - 1],
                averagePrice: average,
                fillUpCount: fills.count
            )
        }
    }

    var cheapestWeekday: WeekdayPrice? {
        weekdayPrices.min { $0.averagePrice < $1.averagePrice }
    }

    var priciestWeekday: WeekdayPrice? {
        weekdayPrices.max { $0.averagePrice < $1.averagePrice }
    }

    /// Headline comparing the cheapest and priciest weekdays — shown only
    /// when the pattern is worth trusting: at least two distinct weekdays,
    /// a handful of fills overall, and at least a one-cent spread.
    func weekdayPriceInsight(units: UnitPreferences = .us) -> String? {
        let prices = weekdayPrices
        guard prices.count >= 2,
              fillUpCount >= 4,
              let cheapest = cheapestWeekday,
              let priciest = priciestWeekday,
              cheapest.weekday != priciest.weekday else { return nil }

        let delta = priciest.averagePrice - cheapest.averagePrice
        guard delta * 100 >= 1 else { return nil }

        let fullSymbols = DateFormatter().weekdaySymbols ?? Self.fallbackFullSymbols   // index 0 = Sunday
        let cheapName = fullSymbols[cheapest.weekday - 1]
        let priceyName = fullSymbols[priciest.weekday - 1]
        let perUnitDelta = Format.plainCurrency(delta / units.volume.fromGallons(1))
        return "You pay about \(perUnitDelta)/\(units.volume.abbreviation) less on \(cheapName)s than \(priceyName)s."
    }

    // Defensive fallbacks; DateFormatter always supplies these in practice.
    private static let fallbackShortSymbols =
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let fallbackFullSymbols =
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
}
