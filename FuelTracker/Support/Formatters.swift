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
}
