import Foundation

/// The pure decision of whether to show the first-run experience.
///
/// Kept separate from the view so the "who sees onboarding" rule is unit-tested.
enum OnboardingGate {
    /// Onboarding is shown only to a genuinely new user: one who hasn't finished
    /// (or skipped) it **and** has no vehicles yet. A user who already has data —
    /// including vehicles synced from iCloud on a fresh install — is never
    /// onboarded, even if the completion flag hasn't been set on this device.
    static func shouldOnboard(hasCompleted: Bool, vehicleCount: Int) -> Bool {
        !hasCompleted && vehicleCount == 0
    }
}
