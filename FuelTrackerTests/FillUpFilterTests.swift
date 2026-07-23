import Foundation
import Testing
@testable import FuelTracker

@MainActor
struct FillUpFilterTests {
    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    private func entry(
        date: Date = Date(timeIntervalSince1970: 1_700_000_000),
        station: String = "",
        notes: String = "",
        grade: FuelGrade = .regular
    ) -> FuelEntry {
        FuelEntry(date: date, odometer: 100, gallons: 10, pricePerGallon: 3,
                  fuelGrade: grade, station: station, notes: notes)
    }

    // MARK: - Search

    @Test func searchMatchesStationOrNotesCaseInsensitively() {
        let entries = [
            entry(station: "Shell", notes: ""),
            entry(station: "", notes: "topped off before road trip"),
            entry(station: "Costco", notes: "membership"),
        ]
        var filter = FillUpFilter()
        filter.searchText = "shell"
        #expect(filter.apply(to: entries).count == 1)

        filter.searchText = "ROAD"
        #expect(filter.apply(to: entries).count == 1)

        filter.searchText = "o" // matches Costco, topped/road, — several
        #expect(filter.apply(to: entries).count == 2)
    }

    @Test func whitespaceOnlySearchIsInactiveAndMatchesEverything() {
        let entries = [entry(station: "Shell"), entry(station: "BP")]
        var filter = FillUpFilter()
        filter.searchText = "   \n"
        #expect(!filter.isActive)
        #expect(filter.apply(to: entries).count == 2)
    }

    @Test func aSearchThatMatchesNothingReturnsEmpty() {
        let entries = [entry(station: "Shell"), entry(station: "BP")]
        var filter = FillUpFilter()
        filter.searchText = "zzz-nonexistent"
        #expect(filter.apply(to: entries).isEmpty)
    }

    // MARK: - Date range

    @Test func rangeFiltersByCutoffRelativeToNow() {
        let now = day(2025, 6, 15)
        let entries = [
            entry(date: day(2025, 1, 1)),   // > 3 months ago
            entry(date: day(2025, 5, 1)),   // within 3 months
        ]
        var filter = FillUpFilter()
        filter.range = .threeMonths
        let matched = filter.apply(to: entries, now: now)
        #expect(matched.count == 1)
        #expect(matched.first?.date == day(2025, 5, 1))
    }

    @Test func allRangeIncludesEverything() {
        let entries = [entry(date: day(2000, 1, 1)), entry(date: day(2030, 1, 1))]
        #expect(FillUpFilter().apply(to: entries, now: day(2025, 6, 15)).count == 2)
    }

    // MARK: - Fuel grade

    @Test func gradeFilterMatchesExactGrade() {
        let entries = [entry(grade: .premium), entry(grade: .regular), entry(grade: .premium)]
        var filter = FillUpFilter()
        filter.fuelGrade = .premium
        #expect(filter.apply(to: entries).count == 2)
    }

    @Test func gradeFilterHandlesTheOtherFallback() {
        // An entry with an unrecognized raw grade reads back as `.other`; a
        // filter for `.other` must catch it, not crash or miss it.
        let odd = entry(grade: .regular)
        odd.fuelGradeRaw = "Nitro"
        let entries = [odd, entry(grade: .regular)]
        var filter = FillUpFilter()
        filter.fuelGrade = .other
        let matched = filter.apply(to: entries)
        #expect(matched.count == 1)
        #expect(matched.first === odd)
    }

    // MARK: - Station

    @Test func stationFilterMatchesExactly() {
        let entries = [entry(station: "Shell"), entry(station: "Shell #123"), entry(station: "BP")]
        var filter = FillUpFilter()
        filter.station = "Shell"
        #expect(filter.apply(to: entries).count == 1) // exact, not prefix
    }

    @Test func stationFilterForAnAbsentStationReturnsEmpty() {
        let entries = [entry(station: "Shell")]
        var filter = FillUpFilter()
        filter.station = "Chevron"
        #expect(filter.apply(to: entries).isEmpty)
    }

    // MARK: - Combined + ordering

    @Test func everyActiveConstraintMustMatch() {
        let now = day(2025, 6, 15)
        let entries = [
            entry(date: day(2025, 5, 1), station: "Shell", notes: "gas", grade: .premium),
            entry(date: day(2025, 5, 2), station: "Shell", notes: "gas", grade: .regular), // wrong grade
            entry(date: day(2025, 1, 1), station: "Shell", notes: "gas", grade: .premium), // out of range
            entry(date: day(2025, 5, 3), station: "BP", notes: "gas", grade: .premium),    // wrong station
        ]
        var filter = FillUpFilter()
        filter.range = .threeMonths
        filter.station = "Shell"
        filter.fuelGrade = .premium
        filter.searchText = "gas"
        let matched = filter.apply(to: entries, now: now)
        #expect(matched.count == 1)
        #expect(matched.first?.date == day(2025, 5, 1))
    }

    @Test func applyPreservesInputOrder() {
        let a = entry(date: day(2025, 5, 3), station: "Shell")
        let b = entry(date: day(2025, 5, 2), station: "Shell")
        let c = entry(date: day(2025, 5, 1), station: "Shell")
        var filter = FillUpFilter()
        filter.station = "Shell"
        #expect(filter.apply(to: [a, b, c]).map(\.date) == [a, b, c].map(\.date))
    }

    // MARK: - isActive

    @Test func isActiveReflectsWhetherAnyConstraintIsSet() {
        #expect(!FillUpFilter().isActive)
        var f = FillUpFilter(); f.range = .year
        #expect(f.isActive)
        var g = FillUpFilter(); g.fuelGrade = .diesel
        #expect(g.isActive)
        var h = FillUpFilter(); h.station = "Shell"
        #expect(h.isActive)
    }
}
