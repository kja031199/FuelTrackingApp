# CLAUDE.md

Operating manual for an AI assistant working in this repo. Claude Code loads
this automatically at the start of a session. Read it before making changes —
it captures the things that are expensive to rediscover and easy to get wrong.

It overlaps with [`CONTRIBUTING.md`](CONTRIBUTING.md) (human-facing) and
[`ARCHITECTURE.md`](ARCHITECTURE.md) (the *why*). This file is the terse "how to
operate here" version. When they conflict, `ARCHITECTURE.md` wins on structure.

## What this is

FuelTracker is a Fuelly-style iOS + watchOS app for logging gas fill-ups and
tracking fuel economy and cost, built with SwiftUI + SwiftData (CloudKit-ready).
There is no server — everything is on-device, optionally synced through the
user's private iCloud.

**Pointer map** (details in `ARCHITECTURE.md`):

- `Shared/` — compiled into **both** apps. Models, statistics, parsers, form
  logic, formatters. No UIKit/Vision/ImageIO/MapKit here.
- `Shared/Models/` — `Vehicle`, `FuelEntry`, `FuelGrade`, `PendingFillUp`, and
  **`FuelEntryDraft`** (the single write chokepoint).
- `Shared/Statistics/` — `FuelStatistics` (MPG/cost math), `VehicleShowdown`,
  `WeekdayPricePattern`, `KPI`.
- `Shared/Scanning/` — pure OCR-text→value parsers (pump, odometer, receipt).
- `Shared/Support/` — formatters, `FillUpFormModel`, `ModelContainerFactory`,
  the units system (`MeasurementUnits`, `UnitSettings`), privacy/security
  (`PrivacySettings`, `LocationPrivacy`, `StoreProtection`, `AppLock`), the
  list search/filter (`FillUpFilter`, `DashboardTimeRange`), the first-run
  gate (`OnboardingGate`), the stats memo (`FuelStatisticsMemo`), and the
  contrast-safe colours (`AccessiblePalette`, `Metric`).
- `FuelTracker/` — the iPhone app (thin views) + iOS-only `Scanning/` importers
  and `Services/` (Vision, ImageIO, CoreLocation/MapKit, PhotosUI).
- `FuelTrackerWatch/` — the watch app (thin views).
- `FuelTrackerTests/` — Swift Testing unit + rendering tests.
- `Shared/Views/` — the shared chart components (`MetricCharts`) and their
  accessibility layers (`ChartAccessibility` spoken summaries,
  `ChartAudioGraph` audio graphs).
- `FuelTracker/FuelTracker.docc/` — DocC catalog (domain essays + curated
  symbol docs); build with ⌃⌘D. Keep the essays in sync when the MPG or
  scanning logic changes.

## Environment reality — read this first

**This environment has no Xcode and cannot build or run the iOS/watchOS test
suite.** It's Linux; there is no `xcodebuild`, no simulator, no Swift toolchain
that links UIKit/SwiftData.

Consequences:

- **You cannot run the tests here.** Verify changes by careful review, by
  tracing the logic, and by a brace/paren/bracket **balance check** on every
  file you touch, e.g.:
  ```bash
  python3 -c "s=open('PATH').read(); print({k:s.count(a)-s.count(b) for k,a,b in [('()','(',')'),('[]','[',']'),('{}','{','}')]})"
  ```
- **Never claim the tests passed.** You didn't run them. **CI does** — a macOS
  runner builds and tests every PR (`.github/workflows/ci.yml`), and that check
  is the authority. In the PR body, point at CI rather than asserting a result.
- Balance checks catch mismatched delimiters, not type errors. Read the code you
  write as if compiling it in your head — CI is the backstop, not a substitute
  for writing code that compiles.

### What CI actually costs, and how not to waste it

`.github/workflows/ci.yml` runs on a **macOS** runner, which bills at a **10x
multiplier** against a private repo's monthly Actions allowance — roughly **200
macOS minutes/month**. Treat every run as expensive:

- **Batch your pushes.** `concurrency: cancel-in-progress: true` means a second
  push to the same branch cancels the in-flight run and starts over, throwing
  away everything it had already billed. Push once, then wait. Do **not** push a
  "small extra fix" while a run is in flight.
