# ``FuelTracker``

Log gas fill-ups and track fuel economy and cost — on device, private by default.

## Overview

FuelTracker is a SwiftUI + SwiftData app for iPhone and Apple Watch. You log
each fill-up; it computes MPG, cost per mile, price trends, and monthly
spending. There is no server — everything lives on device, optionally synced
through your own private iCloud.

Two areas of the domain logic repay a closer look, and comments alone can't
carry the reasoning: how a flat list of fill-ups becomes a fuel-economy number,
and how the camera scanners turn noisy OCR text into trustworthy values. Both
have their own article below.

Every new or edited fill-up is built through one validated chokepoint,
``FuelEntryDraft`` — start there to understand how data enters the store.

## Topics

### Essays

- <doc:HowMPGIsComputed>
- <doc:ScanningHeuristics>

### The write chokepoint

- ``FuelEntryDraft``

### Models

- ``Vehicle``
- ``FuelEntry``
- ``FuelGrade``
- ``PendingFillUp``

### Statistics

- ``FuelStatistics``
