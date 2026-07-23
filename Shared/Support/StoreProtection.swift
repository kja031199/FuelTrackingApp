import Foundation
import OSLog

/// Best-effort at-rest protection for the on-device SwiftData store.
///
/// Marks the store file, its SQLite journal sidecars, and any external-storage
/// blobs with a data-protection class so they aren't readable off a locked or
/// stolen device once it has been unlocked at least once since boot.
///
/// `.completeUntilFirstUserAuthentication` is the safe default: it still allows
/// background access after the user's first post-boot unlock (so CloudKit sync
/// and a future widget keep working) while keeping the data encrypted at rest
/// before that.
///
/// **Limitation.** This protects the files that exist when the store is opened —
/// which covers the structured record store (odometer, coordinates, station
/// names, the whole fill-up history). The *comprehensive*, always-on guarantee
/// for every file the app writes later (e.g. a receipt-image blob added after
/// launch) comes from the `com.apple.developer.default-data-protection`
/// entitlement. That entitlement stays out of the shipped build to preserve
/// free-Apple-ID compatibility (same posture as iCloud sync — see the README),
/// so this applies protection directly to the store's files instead. Enabling
/// the entitlement is the documented upgrade path.
enum StoreProtection {
    private static let log = Logger(subsystem: "FuelTracker", category: "Persistence")

    /// The data-protection class applied to the store's files.
    static let fileProtection: FileProtectionType = .completeUntilFirstUserAuthentication

    /// Applies the protection class to the store at `storeURL` and its related
    /// files. Best-effort: every step is guarded, so a store on a filesystem
    /// that doesn't support data protection (e.g. the Simulator) is a no-op
    /// rather than a failure.
    static func secureStore(at storeURL: URL) {
        var targets: [URL] = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm"),
        ]

        // External-storage blobs live in a sibling "<store>_SUPPORT" directory.
        let supportDirectory = storeURL.deletingLastPathComponent()
            .appendingPathComponent("\(storeURL.lastPathComponent)_SUPPORT")
        targets.append(supportDirectory)
        if let contents = try? FileManager.default.subpathsOfDirectory(atPath: supportDirectory.path) {
            for relative in contents {
                targets.append(supportDirectory.appendingPathComponent(relative))
            }
        }

        var secured = 0
        for url in targets where FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.setAttributes(
                    [.protectionKey: fileProtection], ofItemAtPath: url.path
                )
                secured += 1
            } catch {
                log.notice("Could not set file protection: \(error, privacy: .private)")
            }
        }
        log.notice("Applied at-rest protection to \(secured, privacy: .public) store file(s).")
    }
}
