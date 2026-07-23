import Foundation
import Observation

/// Abstracts device-owner authentication (Face ID / Touch ID / passcode) so the
/// lock's state machine can be unit-tested without the biometric hardware. The
/// iOS app injects an `LAContext`-backed implementation; tests inject a stub.
protocol DeviceAuthenticating: Sendable {
    /// Whether the device can authenticate the owner at all — a biometric is
    /// enrolled or a passcode is set. When false, the lock can't engage.
    var canAuthenticate: Bool { get }

    /// Prompts for authentication. Returns true only on success.
    func authenticate(reason: String) async -> Bool
}

/// Optional Face ID / Touch ID / passcode gate on app entry.
///
/// Owns both the persisted on/off preference and the live `isLocked` state, and
/// keeps the authentication at arm's length behind ``DeviceAuthenticating`` so
/// the transitions are testable. Off by default.
@MainActor
@Observable
final class AppLock {
    private enum Key {
        static let enabled = "privacy.appLockEnabled"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let authenticator: DeviceAuthenticating

    /// True while the app is gated behind the lock screen.
    private(set) var isLocked: Bool

    /// Whether the lock is turned on. Persisted. Turning it off unlocks
    /// immediately; turning it on takes effect the next time the app is
    /// backgrounded or relaunched (so toggling it in Settings isn't jarring).
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Key.enabled)
            if !isEnabled { isLocked = false }
        }
    }

    /// Whether the device is capable of authenticating (biometric enrolled or a
    /// passcode set). The UI disables the toggle and explains when this is false.
    var canUseLock: Bool { authenticator.canAuthenticate }

    init(defaults: UserDefaults = .standard, authenticator: DeviceAuthenticating) {
        self.defaults = defaults
        self.authenticator = authenticator
        let enabled = defaults.bool(forKey: Key.enabled) // absent → false
        self.isEnabled = enabled
        // Cold start begins locked when the feature is on and usable.
        self.isLocked = enabled && authenticator.canAuthenticate
    }

    /// Re-lock when the app leaves the foreground. No-op when disabled or when
    /// the device can't authenticate (nothing to unlock with).
    func lockOnBackground() {
        guard isEnabled, canUseLock else { return }
        isLocked = true
    }

    /// Prompt for authentication and unlock on success. Returns true if the app
    /// is (now) unlocked. A failed or cancelled attempt leaves it locked.
    @discardableResult
    func unlock() async -> Bool {
        guard isLocked else { return true }
        let succeeded = await authenticator.authenticate(reason: "Unlock FuelTracker")
        if succeeded { isLocked = false }
        return succeeded
    }
}
