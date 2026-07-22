import Foundation
import Testing
@testable import FuelTracker

/// A fixed "today" so receipt dates are deterministically in the past
/// regardless of when the suite runs. Chosen to sit after every past-dated
/// fixture below (through early September) but before the December date used
/// to exercise future rejection.
private let reference = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 15))!

private func parse(_ lines: [String]) -> ReceiptReading {
    ReceiptScanParser.parse(lines, referenceDate: reference)
}

private func ymd(_ date: Date) -> (year: Int, month: Int, day: Int) {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return (c.year!, c.month!, c.day!)
}

private func hm(_ date: Date) -> (hour: Int, minute: Int) {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (c.hour!, c.minute!)
}

struct ReceiptScanParserTests {
    // MARK: - Realistic receipts

    @Test func parsesAFullShellReceipt() throws {
        let reading = parse([
            "SHELL",
            "1234 MAIN ST",
            "AUSTIN TX 78701",
            "07/19/2026  14:35:07",
            "PUMP 04",
            "REGULAR",
            "GALLONS      10.234",
            "PRICE/GAL    $3.499",
            "FUEL TOTAL   $35.81",
        ])
        #expect(reading.reading.gallons == 10.234)
        #expect(reading.reading.pricePerGallon == 3.499)
        #expect(reading.stationName == "Shell")
        let date = try #require(reading.purchaseDate)
        #expect(ymd(date) == (2026, 7, 19))
        #expect(hm(date) == (14, 35))
    }

    @Test func parsesAOneLineFuelEntryByArithmetic() {
        // Everything on one line, no clean labels — the gallons × price ≈
        // total consistency (delegated to PumpScanParser) recovers it.
        let reading = parse(["CHEVRON", "10.234 GAL @ 3.499  35.81"])
        #expect(reading.reading.gallons == 10.234)
        #expect(reading.reading.pricePerGallon == 3.499)
        #expect(reading.stationName == "Chevron")
    }

    // MARK: - Date formats

    @Test func parsesUSNumericDate() throws {
        #expect(ymd(try #require(parse(["07/19/2026"]).purchaseDate)) == (2026, 7, 19))
    }

    @Test func parsesTwoDigitYear() throws {
        #expect(ymd(try #require(parse(["07/19/26"]).purchaseDate)) == (2026, 7, 19))
    }

    @Test func parsesISODate() throws {
        #expect(ymd(try #require(parse(["2026-07-19"]).purchaseDate)) == (2026, 7, 19))
    }

    @Test func parsesMonthNameDates() throws {
        #expect(ymd(try #require(parse(["JUL 19, 2026"]).purchaseDate)) == (2026, 7, 19))
        #expect(ymd(try #require(parse(["JULY 19 2026"]).purchaseDate)) == (2026, 7, 19))
        #expect(ymd(try #require(parse(["SEP 3RD 2026"]).purchaseDate)) == (2026, 9, 3))
    }

    @Test func disambiguatesDayFirstWhenFirstFieldExceedsTwelve() throws {
        // 19 can't be a month, so 19/07 must be day/month, not month/day.
        #expect(ymd(try #require(parse(["19/07/2026"]).purchaseDate)) == (2026, 7, 19))
    }

    // MARK: - Times

    @Test func parsesTwelveHourTimeWithMeridiem() throws {
        #expect(hm(try #require(parse(["07/19/2026", "02:35 PM"]).purchaseDate)) == (14, 35))
        #expect(hm(try #require(parse(["07/19/2026", "12:05 AM"]).purchaseDate)) == (0, 5))
    }

    @Test func parsesTwentyFourHourTimeWithSeconds() throws {
        #expect(hm(try #require(parse(["07/19/2026", "23:07:42"]).purchaseDate)) == (23, 7))
    }

    @Test func timeWithoutADateIsIgnored() {
        // A time alone can't anchor a day, so there's no purchase date.
        #expect(parse(["SHELL", "14:35"]).purchaseDate == nil)
    }

    @Test func outOfRangeTimeLeavesTheDateAtMidnight() throws {
        let reading = parse(["07/19/2026", "25:99"])
        let date = try #require(reading.purchaseDate)
        #expect(ymd(date) == (2026, 7, 19))
        #expect(hm(date) == (0, 0))
    }

