import Foundation
import Testing
@testable import FuelTracker

struct MeasurementUnitsTests {
    private func close(_ a: Double, _ b: Double, tol: Double = 1e-6) -> Bool {
        abs(a - b) <= tol * Swift.max(1, abs(b))
    }

    // MARK: - Volume

    @Test func volumeConvertsGallonsAndLitersExactly() {
        #expect(VolumeUnit.gallons.fromGallons(10) == 10)
        #expect(close(VolumeUnit.liters.fromGallons(1), 3.785411784))
        // Round-trips back to canonical gallons.
        #expect(close(VolumeUnit.liters.toGallons(VolumeUnit.liters.fromGallons(12.5)), 12.5))
        #expect(VolumeUnit.gallons.abbreviation == "gal")
        #expect(VolumeUnit.liters.abbreviation == "L")
    }

    @Test func volumeScalesNegativeAndZeroLinearly() {
        #expect(VolumeUnit.liters.fromGallons(0) == 0)
        #expect(close(VolumeUnit.liters.fromGallons(-5), -5 * 3.785411784))
    }

    // MARK: - Distance

    @Test func distanceConvertsMilesAndKilometersExactly() {
        #expect(DistanceUnit.miles.fromMiles(100) == 100)
        #expect(close(DistanceUnit.kilometers.fromMiles(1), 1.609344))
        #expect(close(DistanceUnit.kilometers.toMiles(DistanceUnit.kilometers.fromMiles(42.2)), 42.2))
        #expect(DistanceUnit.miles.abbreviation == "mi")
        #expect(DistanceUnit.kilometers.abbreviation == "km")
    }

    // MARK: - Economy (the non-linear one)

    @Test func economyConvertsFromMPG() {
        #expect(EconomyUnit.mpg.fromMPG(30) == 30)
        // 30 US MPG ≈ 12.754 km/L and ≈ 7.840 L/100km (the reciprocal).
        #expect(close(EconomyUnit.kmPerLiter.fromMPG(30)!, 30 * 1.609344 / 3.785411784))
        #expect(close(EconomyUnit.litersPer100km.fromMPG(30)!, 100 * 3.785411784 / (30 * 1.609344)))
    }

    @Test func economyIsUndefinedForNonPositiveOrNonFiniteInput() {
        for unit in EconomyUnit.allCases {
            #expect(unit.fromMPG(0) == nil)
            #expect(unit.fromMPG(-5) == nil)
            #expect(unit.fromMPG(.nan) == nil)
            #expect(unit.fromMPG(.infinity) == nil)
        }
    }

    @Test func economyHigherIsBetterFlipsOnlyForLitersPer100km() {
        #expect(EconomyUnit.mpg.higherIsBetter)
        #expect(EconomyUnit.kmPerLiter.higherIsBetter)
        #expect(!EconomyUnit.litersPer100km.higherIsBetter)
    }

    @Test func economyOrderingIsPreservedByLinearUnitsAndInvertedByLitersPer100km() {
        // A better car (higher MPG) reads higher in km/L but LOWER in L/100km.
        let worse = 20.0, better = 40.0
        #expect(EconomyUnit.kmPerLiter.fromMPG(better)! > EconomyUnit.kmPerLiter.fromMPG(worse)!)
        #expect(EconomyUnit.litersPer100km.fromMPG(better)! < EconomyUnit.litersPer100km.fromMPG(worse)!)
    }

    // MARK: - Preferences seed

    @Test func localeSeedsMetricOrUS() {
        #expect(UnitPreferences.forCurrentLocale(Locale(identifier: "en_US")) == .us)
        #expect(UnitPreferences.forCurrentLocale(Locale(identifier: "fr_FR")) == .metric)
    }
}

// MARK: - Persisted settings store

struct UnitSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "test.units.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test func writingAPreferencePersistsAcrossReload() {
        let defaults = freshDefaults()
        let settings = UnitSettings(defaults: defaults)
        settings.volumeUnit = .liters
        settings.distanceUnit = .kilometers
        settings.economyUnit = .litersPer100km

        let reloaded = UnitSettings(defaults: defaults)
        #expect(reloaded.volumeUnit == .liters)
        #expect(reloaded.distanceUnit == .kilometers)
        #expect(reloaded.economyUnit == .litersPer100km)
        #expect(reloaded.preferences == .metric)
    }

    @Test func aGarbageStoredValueFallsBackToAValidUnit() {
        let defaults = freshDefaults()
        defaults.set("plutonium", forKey: "units.volume")
        let settings = UnitSettings(defaults: defaults)
        // Never crashes, always a real case.
        #expect(VolumeUnit.allCases.contains(settings.volumeUnit))
    }
}

// MARK: - Unit-aware formatters

struct FormattersUnitsTests {
    private func digits(_ s: String) -> String { s.filter(\.isNumber) }

    @Test func volumeAndDistanceAppendTheAbbreviationWhenAsked() {
        #expect(Format.volume(10, in: .gallons, withUnit: true).hasSuffix(" gal"))
        #expect(Format.volume(10, in: .liters, withUnit: true).hasSuffix(" L"))
        #expect(Format.distance(100, in: .miles, withUnit: true).hasSuffix(" mi"))
        #expect(Format.distance(100, in: .kilometers, withUnit: true).hasSuffix(" km"))
        // Without the flag it's just the number.
        #expect(!Format.volume(10, in: .liters).contains("L"))
    }

    @Test func economyFormatsConvertedValueOrNilWhenUndefined() {
        #expect(Format.economy(30, in: .mpg) != nil)
        #expect(Format.economy(0, in: .litersPer100km) == nil)
        #expect(Format.economy(-1, in: .mpg) == nil)
    }

    @Test func fuelPricePerLiterIsAboutAQuarterOfPerGallon() {
        // $3.785/gal ≈ $1.000/L. Compare digit strings to stay locale-neutral.
        let perGallon = Format.fuelPrice(3.785411784, per: .gallons)
        let perLiter = Format.fuelPrice(3.785411784, per: .liters)
        #expect(digits(perGallon).hasPrefix("3785") || digits(perGallon).hasPrefix("3786"))
        #expect(digits(perLiter).hasPrefix("1000") || digits(perLiter).hasPrefix("999"))
    }

    @Test func usFormattersMatchTheirCanonicalCounterparts() {
        // The US path must reproduce the original output exactly.
        #expect(Format.volume(9.5, in: .gallons) == Format.gallons(9.5))
        #expect(Format.distance(12_345, in: .miles) == Format.odometer(12_345))
        #expect(Format.economy(28.4, in: .mpg) == Format.mpg(28.4))
        #expect(Format.fuelPrice(3.499, per: .gallons) == Format.fuelPrice(3.499))
        #expect(Format.costPerDistance(0.12, in: .miles) == Format.costPerMile(0.12))
    }
}
