import Foundation

enum Format {
    static var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    static func currency(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode))
    }

    /// Price per gallon with the extra tenth-of-a-cent digit gas stations use.
    static func fuelPrice(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode).precision(.fractionLength(3)))
    }

    static func mpg(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    static func gallons(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)))
    }

    static func odometer(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    static func costPerMile(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode).precision(.fractionLength(2...3)))
    }

    /// Miles with compact notation for tight spaces, e.g. "42.2K".
    static func compactMiles(_ value: Double) -> String {
        value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    static func wholeCurrency(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode).precision(.fractionLength(0)))
    }

    /// Currency with standard two decimal places, e.g. y-axis price labels.
    static func plainCurrency(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode).precision(.fractionLength(2)))
    }

    // MARK: - Unit-aware formatting
    //
    // These take a value in the app's canonical unit (gallons / miles / MPG)
    // and render it in the user's chosen unit. The canonical helpers above are
    // kept for currency and for callers that are inherently US (e.g. the pump
    // OCR, which reads US pumps).

    /// A canonical **gallons** value shown in the given volume unit, optionally
    /// with its abbreviation ("9.5" or "36 L").
    static func volume(_ gallons: Double, in unit: VolumeUnit, withUnit: Bool = false) -> String {
        let number = unit.fromGallons(gallons).formatted(.number.precision(.fractionLength(0...3)))
        return withUnit ? "\(number) \(unit.abbreviation)" : number
    }

    /// A canonical **miles** value shown in the given distance unit.
    static func distance(_ miles: Double, in unit: DistanceUnit, withUnit: Bool = false) -> String {
        let number = unit.fromMiles(miles).formatted(.number.precision(.fractionLength(0...1)))
        return withUnit ? "\(number) \(unit.abbreviation)" : number
    }

    /// A canonical **miles** value in compact notation ("42.2K"), in the given
    /// distance unit — for tight spaces like the watch.
    static func compactDistance(_ miles: Double, in unit: DistanceUnit, withUnit: Bool = false) -> String {
        let number = unit.fromMiles(miles).formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
        return withUnit ? "\(number) \(unit.abbreviation)" : number
    }

    /// A canonical **MPG** value shown in the given economy unit, or nil when
    /// economy is undefined (non-positive / non-finite input).
    static func economy(_ mpg: Double, in unit: EconomyUnit) -> String? {
        guard let converted = unit.fromMPG(mpg) else { return nil }
        return converted.formatted(.number.precision(.fractionLength(1)))
    }

    /// A canonical **price per gallon** shown per the given volume unit, with
    /// the extra tenth-of-a-cent digit fuel prices use ("$3.499" per gal, or
    /// the per-liter equivalent).
    static func fuelPrice(_ pricePerGallon: Double, per unit: VolumeUnit) -> String {
        let perUnit = pricePerGallon / unit.fromGallons(1)
        return perUnit.formatted(.currency(code: currencyCode).precision(.fractionLength(3)))
    }

    /// A canonical **cost per mile** shown per the given distance unit.
    static func costPerDistance(_ costPerMile: Double, in unit: DistanceUnit) -> String {
        let perUnit = costPerMile / unit.fromMiles(1)
        return perUnit.formatted(.currency(code: currencyCode).precision(.fractionLength(2...3)))
    }
}