    // MARK: - Station brands

    @Test func matchesMultiWordBrand() {
        #expect(parse(["CIRCLE K #4021", "07/19/2026"]).stationName == "Circle K")
    }

    @Test func matchesBrandsWithApostropheOrHyphen() {
        #expect(parse(["BUC-EE'S #52"]).stationName == "Buc-ee's")
        #expect(parse(["LOVE'S TRAVEL STOP"]).stationName == "Love's")
        #expect(parse(["SAM'S CLUB"]).stationName == "Sam's Club")
    }

    @Test func matchesTwoLetterBrandOnlyAtAWordBoundary() {
        #expect(parse(["BP", "07/19/2026"]).stationName == "BP")
        #expect(parse(["BP #1180"]).stationName == "BP")
        // "BP" buried inside a word is not the brand.
        #expect(parse(["SUBPAR SERVICE CENTER"]).stationName == nil)
    }

    @Test func ignoresABrandHiddenInsideAnotherWord() {
        // ARCO inside MARCOS must not register as the ARCO brand.
        #expect(parse(["MARCOS PIZZA", "555-123-4567"]).stationName == nil)
    }

    @Test func returnsTheTopmostBrandLine() {
        #expect(parse(["EXXON", "NEAR SHELL PLAZA"]).stationName == "Exxon")
    }

    @Test func receiptWithNoKnownBrandHasNilStation() {
        #expect(parse(["JOE'S GAS N GO", "07/19/2026"]).stationName == nil)
    }

    // MARK: - Hostile / abnormal input

    @Test func rejectsAFutureDate() {
        // A receipt can't be from the future; fall back to nil so the caller
        // uses the photo's capture date instead.
        #expect(parse(["12/25/2026"]).purchaseDate == nil)
    }

    @Test func rejectsImpossibleCalendarDates() {
        #expect(parse(["13/40/2026"]).purchaseDate == nil)   // month 13, day 40
        #expect(parse(["02/30/2026"]).purchaseDate == nil)   // Feb 30 never exists
    }

    @Test func doesNotReadPhoneOrZipAsADate() {
        #expect(parse(["PHONE 555-123-4567"]).purchaseDate == nil)
        #expect(parse(["AUSTIN TX 78701-1234"]).purchaseDate == nil)
    }

    @Test func carWashAndTaxLinesDoNotCorruptTheFuelNumbers() {
        // A mixed-purchase receipt: the fuel gallons and price must survive
        // even though a grand total bundles in a car wash.
        let reading = parse([
            "CHEVRON",
            "08/02/2026",
            "UNLEADED  9.000 GAL",
            "PRICE/GAL 3.500",
            "FUEL      31.50",
            "CAR WASH   9.00",
            "TAX        0.74",
            "TOTAL     41.24",
        ])
        #expect(reading.reading.gallons == 9.0)
        #expect(reading.reading.pricePerGallon == 3.5)
    }

    @Test func noiseAndEmptyInputProduceAnEmptyReading() {
        #expect(parse([]).isEmpty)
        #expect(parse(["THANK YOU", "COME AGAIN", "CASHIER: 07"]).isEmpty)
    }

    @Test func implausibleNumbersDoNotBecomeFuel() {
        // An odometer-sized number and an octane rating are out of every band.
        let reading = parse(["ODOMETER 42150.0", "OCTANE 87.0"])
        #expect(reading.reading == PumpReading())
    }

    @Test func aReceiptDatedExactlyAtReferenceIsAccepted() throws {
        // 10/15/2026 == reference: the boundary must not be rejected as future.
        #expect(ymd(try #require(parse(["10/15/2026"]).purchaseDate)) == (2026, 10, 15))
    }

    @Test func negativeAndGarbageValuesDoNotCrashOrFabricateFuel() {
        let reading = parse(["-3.500", "TOTAL -35.81", "PUMP #0000", "999999.999"])
        #expect(reading.reading.gallons == nil || reading.reading.gallons! > 0)
        #expect(reading.reading.pricePerGallon == nil || reading.reading.pricePerGallon! > 0)
    }
}