- **Measured shape of a healthy run:** build ≈ **60 seconds**, suite runs in
  seconds. If a run takes 20+ minutes, it is *hung*, not slow — read the
  timestamps in the log before tuning compiler flags. (An earlier round of
  tuning chased a "20-minute build" that a timestamped log disproved.)
- The job is capped at 20 minutes with tighter per-step timeouts, so a hang
  fails fast and names the step it died in.
- Tests run **serially** (`-parallel-testing-enabled NO`): the suite is short and
  main-actor-bound, so parallel workers buy nothing and only interleave the
  output. With one worker, the last test named in the log is the one that stuck.
- Docs-only changes are skipped via `paths-ignore`. Because skipped runs report
  no status, don't make this a *required* check while that's in place.

### The cheap Linux checks — `.github/workflows/checks.yml`

Three jobs on `ubuntu-latest` at **1x** billing, parallel and independent:
**gitleaks** (secret scan), **SwiftLint** (lint), **lychee** (Markdown links).
Deliberately no `paths-ignore` — they're cheap, and a docs change is exactly when
the link check matters. They always report a status, so unlike `ci.yml` these are
the ones that can be *required* checks.

You **can** run all three in this environment, unlike the iOS suite. Their
Linux binaries download and execute here:

```bash
gitleaks git . --config .gitleaks.toml --redact --no-banner --verbose
lychee --offline --no-progress --include-fragments '**/*.md'
```

**SwiftLint is the exception — it cannot run here.** The standalone
`swiftlint_linux.zip` binary starts but dies with `Loading
libsourcekitdInProc.so failed`: every rule needs SourceKit, which ships with a
Swift toolchain, and `download.swift.org` plus container blob registries are both
blocked by the proxy (the tags/manifest API is reachable; blobs 403). So
`.swiftlint.yml` is the one config whose first CI run is its real proof.

That's why it uses **`only_rules`** — an explicit allowlist rather than the
default set minus exclusions. Every rule in it was verified to read zero by
grepping all 80 Swift files, which is what makes `--strict` safe, and it means a
SwiftLint version bump can't introduce a new rule and redden the branch. The file
also records what was left out **with measured counts** (`force_unwrapping`: 59
hits, 56 in tests; `line_length`: 58 lines over 120, mostly UI copy;
`file_length`: the longest files are test files that should grow). Read those
notes before re-measuring.

When adding a rule you can't execute, verify it by grep first and say in the PR
that CI is the proof — the same discipline as the Swift code.

**Check the grep before trusting a zero.** A rule was added to the allowlist on
the strength of a grep that returned zero and CI then found four violations. The
cause: `[A-Za-z0-9_<>,\[\] ]` looks like a character class containing brackets,
but POSIX brackets don't take backslash escapes — the class ends at the first
`]`, and the rest becomes literal. A silently-wrong pattern reads exactly like a
clean codebase. **A zero result is a claim; prove it by inverting the pattern**
and confirming it matches something you know exists:

```bash
# Trust a "0 hits" only after the same regex finds the case you planted.
grep -rnE '(var|let)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[^=]*\?[[:space:]]*=[[:space:]]*nil' .
```

**Container jobs get `sh`, not bash.** The SwiftLint job runs inside
`ghcr.io/realm/swiftlint`, which ships no bash, so Actions falls back to
`sh -e {0}` — dash. `set -euo pipefail` dies there with `Illegal option -o
pipefail` *before running the step's real command*, which reads like a lint
failure but isn't one. Don't add `set -euo pipefail` to a step running in a
container unless you know that image has bash; `-e` is already applied by the
default shell. The `secrets` and `links` jobs run directly on the runner, where
bash exists, so they keep it.

## The workflow — follow this for every change

Every piece of work runs through four role phases, in order. Wear each hat
deliberately; don't collapse them. "If applicable" means skip a step only when
it genuinely can't apply (e.g. no tests for a docs-only change), not when it's
merely inconvenient.

**1. Lead Software Engineer**
1. Receive the request.
2. If it maps to a repo issue, find it and read the issue and its linked docs
   through — don't reconstruct the requirements from memory.
3. Plan and reason through the change *before* editing: what files, what
   invariants are in play, what could break.
4. Create a new branch (restart from the latest `main` after a merge).
5. Make the changes.

