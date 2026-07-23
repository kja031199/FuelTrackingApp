import Foundation
import Testing
@testable import FuelTracker

/// A scripted authenticator so the lock's transitions can be tested without the
/// biometric hardware. Shared across the lock and rendering tests.
struct StubAuthenticator: DeviceAuthenticating {
    var canAuthenticate: Bool
    var result: Bool
    func authenticate(reason: String) async -> Bool { result }
}

@MainActor
struct AppLockTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.applock.\(UUID().uuidString)")!
    }

    private func enabledDefaults() -> UserDefaults {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "privacy.appLockEnabled")
        return defaults
    }

    @Test func offByDefaultAndUnlocked() {
        let lock = AppLock(defaults: freshDefaults(),
                           authenticator: StubAuthenticator(canAuthenticate: true, result: true))
        #expect(!lock.isEnabled)
        #expect(!lock.isLocked)
    }

    @Test func enabledOnACapableDeviceStartsLocked() {
        let lock = AppLock(defaults: enabledDefaults(),
                           authenticator: StubAuthenticator(canAuthenticate: true, result: true))
        #expect(lock.isEnabled)
        #expect(lock.isLocked)
    }

    @Test func enabledWithoutDeviceAuthCannotLock() {
        // Turned on in a prior session, but no biometric/passcode is available
        // now — there'd be no way to unlock, so it must not lock the user out.
        let lock = AppLock(defaults: enabledDefaults(),
                           authenticator: StubAuthenticator(canAuthenticate: false, result: false))
        #expect(lock.isEnabled)
        #expect(!lock.canUseLock)
        #expect(!lock.isLocked)
    }

    @Test func togglingOnDoesNotLockUntilBackgrounded() {
        let lock = AppLock(defaults: freshDefaults(),
                           authenticator: StubAuthenticator(canAuthenticate: true, result: true))
        lock.isEnabled = true
        #expect(!lock.isLocked)   // not jarring: no immediate lock on toggle
        lock.lockOnBackground()
        #expect(lock.isLocked)
    }

    @Test func togglingOffUnlocks() {
        let lock = AppLock(defaults: enabledDefaults(),
                           authenticator: StubAuthenticator(canAuthenticate: true, result: true))
        #expect(lock.isLocked)
        lock.isEnabled = false
        #expect(!lock.isLocked)
    }

    @Test func successfulAuthenticationUnlocks() async {
        let lock = AppLock(defaults: enabledDefaults(),
                           authenticator: StubAuthenticator(canAuthenticate: true, result: true))
        #expect(lock.isLocked)
        let ok = await lock.unlock()
        #expect(ok)
        #expect(!lock.isLocked)
    }

    @Test func failedAuthenticationStaysLocked() async {
        let lock = AppLock(defaults: enabledDefaults(),
                           authenticator: StubAuthenticator(canAuthenticate: true, result: false))
        let ok = await lock.unlock()
        #expect(!ok)
        #expect(lock.isLocked)
    }

    @Test func backgroundingWhileDisabledDoesNotLock() {
        let lock = AppLock(defaults: freshDefaults(),
                           authenticator: StubAuthenticator(canAuthenticate: true, result: true))
        lock.lockOnBackground()
        #expect(!lock.isLocked)
    }

    @Test func enablingPersistsAndRelocksOnNextColdStart() {
        let defaults = freshDefaults()
        let lock = AppLock(defaults: defaults,
                           authenticator: StubAuthenticator(canAuthenticate: true, result: true))
        lock.isEnabled = true

        let relaunched = AppLock(defaults: defaults,
                                 authenticator: StubAuthenticator(canAuthenticate: true, result: true))
        #expect(relaunched.isEnabled)
        #expect(relaunched.isLocked)
    }
}

// MARK: - At-rest store protection

struct StoreProtectionTests {
    @Test func usesCompleteUntilFirstUserAuthentication() {
        #expect(StoreProtection.fileProtection == .completeUntilFirstUserAuthentication)
    }

    @Test func securingMissingFilesIsASilentNoOp() {
        // Best-effort: a store that doesn't exist yet must not crash.
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("absent-\(UUID().uuidString).store")
        StoreProtection.secureStore(at: missing)
    }

    @Test func securingAnExistingFileAppliesOrIsIgnored() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = directory.appendingPathComponent("test.store")
        try Data([1, 2, 3]).write(to: store)
        StoreProtection.secureStore(at: store)

        // The Simulator/host filesystem may not enforce data protection, so the
        // attribute is either exactly the class we set or absent — never a
        // different value. On-device enforcement is verified manually.
        let attributes = try FileManager.default.attributesOfItem(atPath: store.path)
        if let applied = attributes[.protectionKey] as? FileProtectionType {
            #expect(applied == StoreProtection.fileProtection)
        }
    }
}
