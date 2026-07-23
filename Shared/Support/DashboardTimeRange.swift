import Foundation

/// A relative time window. Shared by the dashboard's range picker and the
/// fill-up list's date filter so the two stay consistent.
enum DashboardTimeRange: String, CaseIterable, Identifiable {
    case threeMonths = "3M"
    case sixMonths = "6M"
    case year = "1Y"
    case all = "All"

    var id: String { rawValue }

    /// The earliest date this range includes, or nil for "all time".
    var cutoff: Date? { cutoff(from: .now) }

    /// The cutoff relative to a supplied `now`, so callers (and tests) can pin
    /// the reference point instead of depending on the wall clock.
    func cutoff(from now: Date) -> Date? {
        let calendar = Calendar.current
        switch self {
        case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: now)
        case .sixMonths: return calendar.date(byAdding: .month, value: -6, to: now)
        case .year: return calendar.date(byAdding: .year, value: -1, to: now)
        case .all: return nil
        }
    }
}