**2. Lead QA Developer (author tests)**
1. Add happy-path test cases in the same branch.
2. Add non-happy-path cases: zero/negative/non-finite values, duplicates, clock
   skew, OCR noise, oversized/garbage payloads — the hostile-input bar.

**3. Senior Technical Writer**
1. Update `CONTRIBUTING.md` for the new/changed behavior and conventions.
2. Update `CLAUDE.md` for the same (invariants, gotchas, pointers).

**4. Lead QA Developer (final review)**
1. Review the tests against the diff — confirm they cover the new, updated, and
   otherwise changed code as fully as possible.
2. Compare the actual changes against the originating issue **and** the user's
   request, and confirm the work matches what was asked. Note any gaps.

Then run the balance check on every touched file, and open the PR (only when
asked) — CI runs the suite on it, so point at that check instead of claiming a
test result.

## Hard invariants — do not break these

These are load-bearing; breaking one stops a target compiling or re-opens a
closed security issue. Full list in `ARCHITECTURE.md` → Invariants.

1. **Writes go through `FuelEntryDraft`.** Every new/edited `FuelEntry` is built
   from a `FuelEntryDraft` (failable init requires positive, finite odometer /
   gallons / price; owns the field mapping). Never `context.insert` a hand-built
   `FuelEntry`. New input sources (imports, intents, shared submissions) build a
   draft too.
2. **Models stay CloudKit-shaped.** Every `@Model` attribute has a default
   value, relationships are optional, no unique constraints. New model → add it
   to `ModelContainerFactory.schema` **and** update the schema-names test in
   `SharedLogicTests`.
