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

### 7. Accent colors go through `AccessiblePalette`

Never use `.orange`, `.blue`, `.teal`, `.green`, or `.purple` directly for text
or chart marks. Apple's stock palette is tuned to look right, not to pass a
contrast threshold, and **every one of those hues fails WCAG 2.2 AA in light
mode** — orange measured 2.20:1 against a white card where 4.5:1 is required,
and orange, teal and green failed even the 3:1 bar for chart marks.

Use `AccessiblePalette.color(_:in:)` or `Metric.color(in:)`, both of which take
the color scheme; views hold `@Environment(\.colorScheme)` and pass it down. The
palette stores colors as **components rather than `Color` values** for a reason:
a `Color` is opaque and its contrast can't be read back, while components can, so
`ContrastTests` recomputes every ratio on each CI run. Add a hue and you inherit
that check; break one and the build goes red.

**If you change a palette value, the tint wash is the constraint — and it's
self-referential.** The tightest pairing in the app is a hue as text on a 15%
wash of *itself*, and that wash is mixed from the value you're editing. Darken
the ink and you darken its background too, so contrast against the wash barely
moves while contrast against the card climbs. Choosing a value against a wash
mixed from Apple's stock color measures something the app never renders; that
mistake put three colors ~0.35 under the bar and only CI noticed.

Full audit, including the before/after numbers and what still needs a device, is
in [`docs/accessibility.md`](docs/accessibility.md).

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
- **Before pushing a change that adds a property to a SwiftUI view struct**, run
  `python3 scripts/check_memberwise_order.py`. Swift's memberwise initializer
  takes arguments in declaration order, so a property added at the end of a
  struct but passed in the middle of a call won't compile — and finding that out
  from a macOS CI run costs a ~7-minute round trip for a one-line fix.
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
- **Batch your pushes.** A push to a branch with a run in flight cancels it and
  restarts from zero, so batch changes into one push instead of trickling commits
  onto an open PR. A healthy run is ~6.5 minutes end to end, of which the test
  suite is about 24 seconds; a 20-minute run means something hung, not that the
  build is slow.

See the "Running the tests" section of the [README](README.md) for the full
layout of the suite.

## Automated checks

The repository is **public**, so GitHub-hosted standard runners — macOS included
— are free. Workflows are split by *speed and determinism* now, not by cost.

**`ci.yml` — build & test.** A macOS runner builds the app and runs the suite on
an iOS Simulator (see Testing above), ~6.5 minutes a run. It runs on **every**
pull request, docs-only ones included, and reports coverage in the job summary.

**`checks.yml` — three fast Linux checks**, running in parallel and independent
of each other.

Together these four are the **required** checks on `main` — none of them skip,
so all four always report a status, which is what makes requiring them safe:

| Check | Tool | What fails it |
|---|---|---|
| Build & test | xcodebuild | A compile error or a failing test |
| Secret scan | gitleaks | A credential-shaped string anywhere in **any commit** |
| Lint | SwiftLint | Any violation of the rules in `.swiftlint.yml` (`--strict`) |
| Docs links | lychee | A broken relative link or `#heading-anchor` in Markdown |

**Why `ci.yml` no longer skips docs.** It used to, via `paths-ignore`, purely to
save billed minutes. But a skipped run reports **no status at all**, and a check
that sometimes reports nothing can never be *required* — a docs-only PR would
wait forever for a result that never arrives. Now that runs are free, a
~6.5-minute run on a Markdown edit is a fine price for a `main` that can
actually block a red build. Don't reintroduce `paths-ignore` without also giving
up required-check status.

**`codeql.yml` — static analysis, on PRs and weekly.** Builds the project on
macOS and runs CodeQL's `security-and-quality` suite over Swift; findings land
in Security → Code scanning. Not a linter — it does dataflow and reachability,
which is a different question from the one SwiftLint answers. Deliberately **not
required**: a scanner that blocks merges before anyone has triaged its output
just teaches people to bypass it. Make it required once it has been quiet for a
while.

**`links-external.yml` — external links, weekly.** Runs lychee *without*
`--offline` against the real network every Monday, plus on demand via
`workflow_dispatch`. It is deliberately **not** on pull requests and **not** a
required check: a failure means a link in the docs needs updating, never that
your change is broken. Keeping it off the merge path is the point — a third
party's server being down should not stand between a correct change and `main`.
This only became useful once the repo went public; while it was private, every
link to its own issues 404'd for an unauthenticated checker.

### Running them locally

```bash
# Lint. On macOS: brew install swiftlint
swiftlint lint --strict

# Or without installing anything, matching CI exactly:
docker run --rm -v "$PWD:/work" -w /work ghcr.io/realm/swiftlint:0.65.0 \
  swiftlint lint --strict

# Secret scan (brew install gitleaks)
gitleaks git . --config .gitleaks.toml --redact --verbose

# Docs links, the PR gate (brew install lychee)
lychee --offline --include-fragments '**/*.md'

# Docs links including external URLs — what the weekly job runs
lychee --include-fragments --max-retries 3 --timeout 20 '**/*.md'
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
- **The PR link check is `--offline` on purpose.** It validates relative links
  and anchors only. Originally that was for two reasons: the repo was private, so
  an unauthenticated checker 404'd on its own issue links, *and* a third-party
  site being down shouldn't block a merge. Going public retired the first reason;
  **the second still stands**, which is why the merge gate stayed offline and
  external checking moved to the weekly `links-external.yml` instead of simply
  dropping the flag.
- **The secret scan reads full history** (`fetch-depth: 0`), not the diff. A
  secret committed and then deleted in a later commit is still leaked. If one
  ever lands, allowlisting is not the fix: rotate the credential first, then
  purge the history, then re-scan.
- **GitHub push protection may reject your push before gitleaks ever sees it.**
  That's a second, earlier line of defence, not a duplicate: gitleaks finds a
  secret already committed, push protection refuses the push so nothing needs
  rotating and no history needs rewriting. If it blocks you, the remedy is to
  remove the credential and rewrite your local commits — **not** to click
  "allow". Bypassing it means the secret enters history, and then the rotate →
  purge → re-scan paragraph above applies to you.
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
- [`docs/accessibility.md`](docs/accessibility.md) — what's supported, the contrast audit, and the device checklist.
- [`README.md`](README.md) — features, running on-device, enabling iCloud sync, the test suite.
- **DocC catalog** (`FuelTracker/FuelTracker.docc`) — browsable domain reference; the "How MPG Is Computed" and "Scanning Heuristics" essays explain the subtle logic. Build with ⌃⌘D.
- [`CLAUDE.md`](CLAUDE.md) — the same conventions as a quick operating manual for AI assistants.
