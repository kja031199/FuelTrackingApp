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

Open the PR (when asked) noting that the suite wasn't executed in CI, so a
reviewer should run **⌘U** before merge.

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

### 5. Untrusted images enter through one bounded decode

Photos are attacker-controllable. All image ingestion goes through `ReceiptImage`
/ the bounded ImageIO thumbnail path — never a raw `UIImage(data:)`, which is a
decompression-bomb vector. Persist only re-encoded, size-bounded data.

## Testing

- Tests use **Swift Testing** (`@Test`, `#expect`, `#require`), not XCTest.
- Run them with **⌘U** in Xcode (Product → Test) on the FuelTracker scheme.
- **Don't just test the happy path.** The suite holds a deliberate hostile-input
  layer (`HostileInputTests`, `SecurityHardeningTests`, adversarial rendering):
  zero/negative/non-finite values, duplicate odometers, clock skew, OCR noise,
  oversized images. The bar is *never crash, never divide by zero, never
  fabricate a statistic*. New logic should carry the same kind of adversarial
  coverage, not only the expected case.
- View bodies are exercised in `ViewRenderingTests`, which hosts screens in a
  real window and forces layout.

See the "Running the tests" section of the [README](README.md) for the full
layout of the suite.

## Branch & PR workflow

- Work on a feature branch; open **one PR per branch**.
- Write clear commit messages. Keep secrets, tokens, and internal hostnames out
  of commits, code, and docs.
- After a PR merges, start follow-up work from a fresh branch off the latest
  `main` rather than stacking onto already-merged history.
- CI cannot run the iOS test suite (see `CLAUDE.md` for why), so a human should
  run **⌘U** before merging. Call this out in the PR when your change wasn't
  executed on a device.

## Where to read more

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — targets, layers, and the load-bearing invariants.
- [`docs/security-review.md`](docs/security-review.md) — threat model and hardening decisions.
- [`README.md`](README.md) — features, running on-device, enabling iCloud sync, the test suite.
- [`CLAUDE.md`](CLAUDE.md) — the same conventions as a quick operating manual for AI assistants.