3. **Entitlements stay empty.** The app must keep building on a free personal
   Apple ID. Don't commit populated entitlements or add iCloud/App Group/Push
   capabilities that break the local build — gate the feature and document the
   prerequisite (see the README's iCloud-sync section for the pattern).
4. **`Shared/` imports no UIKit/Vision/ImageIO/MapKit.** Those aren't available
   on watchOS. Image/camera/location work is iOS-only, under `FuelTracker/`.
5. **Untrusted images use the bounded decode** (`ReceiptImage`), never raw
   `UIImage(data:)`. Persist only re-encoded, size-bounded data.

## Adding files (Xcode 16)

The project uses `PBXFileSystemSynchronizedRootGroup` sync roots
(`FuelTracker`, `FuelTrackerWatch`, `Shared`, `FuelTrackerTests`). Files placed
under those folders are **included automatically** — you do **not** edit
`project.pbxproj` to add a source file. Just create the file in the right
directory. Respect the `Shared/` framework rule when choosing where it goes.

## Git & PR workflow

- Develop on the session's designated feature branch. **One PR per branch.**
- After a PR merges, restart the branch from the latest `main`
  (`git fetch origin main && git checkout -B <branch> origin/main`) rather than
  stacking on merged history. If a follow-up commit was pushed *after* the PR
  merged, it needs its **own new PR** — rebase it onto the merged `main` first.
- Force-push only with `--force-with-lease`, and only when the branch contains
  just already-merged history.
- Commit messages end with the required trailers the harness specifies
  (`Co-Authored-By:` and `Claude-Session:`). **Never** put the raw model
  identifier, secrets, tokens, or internal hostnames in commits, PRs, code, or
  these docs.
- Only open a PR when asked. Check for a PR template before writing the body.

## Testing conventions

- **Swift Testing**, not XCTest: `@Test`, `#expect`, `#require`,
  `@MainActor struct` suites. In-memory store via
  `ModelContainerFactory.makeInMemory()`.
- **Hostile-input testing is expected.** Don't submit only happy-path tests —
  cover zero/negative/non-finite values, duplicates, clock skew, OCR noise,
  oversized/garbage payloads. The bar: never crash, never divide by zero, never
  fabricate a statistic. See `HostileInputTests` and `SecurityHardeningTests`.
- **View rendering:** the `render(...)` harness and its `Scenario` helpers are
  `private` to `ViewRenderingTests.swift`. New view render tests must be added
  **inside that file** to reach them.
- **Tests never touch real device services.** The render harness defaults to
  `StubAuthenticator(canAuthenticate: true, result: true)` — never
  `BiometricAuthenticator`. `AppLock.init` calls `canAuthenticate` and
  `SettingsView`'s body reads `canUseLock`, so a real authenticator turns every
  render into an `LAContext` round-trip to a system daemon on a headless CI
  simulator. Same rule for any future hardware-backed service: put it behind a
  protocol and stub it. Pass `appLock:` explicitly only to pin a *different*
  state (locked, or a device that can't authenticate).
- **Persisted preferences use a throwaway suite.** `throwawayDefaults()` in
  `ViewRenderingTests.swift` (and `freshDefaults()` in `AppLockTests.swift`)
  hands out a single-use `UserDefaults(suiteName:)`, so a test that flips a
  stored flag can't leak it into the next test. Never write to `.standard`.
- **Swift Testing ignores xcodebuild's test-timeout flags.**
  `-test-timeouts-enabled` / `-default-test-execution-time-allowance` bound
  *XCTest* cases only; they were tried in CI and a hung run sailed straight past
  them. To bound a single test, use a `.timeLimit` trait; the workflow's
  step-level `timeout-minutes` is what actually caps a hang.
- Hold the `ModelContainer` for the test's lifetime — a deallocated container
  resets its context and invalidates every model it owned.

## Gotchas worth remembering

- `FuelEntry` / `PendingFillUp` store `fuelGradeRaw: String`; the `fuelGrade`
  computed property falls back to `.other` for an unrecognized raw value. Test
  that fallback when touching grades.
- `FuelEntryDraft` drops a receipt larger than `maxReceiptBytes` (4 MB) at the
  write boundary — the record may still report `hasReceipt`, but promotion
  nulls an oversized blob.
- `FuelEntryDraft` rejects **non-finite** numbers, not just non-positive: `NaN`
  fails `> 0` already, and the explicit `isFinite` guard also stops `+∞` from
  slipping through as "positive."
- Odometer/number formatting rounding can differ across iOS versions
  (banker's vs half-away) — assert unambiguous values, or accept both roundings
  for an exact midpoint.
- Currency is locale-aware (`Format.currency`). Volume/distance/economy honor a
  **user unit preference** (`UnitSettings`, an `@Observable` in the SwiftUI
  environment; enums + conversions in `MeasurementUnits`). **Storage stays
  canonical — miles, US gallons, US MPG** — and conversion happens only at the
  display/entry boundary, so the model and `FuelStatistics` never change with
  the unit choice. Threading rules:
  - Views read `@Environment(UnitSettings.self) private var: UnitSettings?` and
    fall back to `.us` when absent, so previews and the render harness don't
    have to inject it (`SettingsView` is the exception — it binds, so it needs
    a non-optional one).
  - `Format` has unit-aware helpers (`volume` / `distance` / `economy` /
    `fuelPrice(per:)` / `costPerDistance`) that take a canonical value and a
    target unit. The KPI builders, `VehicleShowdown`, and `weekdayPriceInsight`
    take a `UnitPreferences` **defaulting to `.us`**, which reproduces the
    canonical output byte-for-byte (existing tests rely on this).
  - Forms bind through converting `Binding`s so stored values stay canonical.
  - Charts **relabel** for linear metrics (distance/price) but **convert the
    series** for economy — L/100km is the reciprocal of MPG, so its curve shape
    changes.
  - **OCR scanning (pump + odometer) is US-only by design** — the parsers are
    tuned to US pumps. Manual entry supports every unit.
  - The watch keeps its own preference in its local `UserDefaults` (syncing it
    with the phone needs a shared App Group, deferred with iCloud).
- **Accent colors go through `AccessiblePalette`, never `.orange`/`.blue`/etc.**
  Apple's stock palette fails WCAG 2.2 AA in light mode across the board (orange
  2.20:1 on a white card, where text needs 4.5:1; orange/teal/green also fail the
  3:1 bar for chart marks). `AccessiblePalette.color(_:in:)` and
  `Metric.color(in:)` take a `ColorScheme`; views hold
  `@Environment(\.colorScheme)` and pass it down. Colors are stored as **RGB
  components, not `Color`**, precisely so `ContrastTests` can recompute every
  ratio each CI run — a `Color` is opaque and can't be measured. Details and the
  device-only checklist live in `docs/accessibility.md`.
- **Chart audio graphs are iOS-only.** `AXChartDescriptor` doesn't exist on
  watchOS, so `MetricChartDescriptor` sits behind `#if os(iOS)` in
  `Shared/Views/ChartAudioGraph.swift`. The *data* half (`ChartAudioGraphData`)
  is deliberately plain and platform-free so it's testable without a simulator:
  it drops non-finite samples rather than clamping them, returns `nil` rather
  than an empty graph when nothing is usable, and pads a flat series so the axis
  isn't zero-width (with a fixed pad at exactly zero, where a proportional one
  stays zero).
- `Winner.notContested` (not `.none`) is the showdown "tie" case — the rename
  avoided an optional-chaining footgun (`row("x")?.winner == .none`).
- Location capture is user-controllable (`PrivacySettings.locationCaptureEnabled`,
  Settings → Location). When off, **no Core Location use and no coordinates
  stored** — the flag is threaded as `captureLocation` through
  `detectStation` / `importPhoto` and the pure mappers
  (`applyPumpReading` / `applyReceipt` / `applyCoordinates`); a receipt's
  *printed* station name still applies. `LocationPrivacy.purgeSavedLocations(in:)`
  nils coordinates on every `FuelEntry` **and** `PendingFillUp`. If you add a new
  location source, gate it on this flag and clear it in the purge.
- `FuelStatistics` is rebuilt only when its inputs change, via `FuelStatisticsMemo`
  — a **plain (non-observable) class held in a view's `@State`**; `statistics(for:)`
  mutates only its private cache, so calling it in `body` never triggers a
  re-render or a "modifying state during update" warning. The key hashes only
  **stat-affecting** fields (id/date/odometer/gallons/price/full-tank/missed/grade),
  so editing a station or notes correctly doesn't invalidate. Views compute stats
  through the memo, never `FuelStatistics(entries:)` inline. Line charts
  **downsample for display** above 500 points (`[DateValuePoint].downsampled(max:)`,
  endpoint-preserving) — display-only; KPIs/averages still come from the full data.
- First-run onboarding (`WelcomeView`) shows only when
  `OnboardingGate.shouldOnboard(hasCompleted:vehicleCount:)` is true — i.e. no
  vehicles **and** the `@AppStorage("hasOnboarded")` flag isn't set. It's decided
  once in `ContentView`'s `.task` (before iCloud sync might populate vehicles),
  presented as a `fullScreenCover`, reuses the real add-vehicle/add-fill-up
  forms, and is skippable; finishing sets the flag so it never returns.
- The fill-up list search/filter (`FillUpFilter`) is a **pure in-memory filter**
  over one vehicle's already-loaded history — not a `#Predicate`/`@Query` — and
  it only narrows what the list *shows*; `FuelStatistics` stays computed over the
  full history, so the dashboard math never changes with the filter.
  `DashboardTimeRange` now lives in `Shared/` so the list's date filter and the
  dashboard's range picker share one definition (use `cutoff(from:)` for
  deterministic tests).
- At-rest protection is best-effort **without** an entitlement:
  `StoreProtection.secureStore(at:)` sets `.completeUntilFirstUserAuthentication`
  on the store files after the container opens. Comprehensive coverage of
  future blobs needs the `default-data-protection` entitlement, deliberately
  deferred to keep the free-account build working (like iCloud). The optional
  **`AppLock`** (Settings → Security, off by default) gates entry on Face ID /
  passcode via a `DeviceAuthenticating` protocol — keep `LAContext` behind that
  protocol so the state machine stays testable, and inject `AppLock` wherever
  `SettingsView` or the `AppLockGate` is hosted (app root, previews, render
  harness).

## Before you open a PR

- [ ] Change goes through `FuelEntryDraft` if it creates/edits entries.
- [ ] New `@Model`? Registered in `ModelContainerFactory.schema` **and** the
      schema test updated.
- [ ] Entitlements still empty; no free-account-breaking capability added.
- [ ] `Shared/` still free of UIKit/Vision/ImageIO/MapKit.
- [ ] Balance check clean on every touched file.
- [ ] Tests written for the change, including a hostile/edge case.
- [ ] PR body points at the **CI check** for test results — never claims a pass.
- [ ] No secrets, tokens, hostnames, or model identifier in the diff.
