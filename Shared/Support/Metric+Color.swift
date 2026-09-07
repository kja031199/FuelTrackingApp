import SwiftUI

/// The one part of ``Metric`` that needs a UI framework.
///
/// Split out so `Metric` itself — and therefore `KPI`, which carries one —
/// stays Foundation-only. See the note in `Metric.swift`.
extension Metric {
    /// A contrast-safe color for this metric.
    ///
    /// Takes the scheme explicitly rather than reading the environment itself,
    /// so it can be called from inside `Chart` builders and from tests. Callers
    /// hold `@Environment(\.colorScheme)` and pass it down.
    func color(in scheme: ColorScheme) -> Color {
        AccessiblePalette.color(hue, in: scheme)
    }
}
