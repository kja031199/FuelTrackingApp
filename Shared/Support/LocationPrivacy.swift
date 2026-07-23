import Foundation
import SwiftData

/// One-shot deletion of location data the app has already stored.
enum LocationPrivacy {
    /// Clears the saved coordinates from every stored fill-up **and** every
    /// pending submission, leaving the records themselves and all their other
    /// fields untouched. Returns how many records were changed, for a
    /// confirmation message.
    ///
    /// Irreversible: the coordinates are gone once the context saves.
    @MainActor
    @discardableResult
    static func purgeSavedLocations(in context: ModelContext) -> Int {
        var cleared = 0

        let entries = (try? context.fetch(FetchDescriptor<FuelEntry>())) ?? []
        for entry in entries where entry.latitude != nil || entry.longitude != nil {
            entry.latitude = nil
            entry.longitude = nil
            cleared += 1
        }

        let submissions = (try? context.fetch(FetchDescriptor<PendingFillUp>())) ?? []
        for submission in submissions where submission.latitude != nil || submission.longitude != nil {
            submission.latitude = nil
            submission.longitude = nil
            cleared += 1
        }

        return cleared
    }
}
