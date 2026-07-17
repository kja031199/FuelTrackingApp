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
}
