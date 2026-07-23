import Foundation
import Testing
@testable import FuelTracker

// January 2025 weekday reference (Calendar weekday: 1=Sun ... 7=Sat):
//   Jan 5 Sun, Jan 6 Mon, Jan 7 Tue, Jan 8 Wed, Jan 9 Thu, Jan 10 Fri, Jan 11 Sat
// Tuesdays: 7, 14, 21, 28.  Fridays: 3, 10, 17, 24, 31.
private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
}

private func makeEntry(on date: Date, price: Double, gallons: Double = 10) -> FuelEntry {
    FuelEntry(date: date, odometer: 10_000, gallons: gallons, pricePerGallon: price)
}

struct WeekdayPricePatternTests {
    // MARK: - Grouping & averaging

    @Test func averagesPriceByWeekdayAsASimpleMeanNotGallonWeighted() throws {
        // Two Tuesday fills, very different gallons. A gallon-weighted mean
        // would be 3.32; the simple mean is 3.20 — the price you "tend to
        // catch," which is what the pattern is about.
        let statistics = FuelStatistics(entries: [
            makeEntry(on: day(2025, 1, 7), price: 3.00, gallons: 5),
            makeEntry(on: day(2025, 1, 14), price: 3.40, gallons: 20),
        ])
        let tuesday = try #require(statistics.weekdayPrices.first { $0.weekday == 3 })
        #expect(abs(tuesday.averagePrice - 3.20) < 0.0001)
        #expect(tuesday.fillUpCount == 2)
    }

    @Test func cheapestAndPriciestWeekdaysAreIdentified() throws {
        let statistics = FuelStatistics(entries: [
            makeEntry(on: day(2025, 1, 7), price: 3.20),   // Tue
            makeEntry(on: day(2025, 1, 14), price: 3.20),  // Tue
            makeEntry(on: day(2025, 1, 3), price: 3.31),   // Fri
            makeEntry(on: day(2025, 1, 10), price: 3.31),  // Fri
        ])
        #expect(statistics.cheapestWeekday?.weekday == 3)   // Tuesday
        #expect(statistics.priciestWeekday?.weekday == 6)   // Friday
    }

    @Test func weekdaysAreOrderedFromTheLocaleFirstWeekday() {
        // One fill on each of the seven weekdays (Jan 5–11 2025).
        let statistics = FuelStatistics(entries: (5...11).map {
            makeEntry(on: day(2025, 1, $0), price: 3.00)
        })
        let first = Calendar.current.firstWeekday
        let expected = (0..<7).map { ((first - 1 + $0) % 7) + 1 }
        #expect(statistics.weekdayPrices.map(\.weekday) == expected)
    }

    // MARK: - The insight headline

    @Test func insightNamesTheCheapestAndPriciestDaysWithTheSpread() throws {
        let statistics = FuelStatistics(entries: [
            makeEntry(on: day(2025, 1, 7), price: 3.20),   // Tue
            makeEntry(on: day(2025, 1, 14), price: 3.20),  // Tue
            makeEntry(on: day(2025, 1, 3), price: 3.31),   // Fri
            makeEntry(on: day(2025, 1, 10), price: 3.31),  // Fri
        ])
        let insight = try #require(statistics.weekdayPriceInsight())

        let names = DateFormatter().weekdaySymbols!     // 0=Sun ... 6=Sat
        let tuesday = names[2]
        let friday = names[5]
        #expect(insight.contains(tuesday))
        #expect(insight.contains(friday))
        #expect(insight.contains(Format.plainCurrency(0.11)))
        // The cheaper day is named first.
        #expect(insight.range(of: tuesday)!.lowerBound < insight.range(of: friday)!.lowerBound)
    }

    // MARK: - When the insight should stay silent

    @Test func insightIsNilWithoutEnoughFills() {
        // Two fills on two weekdays: a spread exists, but too little data.
        let statistics = FuelStatistics(entries: [
            makeEntry(on: day(2025, 1, 7), price: 3.20),   // Tue
            makeEntry(on: day(2025, 1, 3), price: 3.31),   // Fri
        ])
        #expect(statistics.weekdayPriceInsight() == nil)
    }

    @Test func insightIsNilWithASingleWeekday() {
        // Four fills, all Tuesdays — nothing to compare against.
        let statistics = FuelStatistics(entries: [
            makeEntry(on: day(2025, 1, 7), price: 3.10),
            makeEntry(on: day(2025, 1, 14), price: 3.20),
            makeEntry(on: day(2025, 1, 21), price: 3.30),
            makeEntry(on: day(2025, 1, 28), price: 3.40),
        ])
        #expect(statistics.weekdayPrices.count == 1)
        #expect(statistics.weekdayPriceInsight() == nil)
    }

    @Test func insightIsNilWhenTheSpreadIsUnderOneCent() {
        // Half-a-cent difference is noise, not a pattern.
        let statistics = FuelStatistics(entries: [
            makeEntry(on: day(2025, 1, 7), price: 3.200),   // Tue
            makeEntry(on: day(2025, 1, 14), price: 3.200),  // Tue
            makeEntry(on: day(2025, 1, 3), price: 3.205),   // Fri
            makeEntry(on: day(2025, 1, 10), price: 3.205),  // Fri
        ])
        #expect(statistics.weekdayPriceInsight() == nil)
    }

    // MARK: - Degenerate & hostile

    @Test func emptyHistoryHasNoWeekdayData() {
        let statistics = FuelStatistics(entries: [])
        #expect(statistics.weekdayPrices.isEmpty)
        #expect(statistics.cheapestWeekday == nil)
        #expect(statistics.priciestWeekday == nil)
        #expect(statistics.weekdayPriceInsight() == nil)
    }

    @Test func aSingleFillAveragesToItsOwnPrice() throws {
        let statistics = FuelStatistics(entries: [
            makeEntry(on: day(2025, 1, 7), price: 3.49),
        ])
        let tuesday = try #require(statistics.weekdayPrices.first)
        #expect(tuesday.weekday == 3)
        #expect(abs(tuesday.averagePrice - 3.49) < 0.0001)
        #expect(tuesday.fillUpCount == 1)
        #expect(statistics.weekdayPriceInsight() == nil)
    }

    @Test func patternIsIndependentOfInputOrder() {
        let entries = [
            makeEntry(on: day(2025, 1, 3), price: 3.31),   // Fri
            makeEntry(on: day(2025, 1, 14), price: 3.20),  // Tue
            makeEntry(on: day(2025, 1, 10), price: 3.31),  // Fri
            makeEntry(on: day(2025, 1, 7), price: 3.20),   // Tue
        ]
        for arrangement in [entries, entries.reversed(), entries.shuffled()] {
            let statistics = FuelStatistics(entries: Array(arrangement))
            #expect(statistics.cheapestWeekday?.weekday == 3)   // Tuesday
            #expect(statistics.priciestWeekday?.weekday == 6)   // Friday
        }
    }

    @Test func equalWeekdayAveragesProduceNoInsight() {
        // Two weekdays, plenty of fills, but identical average prices.
        let statistics = FuelStatistics(entries: [
            makeEntry(on: day(2025, 1, 7), price: 3.25),   // Tue
            makeEntry(on: day(2025, 1, 14), price: 3.25),  // Tue
            makeEntry(on: day(2025, 1, 3), price: 3.25),   // Fri
            makeEntry(on: day(2025, 1, 10), price: 3.25),  // Fri
        ])
        #expect(statistics.weekdayPrices.count == 2)
        #expect(statistics.weekdayPriceInsight() == nil)
    }
}
