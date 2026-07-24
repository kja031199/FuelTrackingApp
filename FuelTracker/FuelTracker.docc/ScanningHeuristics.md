# Scanning Heuristics

How the camera turns noisy OCR text from a pump, receipt, or odometer into
trustworthy values — and what it refuses to guess.

## Overview

Optical character recognition is messy: a pump display, a receipt, and a
dashboard cluster are all crowded with numbers, and OCR misreads digits. The
three parsers in the scanning layer share one philosophy — **prefer a confident
"nothing" over a wrong value**, because every scanned value lands in a form the
user reviews before saving. They are pure text→value logic (no camera, no
network), which is why they're heavily unit-tested against hostile input.

## Pump display — ``PumpScanParser``

Given the OCR lines from a pump, it produces a ``PumpReading`` (gallons, price,
total) using four strategies in descending order of trust:

1. **Labels.** Lines like `GALLONS 8.712` or `PRICE/GAL 3.499`. Pumps often
   print the label and the value on separate display lines, so a label with no
   number on its line is remembered for the next number seen.
2. **Arithmetic consistency.** With no usable labels, the parser searches for a
   `(gallons, price, total)` triple where `gallons × price ≈ total`. That single
   relationship pins down all three even from unlabeled numbers.
3. **Derivation.** Any two of the three yield the missing one.
4. **Decimal heuristics.** Pumps show price and gallons to three decimals; a lone
   three-decimal number in range is trusted only when exactly one candidate
   fits.

Plausibility ranges keep noise out: gallons **0.3–60**, price **1.5–9.999**,
total **1–500**. Two details worth knowing:

- **Fraction-of-a-cent notation.** `3.49 9/10` means `3.499`; it's normalized
  before parsing.
- **A bounded search.** The consistency step is `O(n³)` over candidate numbers.
  A real pump shows a handful; a crafted, number-dense image could show
  hundreds and turn that cubic scan into a UI-freezing denial of service. Only
  in-range values are considered and the pool is capped (≈40), bounding the
  worst case without affecting real fills.

A live scan merges frame-to-frame with `merge(current:new:)`, keeping the best
value seen so the reading doesn't flicker as OCR results come and go.

## Receipt — ``ReceiptScanParser``

A receipt shows everything a pump does plus two things it doesn't: a printed
date and the station's name. The gallons/price/total triple is delegated to
``PumpScanParser`` — whose arithmetic check naturally rejects a grand total that
bundles in tax or a car wash, because `gallons × price` won't reconcile with it.
On top of that:

- **Station brand.** Matched against a table of known fuel retailers, most
  specific first (so `ExxonMobil` wins over `Exxon`), and boundary-checked so a
  brand can't hide inside a longer word (`ARCO` must not match `MARCO`). Because
  every brand needle is alphabetic, it can never collide with a dollar amount.
- **Printed date and time.** Parsed from the many formats receipts use — ISO
  (`2026-07-19`), month-name (`JUL 19, 2026`), and numeric (`07/19/2026`,
  `7/19/26`). A first field over 12 disambiguates day/month ordering. The
  printed date wins over the photo's EXIF date, which is merely when the picture
  was taken. A date meaningfully in the future (beyond a day of clock skew),
  absurdly old, or an impossible calendar day (e.g. Feb 30) is rejected as a
  misread rather than silently rolled forward.

## Odometer — ``OdometerScanParser``

A dashboard cluster is full of numbers that aren't the odometer — the clock, the
temperature, the trip meter, the speedometer. The parser produces an
``OdometerCandidate`` with a verdict about how it fits the vehicle's history:

- **Noise removal.** Clock patterns (`12:45`), temperatures/percentages
  (`72°`, `80%`), and digit-grouping commas (`42,150` → `42150`) are stripped
  before extracting numbers. Two-or-more-decimal numbers (money/gallons) are
  consumed whole so their tail digits can't leak out as phantom integers.
- **History validation.** Odometers only move forward, so a reading is judged
  against the last one: `plausible` (ahead of the last reading and within a
  believable distance — `previous + max(3000, typical × 8)`, defaulting to
  350 miles per fill), `belowLastReading` (ran backwards — almost certainly a
  misread), or `implausiblyFar` (beyond a plausible tank, worth a human look).
  With no history, the best guess is simply the largest number on the cluster.
- **Integers over decimals.** Main odometers display whole miles, so integer
  candidates are preferred; a one-decimal value is usually the trip meter.
- The fuel numbers already read from the same photo are **excluded** as
  candidates, so a gallons or price value can't be mistaken for mileage.

## Topics

- ``PumpScanParser``
- ``PumpReading``
- ``OdometerScanParser``
- ``OdometerCandidate``
- ``ReceiptScanParser``
