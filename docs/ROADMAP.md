# FuelTracker Roadmap

> ## 🧊 Closed — this roadmap is a record, not a plan
>
> Development moved to
> **[fueltracker-web](https://github.com/kja031199/fueltracker-web)** in
> September 2026. Nothing below Phase 1 will be built *here*; several items were
> built *there* instead, and the rest were closed as no longer worth doing on a
> frozen iOS app.
>
> The reason is in Phase 3 below, unchanged: every remaining item was gated on a
> paid Apple Developer account. Rewriting for the browser removed the gate
> rather than paying it.
>
> | Was | Became |
> |---|---|
> | Phase 2 — **export (#64)** | Shipped on the web: CSV **and** JSON, with an export→wipe→restore round trip verified in a real browser. No PDF |
> | Phase 2 — reminders, EV, maintenance, tagging (**#65–#68**) | Still unbuilt. Carried over to the web repo's issues; closed here |
> | Phase 3 — **"Ship it"** entirely | Dissolved. Publishing a web app is a URL |
> | Phase 3 — **iCloud sync** | Deliberately *not* rebuilt. The web app is local-first: no account, no server, nothing uploaded |
> | Phase 3 — **#24 shareable link** | Unblocked but unbuilt. On the web a URL *is* the transport, and the submit→review→approve data layer is already ported |
> | Phase 4 — **#42 widget / App Intents** | Closed. The web app is an installable PWA, which is the equivalent affordance |
>
> What the rewrite did **not** reproduce is listed in the README above:
> live pump scanning, the watch app, encryption at rest, and the Face ID lock.
> Those remain reasons to build this version.

Where the app was, and where it was going. Kept as written, for the record.

## Where we are

Version 1 is feature-complete on a **free personal Apple ID** (entitlements ship
empty, everything on-device). Shipped: vehicles + fill-ups through the
`FuelEntryDraft` write chokepoint; statistics (MPG segments, cost/mile, price and
odometer trends, monthly rollups, weekday patterns, two-vehicle showdown);
camera scanning (pump / receipt / odometer OCR) and a receipt vault;
missed-fill-up detection; **international units**; **search & filter**;
**onboarding**; **at-rest data protection + optional app lock**; **location
privacy controls**; a **privacy policy + App Store disclosure checklist**; a
**DocC catalog**; and an Apple Watch app — all backed by an extensive
hostile-input test suite.

## Guiding constraints

- **Entitlements stay empty** so the free-account build keeps working. Anything
  needing iCloud, App Groups, or Push is gated and deferred (see
  `ARCHITECTURE.md` → Invariants).
- **On-device and private** by default; no server, no analytics, no third-party
  SDKs.
- Writes go through `FuelEntryDraft`; models stay CloudKit-shaped; hostile-input
  testing is the bar.

## Direction

The plan, in order: **(1) infra & quality first, then (2) deepen the core while
staying on the free account.** Paid-account features come later, only if the app
heads toward the App Store.

---

## Phase 1 — Infrastructure & quality *(essentially complete)*

Make the foundation trustworthy before adding more surface.

- **CI on every PR** — [#62](https://github.com/kja031199/FuelTrackingApp/issues/62).
  A GitHub Actions macOS runner that builds and runs the suite on the iOS
  Simulator for each PR. Closes the "written but not executed here — run ⌘U
  before merge" gap that has shadowed every change. **No paid account needed**
  (Simulator builds don't require signing). Highest-leverage item on the board.
- **Finish deferred accessibility** —
  [#63](https://github.com/kja031199/FuelTrackingApp/issues/63) *(done, bar the
  device pass)*. Chart audio graphs and a WCAG 2.2 AA contrast fix shipped, along
  with a drafted Accessibility Nutrition Label. The per-screen Accessibility
  Inspector audit and the Voice Control check genuinely need hardware; they're a
  checklist in [`accessibility.md`](accessibility.md).

## Phase 2 — Deepen the core *(free-account-safe)*

Higher-value features that need no entitlements.

- **Data export (CSV + PDF)** —
  [#64](https://github.com/kja031199/FuelTrackingApp/issues/64). Get data out;
  also a hedge for the sync-off local build.
- **Fuel-log reminders** —
  [#65](https://github.com/kja031199/FuelTrackingApp/issues/65). Opt-in local
  notifications so histories stay complete. No server.
- **EV / hybrid support** —
  [#66](https://github.com/kja031199/FuelTrackingApp/issues/66). Log kWh +
  charging cost and electric efficiency. The biggest forward-looking product
  direction — a large, staged change.
- **Maintenance / service log** —
  [#67](https://github.com/kja031199/FuelTrackingApp/issues/67). Oil, tires,
  registration — from fuel tracker toward car tracker.
- **Trip / purpose tagging** —
  [#68](https://github.com/kja031199/FuelTrackingApp/issues/68). Business vs.
  personal, turning the app into a light mileage/expense tool.

## Phase 3 — Ship it *(requires a paid Apple Developer account)*

Deferred until (and if) the app heads to the App Store. A paid membership
(≈ $99/yr) is required for App Store distribution **and** unblocks the
capabilities below at once.

- **Enable iCloud sync** — already fully wired; activate the entitlement.
- **Shareable fill-up link** —
  [#24](https://github.com/kja031199/FuelTrackingApp/issues/24) *(blocked —
  needs CloudKit)*. The local submit → review → approve foundation already
  shipped; only the CloudKit sharing transport remains.
- **Home-screen widget + App Intents** —
  [#42](https://github.com/kja031199/FuelTrackingApp/issues/42) *(blocked —
  needs an App Group)*.
- **App Store prep** — marketing screenshots, listing copy, TestFlight beta, and
  the privacy/accessibility labels already drafted.
- **Localization** — translate UI strings to match the international units work.

## Phase 4 — Platform & bigger bets *(later)*

- iPad multi-column layout, Apple Watch complications, CarPlay, deeper Siri /
  Shortcuts.
- Live/interactive chart refinements.
- Larger directions to evaluate on their own merits: fuel-price data integration
  (would introduce a third-party data source and change the privacy posture),
  and any move beyond family/private sharing.

---

## How this maps to the board

- **Phase 1** issues are labeled `priority: high`; **Phase 2** `priority: medium`.
- **Blocked** items ([#24](https://github.com/kja031199/FuelTrackingApp/issues/24),
  [#42](https://github.com/kja031199/FuelTrackingApp/issues/42)) carry a
  `blocked` label with the specific prerequisite.
- Update this file when priorities shift or a phase completes.
