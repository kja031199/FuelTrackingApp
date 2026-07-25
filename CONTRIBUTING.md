# Contributing to FuelTracker

Thanks for working on FuelTracker. This file captures the conventions that keep
the app building, safe, and consistent — the rules that aren't obvious from
reading any single file. Skim it before your first change.

For the *why* behind the structure, read [`ARCHITECTURE.md`](ARCHITECTURE.md).
For the security posture, read [`docs/security-review.md`](docs/security-review.md).
An agent-facing quick reference lives in [`CLAUDE.md`](CLAUDE.md); it overlaps
with this file but is written as a terse operating manual.

## The workflow for every change

Every piece of work — feature, fix, or refactor — runs through four phases, in
order. They're framed as roles so it's clear which hat you're wearing; on a solo
change you wear all four yourself. Skip a step only when it genuinely doesn't
apply (e.g. there are no tests to write for a docs-only change).

1. **Lead Software Engineer** — Take the request. If it maps to a repo issue,
   read the issue and its linked docs before touching code. Plan and reason
   through the change (files, invariants, blast radius) up front. Create a new
   branch off the latest `main`, then implement.
2. **Lead QA Developer (author tests)** — Add happy-path tests, then add
   non-happy-path tests (zero/negative/non-finite values, duplicates, clock
   skew, OCR noise, oversized/garbage input). See the testing bar below.
3. **Senior Technical Writer** — Update this file and
   [`CLAUDE.md`](CLAUDE.md) to reflect the new or changed behavior and any new
   conventions or gotchas.
4. **Lead QA Developer (final review)** — Review the tests against the diff to
   confirm they cover the new, updated, and changed code as fully as possible.
   Then compare the actual changes against the originating issue and the
   request, and confirm the work matches what was asked — flag any gaps.

Open the PR (when asked). CI builds the app and runs the suite on every pull
request — check that status rather than asserting the tests pass yourself.

## The rules that matter

### 1. All fill-up writes go through one validation chokepoint

Every new or edited `FuelEntry` is built from a **`FuelEntryDraft`**. Its
failable initializer rejects anything without a positive, finite odometer,
gallons, and price, and it owns the single field-by-field mapping onto
`FuelEntry`. `FillUpFormModel` exposes the current form as a `draft` and saves
through it; `PendingFillUp.approve(onto:in:)` re-validates through the same
draft before promoting a submission.

**Never** insert a `FuelEntry` (or copy its fields) by hand. Any new source of
fill-ups — an import, a widget intent, a shared submission — must build a
`FuelEntryDraft`. This keeps validation in exactly one place instead of trusting
each caller.

### 2. The model schema stays CloudKit-shaped

Every `@Model` attribute has a **default value**, every relationship is
**optional**, and there are **no unique constraints**. SwiftData syncs the
schema through the user's private CloudKit database, which requires this shape.
When you add a model, register it in `ModelContainerFactory.schema` and update
the schema test in `SharedLogicTests`.

### 3. Entitlements ship empty

