import Foundation

/// The app's dashboard metrics and their fixed hues.
///
/// Color follows the metric everywhere — KPI tiles and charts, iPhone and
/// watch — so a reader can connect "blue" to fuel economy across screens.
///
/// This file is deliberately **Foundation-only**. Resolving a hue to an actual
/// `Color` needs SwiftUI, so it lives in `Metric+Color.swift`; keeping the two
/// apart means `KPI` — which carries a `Metric` — stays a pure value type, and
/// the whole statistics layer can be reasoned about (and ported) without a UI
/// framework in scope. `AccentHue` itself is a plain string enum, though it is
/// declared next to the palette that consumes it in `AccessiblePalette.swift`.
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
