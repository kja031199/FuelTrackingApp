import Foundation
import Observation

/// The user's unit preferences, persisted to `UserDefaults` so they survive
/// launches and are readable everywhere — views, the watch, and any future
/// widget — without depending on SwiftUI's `@AppStorage`.
///
/// Injected into the SwiftUI environment at the app root; read with
/// `@Environment(UnitSettings.self)`. Writing a property persists it.
@Observable
final class UnitSettings {
    private enum Key {
        static let volume = "units.volume"
        static let distance = "units.distance"
        static let economy = "units.economy"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var volumeUnit: VolumeUnit {
        didSet { defaults.set(volumeUnit.rawValue, forKey: Key.volume) }
    }

    var distanceUnit: DistanceUnit {
        didSet { defaults.set(distanceUnit.rawValue, forKey: Key.distance) }
    }

    var economyUnit: EconomyUnit {
        didSet { defaults.set(economyUnit.rawValue, forKey: Key.economy) }
    }

    /// Loads saved units, falling back to a locale-appropriate default for any
    /// choice that hasn't been set yet.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let seed = UnitPreferences.forCurrentLocale()
        volumeUnit = defaults.string(forKey: Key.volume).flatMap(VolumeUnit.init(rawValue:)) ?? seed.volume
        distanceUnit = defaults.string(forKey: Key.distance).flatMap(DistanceUnit.init(rawValue:)) ?? seed.distance
        economyUnit = defaults.string(forKey: Key.economy).flatMap(EconomyUnit.init(rawValue:)) ?? seed.economy
    }

    /// The current choices bundled for passing through the display layer.
    var preferences: UnitPreferences {
        UnitPreferences(volume: volumeUnit, distance: distanceUnit, economy: economyUnit)
    }
}
