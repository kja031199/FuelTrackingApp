import Foundation
import Observation

/// User privacy preferences, persisted to `UserDefaults` and injected into the
/// SwiftUI environment (read with `@Environment(PrivacySettings.self)`).
///
/// Currently governs location capture. Writing a property persists it.
@Observable
final class PrivacySettings {
    private enum Key {
        static let locationCapture = "privacy.locationCaptureEnabled"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Whether logging a fill-up may record where it happened. When off, the
    /// app neither requests nor uses location, and stores no coordinates.
    var locationCaptureEnabled: Bool {
        didSet { defaults.set(locationCaptureEnabled, forKey: Key.locationCapture) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Defaults to on: station detection is already gated behind an explicit
        // iOS permission prompt, so a location is only ever captured after the
        // user has consented at the system level. The toggle lets them opt out
        // entirely. `object(forKey:)` distinguishes "never set" (→ on) from a
        // stored `false`, which `bool(forKey:)` could not.
        locationCaptureEnabled = (defaults.object(forKey: Key.locationCapture) as? Bool) ?? true
    }
}
