import Foundation
import LocalAuthentication

/// `LAContext`-backed device authentication: Face ID / Touch ID, falling back to
/// the device passcode. The `.deviceOwnerAuthentication` policy provides that
/// fallback automatically, and reports as available whenever a biometric *or* a
/// passcode is set.
struct BiometricAuthenticator: DeviceAuthenticating {
    var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            // A cancel, a failed match, or no-enrollment all count as "not
            // authenticated" — stay locked.
            return false
        }
    }
}
