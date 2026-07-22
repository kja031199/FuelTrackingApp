import Foundation

/// Everything readable from the printed text of a fuel receipt: the pump
/// numbers (reused from the pump parser) plus the two things a receipt shows
/// that a live pump display doesn't — a printed purchase date/time and the
/// name of the station.
struct ReceiptReading: Equatable {
    var reading = PumpReading()
    var purchaseDate: Date?
    var stationName: String?

    var isEmpty: Bool {
        reading == PumpReading() && purchaseDate == nil && stationName == nil
    }
}

/// Parses OCR text lines from a fuel receipt.
///
/// The gallons / price / total triple is delegated to ``PumpScanParser``,
/// whose label and arithmetic-consistency logic already isolates a receipt's
/// fuel line — and naturally rejects a grand total that bundles in tax, a car
/// wash, or a loyalty discount, because gallons × price won't reconcile with
/// it. On top of that, this parser adds what only a receipt carries:
///
/// - the printed **purchase date and time**, in the many formats receipts use
///   (the photo's own EXIF date is merely when it was snapped, which may be
///   days later);
/// - the **station brand**, matched against known fuel retailers so we return
///   a clean name instead of a random line of address text.
enum ReceiptScanParser {
    static func parse(_ rawLines: [String], referenceDate: Date = .now) -> ReceiptReading {
        var result = ReceiptReading()
        result.reading = PumpScanParser.parse(rawLines)

        let lines = rawLines.map { $0.uppercased() }
        result.stationName = station(in: lines)
        result.purchaseDate = purchaseDate(in: lines, referenceDate: referenceDate)
        return result
    }

    // MARK: - Station brand

    /// Distinctive brand words, most-specific first, paired with a clean
    /// display name. Every needle is alphabetic, so it can't collide with a
    /// dollar amount or pump number, and matches are boundary-checked so a
    /// brand can't hide inside a longer word (e.g. ARCO inside "MARCO").
    private static let brands: [(needle: String, name: String)] = [
        ("EXXONMOBIL", "ExxonMobil"),
        ("EXXON", "Exxon"),
        ("MOBIL", "Mobil"),
        ("SHELL", "Shell"),
        ("CHEVRON", "Chevron"),
        ("TEXACO", "Texaco"),
        ("MARATHON", "Marathon"),
        ("SUNOCO", "Sunoco"),
        ("VALERO", "Valero"),
        ("PHILLIPS 66", "Phillips 66"),
        ("PHILLIPS", "Phillips 66"),
        ("CONOCO", "Conoco"),
        ("CITGO", "Citgo"),
        ("SINCLAIR", "Sinclair"),
        ("ARCO", "ARCO"),
        ("QUIKTRIP", "QuikTrip"),
        ("RACETRAC", "RaceTrac"),
        ("CIRCLE K", "Circle K"),
        ("SPEEDWAY", "Speedway"),
        ("KWIK TRIP", "Kwik Trip"),
        ("KWIK STAR", "Kwik Star"),
        ("KUM & GO", "Kum & Go"),
        ("CASEY", "Casey's"),
        ("BUC-EE", "Buc-ee's"),
        ("BUCEE", "Buc-ee's"),
        ("LOVE'S", "Love's"),
        ("FLYING J", "Flying J"),
        ("PILOT", "Pilot"),
        ("WAWA", "Wawa"),
        ("SHEETZ", "Sheetz"),
        ("MAVERIK", "Maverik"),
        ("ROYAL FARMS", "Royal Farms"),
        ("MURPHY", "Murphy USA"),
        ("HOLIDAY", "Holiday"),
        ("CENEX", "Cenex"),
        ("GETGO", "GetGo"),
        ("IRVING", "Irving"),
        ("PETRO-CANADA", "Petro-Canada"),
        ("ESSO", "Esso"),
        ("COSTCO", "Costco"),
        ("SAM'S CLUB", "Sam's Club"),
        ("SAMS CLUB", "Sam's Club"),
        ("MEIJER", "Meijer"),
        ("BP", "BP"),
    ]

    /// The brand from the topmost line that names one — the merchant header
    /// usually sits at the top, above the address.
    private static func station(in lines: [String]) -> String? {
        for line in lines {
            for brand in brands where boundaryContains(line, brand.needle) {
                return brand.name
            }
        }
        return nil
    }

