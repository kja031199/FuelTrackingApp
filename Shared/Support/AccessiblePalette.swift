import Foundation
import SwiftUI

/// The app's accent hues.
///
/// Named here rather than taken straight from SwiftUI's standard palette so
/// their contrast can be *guaranteed* — see ``AccessiblePalette``.
enum AccentHue: String, CaseIterable, Sendable {
    case blue
    case orange
    case purple
    case teal
    case green
}

/// An sRGB color as plain components.
///
/// Colors are declared as numbers, not as `Color.orange`, for one reason: a
/// `Color` is opaque — you cannot read channels back out of it, so its contrast
/// can't be checked. Components can, which is what lets `AccessibilityTests`
/// assert the WCAG ratios on every CI run instead of trusting a one-time audit.
struct RGBComponents: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

/// Accent colors that meet **WCAG 2.2 AA** as text (4.5:1) on the backgrounds
/// this app actually draws them on, in both light and dark mode.
///
/// ## Why not just use `.orange`, `.blue`, …
///
/// Apple's standard palette is tuned to look right, not to pass a contrast
/// threshold, and its light-mode values are bright. Measured against the app's
/// own card background before this existed:
///
/// | hue    | light  | dark  |
/// |--------|--------|-------|
/// | orange | 2.20:1 | 8.28:1 |
/// | teal   | 2.57:1 | 8.55:1 |
/// | green  | 2.22:1 | 8.42:1 |
/// | blue   | 4.02:1 | 4.66:1 |
/// | purple | 4.13:1 | 4.83:1 |
///
/// Every one of them fails 4.5:1 in light mode — orange, teal and green fail
/// even the looser 3:1 bar that WCAG 1.4.11 sets for chart marks and other
/// non-text graphics. Dark mode was already fine, because the dark variants are
/// brighter against a near-black background.
///
/// So the light values here are darkened versions of Apple's, and the dark
/// values are Apple's own except for blue and purple, which were brightened:
/// on a 15%-tint capsule (`.blue` text on a `.blue` wash) they came to 3.90:1
/// and 4.03:1, short of the bar.
///
/// Hue and saturation are preserved; only brightness moves, so "blue means fuel
/// economy" still reads across screens.
///
/// ## The tint wash is self-referential — mind this when re-deriving values
///
/// The tightest pairing in the app is a hue as text on a 15% wash **of itself**
/// (see ``tintedBackground(_:in:)``). That wash is composited from *this table's*
/// value, not from Apple's original, so darkening the ink darkens its own
/// background too and the pair moves together. Contrast therefore rises far more
/// slowly against the wash than against the card, and the wash is always the
/// binding constraint.
///
/// Deriving a candidate against a wash mixed from Apple's stock color solves the
/// wrong problem: it looks like it clears the bar and lands ~0.35 short. That
/// mistake shipped once and was caught only by CI. Any re-derivation must mix
/// the wash from the **candidate itself**.
///
/// ## The guarantee
///
/// Each color clears ``minimumTextContrast`` against all three surfaces it can
/// land on: the card background, the grouped background, and its own 15% tint
/// wash. Every value in the table is at **4.80:1 or better**, so the margin
/// isn't a hair's breadth. `AccessibilityTests` recomputes all of it from the
/// components below — against both the 4.5 standard and this internal margin —
/// so a palette edit that breaks the promise fails CI.
enum AccessiblePalette {
    /// Opacity of the tint wash behind capsule/banner labels.
    static let tintOpacity: Double = 0.15

    /// The minimum ratio the palette is held to. WCAG 2.2 AA requires 4.5:1 for
    /// body text; the extra is headroom so a small future tweak doesn't
    /// silently land a hair under.
    static let minimumTextContrast: Double = 4.7

    static func components(_ hue: AccentHue, in scheme: ColorScheme) -> RGBComponents {
        scheme == .dark ? dark(hue) : light(hue)
    }

    static func color(_ hue: AccentHue, in scheme: ColorScheme) -> Color {
        components(hue, in: scheme).color
    }

    /// `secondarySystemGroupedBackground` — the card surface most labels sit on.
    static func cardBackground(in scheme: ColorScheme) -> RGBComponents {
        scheme == .dark
            ? RGBComponents(red: 0.1098, green: 0.1098, blue: 0.1176)   // #1C1C1E
            : RGBComponents(red: 1, green: 1, blue: 1)                  // #FFFFFF
    }

    /// `systemGroupedBackground` — the page behind the cards.
    static func groupedBackground(in scheme: ColorScheme) -> RGBComponents {
        scheme == .dark
            ? RGBComponents(red: 0, green: 0, blue: 0)                        // #000000
            : RGBComponents(red: 0.9490, green: 0.9490, blue: 0.9686)         // #F2F2F7
    }

    /// The tint wash actually rendered behind a capsule: the hue at
    /// ``tintOpacity`` composited over the card background.
    ///
    /// Note the recursion — the wash is mixed from the palette's *own* value for
    /// `hue`, which is why it's the binding constraint on the table above.
    static func tintedBackground(_ hue: AccentHue, in scheme: ColorScheme) -> RGBComponents {
        let fg = components(hue, in: scheme)
        let bg = cardBackground(in: scheme)
        func mix(_ f: Double, _ b: Double) -> Double {
            f * tintOpacity + b * (1 - tintOpacity)
        }
        return RGBComponents(
            red: mix(fg.red, bg.red),
            green: mix(fg.green, bg.green),
            blue: mix(fg.blue, bg.blue)
        )
    }

    // MARK: - WCAG math

    /// Relative luminance, per the WCAG 2.2 definition.
    static func relativeLuminance(_ c: RGBComponents) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue)
    }

    /// Contrast ratio between two colors, from 1:1 (identical) to 21:1
    /// (black on white). Order doesn't matter.
    static func contrastRatio(_ a: RGBComponents, _ b: RGBComponents) -> Double {
        let first = relativeLuminance(a)
        let second = relativeLuminance(b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    // MARK: - The values

    private static func light(_ hue: AccentHue) -> RGBComponents {
        switch hue {
        case .blue:   RGBComponents(red: 0.0000, green: 0.3725, blue: 0.7843) // #005FC8
        case .orange: RGBComponents(red: 0.5725, green: 0.3333, blue: 0.0000) // #925500
        case .purple: RGBComponents(red: 0.5490, green: 0.2549, blue: 0.6941) // #8C41B1
        case .teal:   RGBComponents(red: 0.1176, green: 0.4275, blue: 0.4824) // #1E6D7B
        case .green:  RGBComponents(red: 0.1176, green: 0.4471, blue: 0.2000) // #1E7233
        }
    }

    private static func dark(_ hue: AccentHue) -> RGBComponents {
        switch hue {
        case .blue:   RGBComponents(red: 0.2314, green: 0.6157, blue: 1.0000) // #3B9DFF
        case .orange: RGBComponents(red: 1.0000, green: 0.6235, blue: 0.0392) // #FF9F0A
        case .purple: RGBComponents(red: 0.8118, green: 0.4431, blue: 1.0000) // #CF71FF
        case .teal:   RGBComponents(red: 0.2510, green: 0.7843, blue: 0.8784) // #40C8E0
        case .green:  RGBComponents(red: 0.1882, green: 0.8196, blue: 0.3451) // #30D158
        }
    }
}
