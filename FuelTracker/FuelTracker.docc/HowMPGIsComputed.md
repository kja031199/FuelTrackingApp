# How MPG Is Computed

Turning a list of fill-ups into a fuel-economy number the way Fuelly does it.

## Overview

Miles per gallon isn't a property of a single fill-up — it's a property of the
distance driven **between** two full tanks and all the fuel poured in over that
span. ``FuelStatistics`` computes it once from a vehicle's entries; this article
explains the rule so the code in its initializer reads as intended.

## The segment rule

Entries are first sorted by **odometer** (not date — a phone's clock can be
wrong; the odometer only moves forward). The calculation then walks them in
order, tracking a *baseline* (the last full tank) and the gallons added since.

- The **first full tank** becomes the baseline. It has no MPG of its own —
  there's no earlier full tank to measure from.
- Every later fill-up adds its gallons to a running total for the current
  segment, **including partial fills**. A partial fill never produces its own
  MPG point; its fuel simply counts toward the next full-tank segment.
- When a **full tank** closes a segment, the distance is
  `odometer − baseline.odometer` and the economy is
  `miles ÷ gallonsSinceBaseline`. That full tank then becomes the new baseline
  and the gallon counter resets.

Each closed segment yields one ``MPGPoint`` (miles, gallons, and the resulting
mpg), which is what the dashboard's fuel-economy chart plots.

## Guards

The math refuses to invent a number:

- A segment is recorded only when **miles > 0 and gallons > 0**, so a duplicate
  odometer (zero distance) or a zero-gallon entry can never divide by zero or
  fabricate a point.
- Averages and totals shown elsewhere are computed over the **full** dataset;
  the chart may downsample points for display, but never the underlying math.

## Missed fill-ups restart the chain

If you forget to log a fill-up, the next segment would span *more* distance than
the fuel you recorded — producing an impossibly high MPG. Marking an entry with
`missedPreviousFillUp` (see ``FuelEntry``) tells the calculation an unlogged fill
sits just before it, so **no segment can end there**. The chain restarts: that
entry becomes the new baseline if it's a full tank, otherwise the baseline
clears until the next full tank. The skipped fuel still counts toward spending —
it just can't produce an MPG.

## Catching the ones you didn't mark

Even unmarked, a missed fill-up leaves a fingerprint: a segment whose MPG is far
above the vehicle's norm. ``FuelStatistics`` flags a segment as *suspect* when,
with at least three points to establish a norm, its MPG exceeds **1.75×** the
median — or, regardless of history, when it exceeds an absolute **120 MPG**,
which is physically implausible for a fueled car. The dashboard surfaces these
so you can mark the entry and keep your stats honest.

## Topics

- ``FuelStatistics``
- ``FuelEntry``