    /// True if `needle` appears in `haystack` bounded by non-letters, so a
    /// brand can't match inside a longer word.
    private static func boundaryContains(_ haystack: String, _ needle: String) -> Bool {
        var searchStart = haystack.startIndex
        while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            let beforeOK = range.lowerBound == haystack.startIndex
                || !haystack[haystack.index(before: range.lowerBound)].isLetter
            let afterOK = range.upperBound == haystack.endIndex
                || !haystack[range.upperBound].isLetter
            if beforeOK && afterOK { return true }
            guard range.upperBound < haystack.endIndex else { break }
            searchStart = haystack.index(after: range.lowerBound)
        }
        return false
    }

    // MARK: - Date & time

    private static func purchaseDate(in lines: [String], referenceDate: Date) -> Date? {
        var components: DateComponents?
        for line in lines {
            if let match = date(in: line) {
                components = match
                break
            }
        }
        guard var components else { return nil }

        for line in lines {
            if let time = time(in: line) {
                components.hour = time.hour
                components.minute = time.minute
                components.second = time.second
                break
            }
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let date = calendar.date(from: components) else { return nil }

        // A receipt is a record of the past. Reject anything meaningfully in
        // the future (allow a day of clock skew) or absurdly old — both are
        // the signature of a misread number, not a real purchase date.
        guard date <= referenceDate.addingTimeInterval(86_400),
              date >= referenceDate.addingTimeInterval(-40 * 365 * 86_400) else {
            return nil
        }
        // Reject impossible calendar days (e.g. Feb 30) that Calendar would
        // otherwise silently roll forward into the next month.
        let rounded = calendar.dateComponents([.year, .month, .day], from: date)
        guard rounded.year == components.year,
              rounded.month == components.month,
              rounded.day == components.day else {
            return nil
        }
        return date
    }

    private static func date(in line: String) -> DateComponents? {
        // ISO first: 2026-07-19 / 2026.07.19
        if let m = line.firstMatch(of: #/\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b/#) {
            return components(year: Int(m.1), month: Int(m.2), day: Int(m.3))
        }
        // Month name: JUL 19, 2026 / JULY 19 2026 / SEP 3RD 2026
        if let m = line.firstMatch(of: #/\b([A-Z]{3,9})\.?\s+(\d{1,2})(?:ST|ND|RD|TH)?,?\s+(\d{2,4})\b/#),
           let month = monthNumber(String(m.1)) {
            return components(year: Int(m.3), month: month, day: Int(m.2))
        }
        // Numeric: 07/19/2026, 7/19/26, 19-07-2026.
        if let m = line.firstMatch(of: #/\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b/#) {
            guard let a = Int(m.1), let b = Int(m.2), let year = Int(m.3) else { return nil }
            // A first field over 12 can only be the day (day/month ordering);
            // otherwise assume US month/day.
            let month = (a > 12 && b <= 12) ? b : a
            let day = (a > 12 && b <= 12) ? a : b
            return components(year: year, month: month, day: day)
        }
        return nil
    }

    private static func components(year: Int?, month: Int?, day: Int?) -> DateComponents? {
        guard var year, let month, let day,
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        if year < 100 { year += 2000 }           // "26" → 2026
        guard (1990...2100).contains(year) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return components
    }

    private static func monthNumber(_ name: String) -> Int? {
        let months = ["JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6,
                      "JUL": 7, "AUG": 8, "SEP": 9, "OCT": 10, "NOV": 11, "DEC": 12]
        return months[String(name.prefix(3))]
    }

    private static func time(in line: String) -> (hour: Int, minute: Int, second: Int?)? {
        guard let m = line.firstMatch(of: #/\b(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)?\b/#),
              var hour = Int(m.1), let minute = Int(m.2),
              (0...59).contains(minute) else { return nil }

        let meridiem = m.4.map(String.init)
        let second = m.3.flatMap { Int($0) }
        if let second, !(0...59).contains(second) { return nil }

        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "PM", hour < 12 { hour += 12 }
            if meridiem == "AM", hour == 12 { hour = 0 }
        }
        guard (0...23).contains(hour) else { return nil }
        return (hour, minute, second)
    }
}
