# Accessibility

What FuelTracker supports, how it's verified, and what still needs a device.

The first accessibility pass ([#33]) landed VoiceOver labels, Dynamic Type,
Reduce Motion support, and spoken chart summaries. It deferred four items that
needed a device or the Accessibility Inspector; [#63] finished three of them and
turned the fourth into the checklist at the bottom of this file.

## What's supported

| Feature | Status | Where it lives |
|---|---|---|
| VoiceOver labels & values | Supported | Per-view `.accessibilityLabel` / `.accessibilityValue`; `KPI.accessibilityLabel`, `ShowdownRow.accessibilityLabel` |
| Spoken chart summaries | Supported | `ChartAccessibility.summary` — range, average, latest, direction |
| **Chart audio graphs** | Supported | `ChartAudioGraphData` + `MetricChartDescriptor` |
| Dynamic Type incl. accessibility sizes | Supported | `KPICard` and forms reflow at `isAccessibilitySize` |
| **Contrast (WCAG 2.2 AA)** | Supported | `AccessiblePalette` |
| Differentiate without color | Supported | The showdown states its winner in words; capsules carry text, not just tint |
| Reduce Motion | Supported | Animations gated on the environment flag |
| Dark interface | Supported | Every surface is a semantic or scheme-resolved color |
| Voice Control | **Unverified** | Needs a device pass — see the checklist |

## Chart audio graphs

VoiceOver can play a chart as sound, so the shape of a trend is available
without sight. The line and bar charts adopt `AXChartDescriptor` through
`ChartAudioGraph`.

The design point worth knowing: **the descriptor is built from plain data.**
`ChartAudioGraphData` holds no `AXChartDescriptor` and imports no Accessibility
framework, so the part that can actually be wrong — which samples survive, what
the axis bounds are — is unit-tested without a simulator. Only the thin bridge
(`MetricChartDescriptor`) is platform-bound, and it's `#if os(iOS)` because
audio graphs don't exist on watchOS.

Three behaviors that are deliberate rather than incidental:

- **Non-finite values are dropped, not clamped.** A `NaN` MPG is missing data;
  placing a tone for it would put sound where the user's finger says there's no
  reading. An infinite bound would make the whole axis meaningless.
- **A series with nothing usable produces no audio graph at all**, rather than an
  empty one. Silence from a broken descriptor is indistinguishable from a bug;
  the per-mark labels and the spoken summary still work.
- **A flat series still gets a playable axis.** Every fill-up at the same price
  is real data, but a zero-width range has nowhere to put a tone, so the range
  is padded — proportionally, except at exactly zero, where a proportion of zero
  is still zero and a fixed pad is used.

## The contrast audit

Measured against the app's own card background, **before** any change:

| Hue | Light | Dark |
|---|---|---|
| orange | **2.20:1** | 8.28:1 |
| teal | **2.57:1** | 8.55:1 |
| green | **2.22:1** | 8.42:1 |
| blue | **4.02:1** | 4.66:1 |
| purple | **4.13:1** | 4.83:1 |

Every hue failed WCAG 2.2 AA's 4.5:1 for text in light mode. Orange, teal and
green failed even the looser **3:1** that WCAG 1.4.11 sets for chart marks and
other non-text graphics — so the lines and bars themselves were non-compliant,
not just the labels. Dark mode was already fine: the dark variants are brighter
against a near-black background.

Two pairings were worse than the table suggests, because the label sits on a
tint wash of its own color rather than on the plain card:

- `.orange` on a 15% orange capsule, light: **1.95:1**
- `.blue` on a 15% blue capsule, light: **3.30:1**
- the same two in **dark** mode: 6.22:1 (fine) and **3.90:1** (fails)

### The fix

`AccessiblePalette` replaces the stock palette. Light values are darkened
versions of Apple's; dark values are Apple's own except blue and purple, which
were brightened to clear the capsule case. Hue and saturation are preserved and
only brightness moves, so "blue means fuel economy" still reads across screens.

Every color clears **4.7:1** — margin over the 4.5 requirement — against all
three surfaces it can land on: the card, the grouped background, and its own
tint wash. The measured worst case anywhere in the palette is **4.80:1**, on
light-mode teal against its own wash.

| Hue | Light: card / grouped / wash | Dark: card / grouped / wash |
|---|---|---|
| blue | 6.05 / 5.42 / **4.82** | 6.04 / 7.45 / **4.81** |
| orange | 5.96 / 5.34 / **4.81** | 8.28 / 10.22 / 6.24 |
| purple | 5.99 / 5.37 / **4.81** | 6.04 / 7.46 / **4.82** |
| teal | 5.95 / 5.33 / **4.80** | 8.55 / 10.56 / 6.38 |
| green | 5.98 / 5.36 / **4.82** | 8.42 / 10.39 / 6.35 |

### The wash is the constraint, and it's self-referential

The bolded column is the binding one in every case, and it has a trap in it. The
tint wash is 15% of *the palette's own value* over the card — so darkening a
color to fix its contrast also darkens the background it's being measured
against. The pair moves together, and the ratio against the wash climbs far more
slowly than the ratio against the card.

Derive a candidate against a wash mixed from **Apple's** color instead and the
numbers look fine while the app renders something ~0.35 short: the first attempt
at this table cleared the card at 5.37:1 and failed the capsule at 4.37:1. CI
caught it. `ContrastTests.theTintWashIsMixedFromThePaletteItself` now pins the
recursion so a re-derivation can't quietly optimize the looser constraint.

**This is enforced, not asserted.** Colors are stored as components rather than
as `Color` values specifically so the ratios can be recomputed; `ContrastTests`
does exactly that on every CI run — against both the 4.5 standard *and* the
palette's own 4.7 margin — and a palette edit that drops below either bar fails
the build. `ContrastTests` also keeps a test proving Apple's stock values *would*
fail, so a future "simplification" back to `.orange` has a reason not to.

## Still needs a device

Two things genuinely cannot be checked in CI or on a Linux authoring box. Both
want a real device with VoiceOver on.

### Accessibility Inspector audit

Run Xcode → Open Developer Tool → Accessibility Inspector, point it at the
running app, and use the audit button on each screen:

- [ ] Dashboard (populated, and the empty/welcome state)
- [ ] Fill-ups list, including the search/filter bar
- [ ] Add/edit fill-up form
- [ ] Vehicles list and the add-vehicle sheet
- [ ] Showdown
- [ ] Settings (all sections)
- [ ] Onboarding / welcome
- [ ] Pump, odometer, and receipt scanners
- [ ] Review queue for shared submissions

Watch for: hit targets under 44×44pt, images without labels, elements missing
traits, and text that clips instead of wrapping at the largest Dynamic Type size.

### Audio graph and Voice Control

- [ ] With VoiceOver on, focus a chart and confirm the audio graph plays and the
      "Describe Chart" / audio graph option appears.
- [ ] Confirm the announced title distinguishes the two distance charts
      ("Odometer" vs "Monthly Distance").
- [ ] Turn on Voice Control and confirm every interactive control can be reached
      by name, then update the Voice Control row above.

## App Store Accessibility Nutrition Label

Draft declarations for the listing, to be confirmed against the device pass
before submission. This pairs with the privacy disclosures in
[`privacy.md`](privacy.md).

| Declaration | Claim | Basis |
|---|---|---|
| VoiceOver | Yes | Labels/values throughout; audio graphs on charts |
| Larger Text | Yes | Dynamic Type through accessibility sizes, with reflow |
| Sufficient Contrast | Yes | `AccessiblePalette`, CI-enforced at 4.5:1+ |
| Differentiate Without Color | Yes | Winners and states are stated in text |
| Reduced Motion | Yes | Honors the system setting |
| Dark Interface | Yes | Full light/dark support |
| Captions | Not applicable | No audio or video content |
| Audio Descriptions | Not applicable | No video content |
| Voice Control | **Hold** | Claim only after the device pass above |

Claim nothing that hasn't been verified — an inaccurate accessibility label is
worse than an absent one, because it sends someone who depends on the feature
into an app that doesn't deliver it.

[#33]: https://github.com/kja031199/FuelTrackingApp/issues/33
[#63]: https://github.com/kja031199/FuelTrackingApp/issues/63
