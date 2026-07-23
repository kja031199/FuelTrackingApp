# Architecture

How FuelTracker is put together, and the invariants that keep it building and
safe. Read this before moving code between folders or targets.

See also: [`CONTRIBUTING.md`](CONTRIBUTING.md) for the working conventions, and
[`CLAUDE.md`](CLAUDE.md) for the same as a quick operating manual (used by AI
assistants, useful to anyone).

## Targets

| Target | Contains | Depends on |
| --- | --- | --- |
| **FuelTracker** (iOS) | The iPhone app: views, view-scoped models, and iOS-only services (Vision OCR, ImageIO, CoreLocation/MapKit, PhotosUI). | `Shared/` |
| **FuelTrackerWatch** (watchOS) | The watch app: a quick-entry form and compact KPIs/charts. | `Shared/` |
| **FuelTrackerTests** | Unit and rendering tests (Swift Testing). | `@testable` FuelTracker |

`Shared/` is compiled into **both** apps. It is the single source of truth for
models, statistics, parsing, and shared form logic.

## Layers

```
Models        Vehicle, FuelEntry, FuelGrade,         (SwiftData @Model
              FuelEntryDraft, PendingFillUp           + the write chokepoint)
   ▲
Domain        FuelStatistics, VehicleShowdown,        (pure value logic)
              WeekdayPricePattern, KPI,
              PumpScanParser, OdometerScanParser,
              ReceiptScanParser
   ▲
Support       FillUpFormModel, Formatters, Metric,    (shared app services)
              ModelContainerFactory, MeasurementUnits,
              UnitSettings
   ▲
Services      PumpPhotoImporter, ReceiptPhotoImporter, (iOS-only: UIKit/
(iOS only)    ReceiptImage, StationLocator,            Vision/ImageIO/MapKit)
              FillUpImportModel
   ▲
Views         SwiftUI screens (iOS + watch)            (declarative only)
```

Dependencies point upward only. A view never reaches past a view model into a
parser; presentation logic does not live in the domain layer.

## Invariants

These are load-bearing. Breaking one either stops a target from compiling or
re-opens a closed security issue.

1. **`Shared/` stays free of UIKit, Vision, ImageIO, and MapKit.** The watch
   target compiles `Shared/`, and those frameworks aren't available (or
   appropriate) there. Anything touching image bytes, OCR pixels, or the
   camera/location hardware belongs in the iOS `Services/` layer. The *parsers*
   are pure text→value logic and therefore live in `Shared/`; the *importers*
   that produce that text from a photo are iOS-only.

2. **The model schema stays CloudKit-shaped.** Every `@Model` attribute has a
   default value, every relationship is optional, and there are no unique
   constraints. SwiftData syncs the schema through the user's private CloudKit
   database, which requires this shape. See `ModelContainerFactory`.

3. **Entitlements ship empty by default.** So the app builds and runs on a free
   personal Apple ID (personal teams can't use the iCloud capability). Sync
   activates only when the entitlement is present; otherwise the container
   factory falls back to a local store. Do not commit populated entitlements.

4. **All fill-up writes go through one validation chokepoint.** Every new or
   edited entry is built from a `FuelEntryDraft`, whose failable initializer
   rejects anything without positive odometer, gallons, and price, and which
   owns the single field-by-field mapping onto `FuelEntry`. `FillUpFormModel`
   exposes the current form as a `draft` and saves through it. Any new way to
   create an entry — including features that accept input from other people —
   must build a `FuelEntryDraft`, never a parallel `context.insert` that skips
   the validation.

5. **Untrusted images enter through one bounded decode.** Photos are attacker-
   controllable (a library can hold images from anyone). All image ingestion
   goes through `ReceiptImage` / the bounded ImageIO thumbnail path, never a
   raw `UIImage(data:)`, which is a decompression-bomb vector. Persist only
   re-encoded, size-bounded data.

6. **The parsers' public signatures are stable.** `PumpScanParser`,
   `OdometerScanParser`, and `ReceiptScanParser` have extensive hostile-input
   tests. Refactor their internals freely, but treat their entry points as a
   tested contract.

## Where things live

```
Shared/
├── Models/          SwiftData models + FuelEntryDraft (the write chokepoint)
├── Statistics/      KPI & chart math, showdown, weekday patterns
├── Scanning/        Pure OCR-text → value parsers (pump, odometer, receipt)
├── Support/         Shared form model, formatters, metric colors, container
│                    factory, and the units system (canonical storage +
│                    display/entry conversion)
└── Views/           Generic chart components used by both apps

FuelTracker/         iPhone app (thin view layer)
├── Scanning/        iOS-only: photo importers, image sanitizing, and
│                    FillUpImportModel (import/scan/station orchestration)
├── Services/        iOS-only: StationLocator
└── Views/           Dashboard, FillUps, Vehicles, Submissions, Settings

FuelTrackerWatch/    Apple Watch app (thin view layer)
FuelTrackerTests/    Unit + rendering tests
docs/                Security review and other design notes
```

## View models

Views stay declarative. Two `@Observable` models carry the logic behind the
fill-up screens:

- **`FillUpFormModel`** (Shared) — field state, live total, validation, the
  odometer sanity check, and saving. Shared by the iPhone and watch forms.
- **`FillUpImportModel`** (iOS) — orchestrates the pump-photo, receipt, and
  live-scan imports plus the station lookup, and maps their results onto a
  `FillUpFormModel`. Its result-to-form mapping is pure and unit-tested; the
  async I/O (Vision, MapKit, PhotosUI) stays at the edge.
