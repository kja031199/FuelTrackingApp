import Foundation

/// Search + filter criteria for the fill-up list.
///
/// Pure and value-typed so the matching logic is unit-tested. The view owns the
/// state and applies it to the selected vehicle's already-loaded fill-ups — a
/// single in-memory pass over one vehicle's history, which is both simpler and
/// safer than a dynamic `#Predicate`, and keeps statistics (computed over the
/// full history elsewhere) unaffected by what the list is showing.
struct FillUpFilter: Equatable {
    /// Free text matched against station name and notes (case-insensitive).
    var searchText: String = ""
    /// Only fill-ups on or after this range's cutoff. `.all` means no limit.
    var range: DashboardTimeRange = .all
    /// Restrict to one fuel grade, or nil for any.
    var fuelGrade: FuelGrade?
    /// Restrict to one station name, or nil for any.
    var station: String?

    /// Whether any constraint is set — drives the "filters active" indicator.
    var isActive: Bool {
        !trimmedSearch.isEmpty || range != .all || fuelGrade != nil || station != nil
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The entries matching every active constraint, preserving input order.
    func apply(to entries: [FuelEntry], now: Date = .now) -> [FuelEntry] {
        let query = trimmedSearch
        let cutoff = range.cutoff(from: now)
        return entries.filter { entry in
            matchesSearch(entry, query: query)
                && (cutoff.map { entry.date >= $0 } ?? true)
                && (fuelGrade.map { entry.fuelGrade == $0 } ?? true)
                && (station.map { entry.station == $0 } ?? true)
        }
    }

    private func matchesSearch(_ entry: FuelEntry, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return entry.station.localizedCaseInsensitiveContains(query)
            || entry.notes.localizedCaseInsensitiveContains(query)
    }
}
