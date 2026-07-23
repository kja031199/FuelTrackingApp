import Foundation

// The app stores every measurement in one canonical unit — **miles**,
// **US gallons**, and **US MPG** — and converts only at the display and entry
// boundary. Nothing in the model or in `FuelStatistics` changes with the user's
// unit choice; these types own the conversions that sit between stored values
// and what the user sees or types.

/// Fuel volume. Canonical storage is US gallons.
enum VolumeUnit: String, CaseIterable, Identifiable, Codable {
    case gallons
    case liters

    var id: String { rawValue }

    /// Exact liters in one US gallon.
    static let litersPerGallon = 3.785411784

    var abbreviation: String {
        switch self {
        case .gallons: return "gal"
        case .liters: return "L"
        }
    }

    var name: String {
        switch self {
        case .gallons: return "Gallons"
        case .liters: return "Liters"
        }
    }

    /// Singular noun for labels like "Price per Gallon" / "Price per Liter".
    var singularNoun: String {
        switch self {
        case .gallons: return "Gallon"
        case .liters: return "Liter"
        }
    }

    /// A canonical gallons value expressed in this unit.
    func fromGallons(_ gallons: Double) -> Double {
        switch self {
        case .gallons: return gallons
        case .liters: return gallons * Self.litersPerGallon
        }
    }

    /// A value in this unit converted back to canonical gallons.
    func toGallons(_ value: Double) -> Double {
        switch self {
        case .gallons: return value
        case .liters: return value / Self.litersPerGallon
        }
    }
}

/// Distance / odometer. Canonical storage is miles.
enum DistanceUnit: String, CaseIterable, Identifiable, Codable {
    case miles
    case kilometers

    var id: String { rawValue }

    /// Exact kilometers in one mile.
    static let kilometersPerMile = 1.609344

    var abbreviation: String {
        switch self {
        case .miles: return "mi"
        case .kilometers: return "km"
        }
    }

    var name: String {
        switch self {
        case .miles: return "Miles"
        case .kilometers: return "Kilometers"
        }
    }

    /// Singular noun for titles like "Cost per Mile" / "Cost per Kilometer".
    var singularNoun: String {
        switch self {
        case .miles: return "Mile"
        case .kilometers: return "Kilometer"
        }
    }

    /// A canonical miles value expressed in this unit.
    func fromMiles(_ miles: Double) -> Double {
        switch self {
        case .miles: return miles
        case .kilometers: return miles * Self.kilometersPerMile
        }
    }

    /// A value in this unit converted back to canonical miles.
    func toMiles(_ value: Double) -> Double {
        switch self {
        case .miles: return value
        case .kilometers: return value / Self.kilometersPerMile
        }
    }
}

/// Fuel economy. Canonical storage is US MPG. Note the conversions are **not**
/// all linear: L/100km is the reciprocal of distance-per-volume, so higher MPG
/// means a *lower* L/100km number.
enum EconomyUnit: String, CaseIterable, Identifiable, Codable {
    case mpg
    case litersPer100km
    case kmPerLiter

    var id: String { rawValue }

    var abbreviation: String {
        switch self {
        case .mpg: return "MPG"
        case .litersPer100km: return "L/100km"
        case .kmPerLiter: return "km/L"
        }
    }

    var name: String {
        switch self {
        case .mpg: return "Miles per gallon"
        case .litersPer100km: return "Liters per 100 km"
        case .kmPerLiter: return "Kilometers per liter"
        }
    }

    /// True when a larger number is better economy. False for L/100km, where
    /// less fuel per distance — a smaller number — is better. Ranking itself is
    /// always done on canonical MPG; this only affects how a displayed number
    /// reads.
    var higherIsBetter: Bool {
        self != .litersPer100km
    }

    /// A canonical MPG value expressed in this unit, or nil when the value is
    /// non-positive or non-finite — economy is undefined there (and L/100km
    /// would divide by zero), so callers show a placeholder instead.
    func fromMPG(_ mpg: Double) -> Double? {
        guard mpg.isFinite, mpg > 0 else { return nil }
        switch self {
        case .mpg:
            return mpg
        case .kmPerLiter:
            return mpg * (DistanceUnit.kilometersPerMile / VolumeUnit.litersPerGallon)
        case .litersPer100km:
            return 100 * VolumeUnit.litersPerGallon / (mpg * DistanceUnit.kilometersPerMile)
        }
    }
}

/// The user's three unit choices, bundled so they can be passed through the
/// display layer as one value.
struct UnitPreferences: Equatable {
    var volume: VolumeUnit
    var distance: DistanceUnit
    var economy: EconomyUnit

    /// US customary units — the app's canonical storage units, and the default
    /// for non-metric locales.
    static let us = UnitPreferences(volume: .gallons, distance: .miles, economy: .mpg)

    /// Metric units, the default seed for metric locales.
    static let metric = UnitPreferences(volume: .liters, distance: .kilometers, economy: .litersPer100km)

    /// A sensible starting point for a locale: metric locales seed metric,
    /// everything else seeds US. The user can change any of the three in
    /// Settings afterward, so this only has to be a reasonable default.
    static func forCurrentLocale(_ locale: Locale = .current) -> UnitPreferences {
        locale.measurementSystem == .metric ? .metric : .us
    }
}