The entitlements files are committed **empty** so the app builds and runs on a
free personal Apple ID (personal teams can't use the iCloud capability). Sync
activates only when an entitlement is present; otherwise the container factory
falls back to a local store. **Do not commit populated entitlements**, and don't
add capabilities (iCloud, App Groups, Push) that break the free-account local
build — gate such features behind runtime checks and document the prerequisite
in the README, the way iCloud sync is handled.

### 4. `Shared/` stays framework-light

`Shared/` compiles into both the iOS and watch apps, so it must not import
UIKit, Vision, ImageIO, or MapKit. Pure text→value parsers live in `Shared/`;
the importers that produce that text from a photo are iOS-only (`FuelTracker/`).

### 5. Measurements are stored canonical and converted only at the edge

Every measurement is stored in one canonical unit — **miles, US gallons, US
MPG** — regardless of what the user sees. The unit preference (`UnitSettings`,
an `@Observable` in the SwiftUI environment) and the conversions
(`MeasurementUnits`) live entirely at the display and entry boundary: `Format`'s
unit-aware helpers convert on the way out, and the forms' converting bindings
convert on the way in. The model and `FuelStatistics` stay unit-agnostic — never
convert inside them. Unit-parameterized APIs (`dashboardKPIs(units:)`,
`VehicleShowdown`, `weekdayPriceInsight(units:)`) default to `.us`, which
reproduces the canonical output. OCR scanning is US-only by design; manual entry
supports every unit.

### 6. Untrusted images enter through one bounded decode

Photos are attacker-controllable. All image ingestion goes through `ReceiptImage`
/ the bounded ImageIO thumbnail path — never a raw `UIImage(data:)`, which is a
decompression-bomb vector. Persist only re-encoded, size-bounded data.

## Testing

- Tests use **Swift Testing** (`@Test`, `#expect`, `#require`), not XCTest.
- Run them with **⌘U** in Xcode (Product → Test) on the FuelTracker scheme.
- **CI runs the suite on every pull request** (`.github/workflows/ci.yml`) — a
  macOS runner builds the app and tests it on an iOS Simulator. That check is
  the authority on whether the tests pass; a red check blocks merge.
- **Don't just test the happy path.** The suite holds a deliberate hostile-input
  layer (`HostileInputTests`, `SecurityHardeningTests`, adversarial rendering):
  zero/negative/non-finite values, duplicate odometers, clock skew, OCR noise,
  oversized images. The bar is *never crash, never divide by zero, never
  fabricate a statistic*. New logic should carry the same kind of adversarial
  coverage, not only the expected case.
- View bodies are exercised in `ViewRenderingTests`, which hosts screens in a
  real window and forces layout.
- **Tests stay off real device services.** Anything hardware-backed goes behind
  a protocol and is stubbed. Concretely, the render harness injects
  `StubAuthenticator`, never `BiometricAuthenticator` — `AppLock.init` and
  `SettingsView`'s body both ask whether the device can authenticate, and with
  the real implementation that's an `LAContext` call to a system daemon on every
  render, on a CI simulator that has no biometric and no passcode. Tests that
  persist a preference use a single-use `UserDefaults(suiteName:)` rather than
  `.standard`, so state never leaks between tests.
- **`xcodebuild`'s `-test-timeouts-enabled` and
  `-default-test-execution-time-allowance` do nothing here** — they bound XCTest
  cases, and this suite is Swift Testing. Bound an individual test with a
  `.timeLimit` trait; CI's step timeouts bound the job.
- **CI runs on a 10x-billed macOS runner.** A push to a branch with a run in
  flight cancels it and restarts from zero, so batch changes into one push
  instead of trickling commits onto an open PR. A healthy run is a ~60-second
  build plus a few seconds of tests; a 20-minute run means something hung.

See the "Running the tests" section of the [README](README.md) for the full
layout of the suite.

## Automated checks

Two workflows run on every pull request, split by what they cost.

**`ci.yml` — build & test.** A macOS runner builds the app and runs the suite on
an iOS Simulator (see Testing above). This is the expensive one: **10× billing**,
~7 minutes a run. It skips docs-only changes.

**`checks.yml` — three cheap Linux checks**, all at **1× billing**, running in
parallel and independent of each other. Unlike `ci.yml` these never skip, so they
always report a status — which means they're the ones safe to make *required*
status checks.

| Check | Tool | What fails it |
|---|---|---|
| Secret scan | gitleaks | A credential-shaped string anywhere in **any commit** |
| Lint | SwiftLint | Any violation of the rules in `.swiftlint.yml` (`--strict`) |
| Docs links | lychee | A broken relative link or `#heading-anchor` in Markdown |

### Running them locally

```bash
# Lint. On macOS: brew install swiftlint
swiftlint lint --strict

# Or without installing anything, matching CI exactly:
docker run --rm -v "$PWD:/work" -w /work ghcr.io/realm/swiftlint:0.65.0 \
  swiftlint lint --strict

# Secret scan (brew install gitleaks)
gitleaks git . --config .gitleaks.toml --redact --verbose

# Docs links (brew install lychee)
lychee --offline --include-fragments '**/*.md'
```

### What to know before changing them

- **`.swiftlint.yml` is an allowlist, not the default set.** `only_rules` means
  nothing runs but what's listed. Every rule in it was verified to read zero
  across all 80 Swift files, which is what makes `--strict` safe. It also means a
  SwiftLint upgrade can't turn the branch red on its own — new rules stay off
  until someone opts in. Adding a rule is cheap and expected.
- The file records what was **deliberately left out, with measured counts** —
  `force_unwrapping` (59 hits, 56 of them in tests), `line_length` (58 lines over
  120, nearly all UI copy), `file_length` (the four longest files are test files
  that are *supposed* to grow). Read that before re-litigating one of them.
- **The link check is `--offline` on purpose.** It validates relative links and
  anchors only. External URLs are skipped because this repo is private and its
  own docs link to its own issues — an unauthenticated checker 404s on every one
  — and because a third-party site being down shouldn't block a merge.
- **The secret scan reads full history** (`fetch-depth: 0`), not the diff. A
  secret committed and then deleted in a later commit is still leaked. If one
  ever lands, allowlisting is not the fix: rotate the credential first, then
  purge the history, then re-scan.
- `.github/dependabot.yml` bumps the pinned actions monthly, grouping minor and
  patch into one PR and leaving majors separate. The gitleaks and lychee versions
  are plain release downloads Dependabot can't see; they sit in an `env:` block
  at the top of their job so bumping is a one-line edit.

## Branch & PR workflow

- Work on a feature branch; open **one PR per branch**.
- Write clear commit messages. Keep secrets, tokens, and internal hostnames out
  of commits, code, and docs.
- After a PR merges, start follow-up work from a fresh branch off the latest
  `main` rather than stacking onto already-merged history.
- CI runs the suite on each PR, so let that check — not a hand-written claim —
  confirm the tests pass. Authoring still happens without Xcode (see
  `CLAUDE.md`), so review the code carefully before pushing; CI catches what
  review can't (type errors, actual failures), not the reverse.

## Where to read more

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — targets, layers, and the load-bearing invariants.
- [`docs/security-review.md`](docs/security-review.md) — threat model and hardening decisions.
- [`README.md`](README.md) — features, running on-device, enabling iCloud sync, the test suite.
- **DocC catalog** (`FuelTracker/FuelTracker.docc`) — browsable domain reference; the "How MPG Is Computed" and "Scanning Heuristics" essays explain the subtle logic. Build with ⌃⌘D.
- [`CLAUDE.md`](CLAUDE.md) — the same conventions as a quick operating manual for AI assistants.
