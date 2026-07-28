import SwiftUI

/// The app's dashboard metrics and their fixed colors.
///
/// Color follows the metric everywhere — KPI tiles and charts, iPhone and
/// watch — so a reader can connect "blue" to fuel economy across screens.
enum Metric {
    case economy
    case price
    case spending
    case distance

    /// The metric's hue. Resolving it to an actual `Color` goes through
    /// ``AccessiblePalette``, which picks a value meeting WCAG 2.2 AA for the
    /// current color scheme — Apple's stock `.orange` and `.teal` are far too
    /// light against a white card to be readable as text.
    var hue: AccentHue {
        switch self {
        case .economy: .blue
        case .price: .orange
        case .spending: .purple
        case .distance: .teal
        }
    }

    /// A contrast-safe color for this metric.
    ///
    /// Takes the scheme explicitly rather than reading the environment itself,
    /// so it can be called from inside `Chart` builders and from tests. Callers
    /// hold `@Environment(\.colorScheme)` and pass it down.
    func color(in scheme: ColorScheme) -> Color {
        AccessiblePalette.color(hue, in: scheme)
    }

    /// Name VoiceOver falls back to when a chart isn't given a specific title.
    var accessibilityName: String {
        switch self {
        case .economy: "Fuel economy"
        case .price: "Gas price"
        case .spending: "Spending"
        case .distance: "Distance"
        }
    }
}
