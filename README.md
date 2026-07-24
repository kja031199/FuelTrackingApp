# FuelTracker

A native iPhone app for tracking gas fill-ups and fuel economy, inspired by Fuelly. Built with SwiftUI, SwiftData, and Swift Charts — no third-party dependencies.

## Features

### Scan the pump with your camera
Tap **Scan Pump Display** on the fill-up form and point your camera at the pump: live on-device text recognition (VisionKit) reads the gallons, price per gallon, and total straight off the display and fills the form. The parser cross-checks the numbers (gallons × price ≈ total) so it can identify the values even on pumps with unusual layouts — and it refuses to guess when the reading is ambiguous. Nothing leaves your phone. (Requires a real device; the Simulator has no camera.)

### Receipt vault
Every fill-up can keep its photo. When you scan the pump or import a pump photo, the image is **attached to the entry automatically** instead of being discarded after the numbers are read — and you can attach any receipt photo manually. Tap the thumbnail to view it full-screen (pinch to zoom) or share it for an expense report or warranty claim; a paperclip marks entries that have one in the history list. Photos are downsized before storage so they stay light in the on-device store and in iCloud sync.

### Scan your odometer too
The odometer field has its own camera button: point it at your dashboard and OCR picks the odometer out of the instrument-cluster clutter — the clock, temperature, trip meter, and speedometer are recognized and ignored. Every reading is **validated against your history**: a value below your last reading or implausibly far beyond your typical tank distance is flagged with a warning before you accept it, so a misread gets caught instead of saved. Combined with pump scanning, a fill-up is two photos and zero typing.

### Import a pump photo taken earlier
Took a photo at the pump to log later? Tap **Import Pump Photo** on the fill-up form and pick it: the same on-device OCR reads gallons and price off the display, the **date and time** come from the photo's EXIF metadata, and the **gas station** is looked up from the GPS coordinates embedded in the photo — no location permission needed, since the location comes from the photo itself. A dashboard photo fills the **odometer** the same way, but only when the reading validates against your vehicle's history — doubtful readings are never auto-filled. A summary line shows exactly what was imported; anything unreadable is left for manual entry.

### Scan a paper receipt
Kept the receipt instead? Tap **Scan Receipt** on the fill-up form and pick a photo of it. The same on-device OCR reads the fuel **gallons and price** (the gallons × price ≈ total cross-check ignores car-wash, tax, and grand-total lines), and — unlike a pump display — the receipt also gives up its **printed purchase date and time** and the **station brand**. The printed date is trusted over the photo's own timestamp, since a receipt is often photographed days later; the station is matched against known fuel retailers so you get a clean name ("Shell", "Circle K") rather than a line of address text, falling back to the photo's GPS only when no brand is printed. The receipt image is attached to the entry automatically, and anything unreadable is left for you to fill in. Everything happens on your device.

### Day-of-week price patterns
The dashboard surfaces your personal price rhythm from your own history — no external data. A **Price by Day** card charts your average price per gallon by weekday (a dot plot with a zoomed axis so cent-level differences are visible and honest, cheapest day highlighted) and headlines the takeaway: "You pay about $0.11/gal less on Tuesdays than Fridays." It appears once you have at least two weekdays of data, and the headline stays quiet until there's a handful of fills and a real (≥1¢) spread — so it never reads noise as a pattern.

### Missed fill-up detection
Forgot to log a fill? The next entry's MPG comes out impossibly high — and the app notices. Segments far above your vehicle's norm (or physically absurd outright) are flagged with a "Missed a fill?" badge in the history and a review banner on the dashboard. Mark **"Missed logging a fill before this"** on the entry and the bogus segment is excluded from your MPG stats while the fuel still counts toward spending. Detection is deliberately conservative: it compares against your median MPG and needs enough history before flagging anything relative — a hybrid's great highway tank won't get falsely accused.

### Automatic gas station detection
The station field fills itself: with location access granted, a new fill-up looks up the nearest gas station (MapKit points of interest) and records its name and coordinates with the entry. A location button on the field lets you trigger or re-run detection; you can always type the name manually. Location is used once per fill-up, never tracked in the background.

### Logging fill-ups
Every time you fill up, log:

- **Odometer reading** (with a warning if it's at or below your last reading)
- **Gallons** pumped
- **Price per gallon**
- **Total cost — calculated automatically** from gallons × price, live as you type
- Date & time, fuel grade (Regular / Midgrade / Premium / Diesel / E85), gas station, notes
- **Full vs. partial tank** — full-tank fills let the app compute exact MPG; partial-fill gallons roll into the next full-tank segment (the same method Fuelly uses)

### Dashboard
KPI tiles, filterable by time range (3M / 6M / 1Y / All):

- Average MPG (true total-miles ÷ total-gallons, not an average of averages), last MPG, best MPG
- Total spent and average monthly spend
- Cost per mile
- Average price per gallon (gallon-weighted) and last price paid
- Miles tracked and average miles between fill-ups
- Fill-up count, total gallons, average cost and gallons per fill

Charts (tap or drag the line charts to inspect a point):

- **Fuel Economy** — MPG per full-tank fill-up, with your average as a reference line
- **Gas Price** — price per gallon you paid over time
- **Odometer** — mileage recorded at each fill-up over time
- **Monthly Spending** — total fuel cost by calendar month
- **Monthly Distance** — miles driven by calendar month

### Vehicles
Track multiple vehicles, each with its own history and dashboard. Switch vehicles from the toolbar on the Dashboard and Fill-Ups tabs.

### Head-to-head vehicle showdown
Once you're tracking two or more vehicles, a **Compare** button appears on the Vehicles tab. It puts two cars side by side: a verdict line ("Prius leads 2–1"), a metric table with the winner of each contested row highlighted — average MPG, cost per mile, and average price per gallon — plus informational rows for miles tracked, total spent, and fill-up count. Their MPG trends are overlaid on a single chart so you can see which one is pulling ahead over time. Great for settling "should we take my car or yours?" and for sizing up a car you're thinking of buying. With three or more vehicles, pickers let you choose which two to pit against each other. Rows with data on only one side (or informational rows) never declare a winner, so a brand-new vehicle can't fake a lead.

### Apple Watch app
A companion watchOS app for logging fill-ups from your wrist. The main screen is a quick-entry form (odometer, gallons, price per gallon, live auto-calculated total, full-tank toggle); scroll down for compact KPIs (avg/last MPG, total spent, cost per mile, avg price per gallon, miles tracked) and mini charts (MPG trend, gas price, monthly spend). Data syncs with the iPhone app through iCloud, and the watch app can also run standalone.

To run it in Xcode: select the **FuelTrackerWatch** scheme, pick an Apple Watch simulator, and hit Run. (Xcode needs the watchOS platform downloaded — Settings → Components.)

### iCloud sync (optional, off by default)
The app is fully wired for private iCloud sync (SwiftData + CloudKit) across iPhone and watch, but the entitlements ship **disabled** so the project builds and runs on-device with a free Apple ID — personal teams can't use the iCloud capability. With sync off, data is stored locally on each device and everything works offline. To turn sync on with a paid Apple Developer account, see "Enabling iCloud sync" below; no code changes are needed — the app detects the entitlement and starts syncing.

## Requirements

- Xcode 16 or later
- iOS 17.0+ (uses SwiftData and Swift Charts interactive selection)

## Getting started

1. Open `FuelTracker.xcodeproj` in Xcode.
2. In the target's *Signing & Capabilities* tab, select your development team and change the bundle identifier from `com.example.FuelTracker` to something unique (e.g. `com.yourname.FuelTracker`). If you rename it, also update the watch target: its bundle identifier must be `<your bundle id>.watchkitapp` and its *WKCompanionAppBundleIdentifier* build setting must equal the iPhone app's bundle identifier.
3. Build and run on an iPhone or the iOS Simulator.
4. Add a vehicle in the **Vehicles** tab, then log fill-ups with the **+** button.

### Running on your iPhone with a free Apple ID

1. Plug your iPhone in, trust the Mac, and enable Developer Mode (Settings → Privacy & Security → Developer Mode).
2. In *Signing & Capabilities*, pick your personal team for the FuelTracker, FuelTrackerWatch, and FuelTrackerTests targets.
3. Select your iPhone as the run destination and press Run. On first install, trust yourself in Settings → General → VPN & Device Management.

Free-account installs expire after 7 days — re-run from Xcode to refresh.

### Enabling iCloud sync

Sync requires a **paid Apple Developer Program membership**. One-time setup:

1. In each target's *Signing & Capabilities* tab, add the **iCloud** capability, check **CloudKit**, and add a container named `iCloud.<your bundle id>` — the iPhone and watch targets must share the same container. (This rewrites the entitlements files, which currently ship empty.)
2. On the iPhone target only, also add **Push Notifications** and the **Background Modes → Remote notifications** checkbox so CloudKit can push changes in the background.
3. Let Xcode register the App ID and container with your team (automatic signing does this on first build).
4. Run on devices signed into the same iCloud account — changes sync automatically.

The sync code is always present; it activates automatically when the entitlement exists and falls back to local storage when it doesn't.

## Project structure

```
Shared/                           # Compiled into both apps — single source of truth
├── Models/                       # SwiftData models (Vehicle, FuelEntry, FuelGrade)
├── Statistics/
│   ├── FuelStatistics.swift      # All KPI & chart math (MPG segments, monthly rollups)
│   ├── VehicleShowdown.swift     # Head-to-head two-vehicle comparison model
│   └── KPI.swift                 # Formatted KPI definitions for both dashboards
├── Views/
│   └── MetricCharts.swift        # Generic line/bar chart components (full & compact modes)
└── Support/
    ├── ModelContainerFactory.swift  # CloudKit container with local fallback; in-memory for tests
    ├── FillUpFormModel.swift        # Form state, validation & saving for both entry screens
    ├── PumpScanParser.swift         # OCR text → gallons/price/total (labels + arithmetic)
    ├── ReceiptScanParser.swift      # Receipt OCR → fuel numbers + printed date + station brand
    ├── OdometerScanParser.swift     # OCR text → odometer, validated against history
    ├── Metric.swift                 # Fixed metric→color mapping
    └── Formatters.swift             # Number/currency formatting
FuelTracker/                      # iPhone app (thin view layer)
├── FuelTrackerApp.swift
├── ContentView.swift             # Tab bar + vehicle picker
└── Views/
    ├── Dashboard/                # KPI grid + chart cards
    ├── FillUps/                  # History list + add/edit form
    └── Vehicles/                 # Vehicle management
FuelTrackerWatch/                 # Apple Watch app (thin view layer)
├── FuelTrackerWatchApp.swift
└── Views/                        # Quick-entry form, compact KPIs & charts
FuelTrackerTests/                 # Unit tests (Swift Testing)
└── FuelStatisticsTests.swift     # Statistics engine + form model coverage
```

## Running the tests

Press **⌘U** in Xcode (or Product → Test) with the FuelTracker scheme selected. Code coverage collection is enabled in the shared scheme — see the report under the Report navigator (⌘9) → latest Test → Coverage.

The suite has three layers:

- **`FuelStatisticsTests`** — core statistics engine: full-tank MPG segmentation, partial-fill handling, weighted averages, cost per mile, monthly rollups, plus the fill-up form model (validation, saving, editing, odometer sanity check)
- **`SharedLogicTests`** — every remaining branch of the shared code: model behaviors (cascade delete, fuel-grade fallback), statistics edge cases (zero-distance segments, all-partial history, free fuel, same-day entries), KPI definitions, formatters (locale-independent digit assertions), dashboard time ranges, the container factory, and preview seed data
- **`ViewRenderingTests`** — hosts every iOS screen and component in a real window and forces layout, so view bodies execute under test: all dashboard/list/form/vehicle states, both chart components in full and compact modes, and KPI cards with and without data
- **`HostileInputTests` + adversarial rendering** — deliberately abnormal usage: zero-gallon and negative entries, duplicate odometers, clock skew, future dates, sub-day extrapolation guards, year-boundary grouping, 2,000-entry stress, double-tapped saves, OCR noise floods, out-of-range pump numbers, negative/huge/zero formatter values, and screens rendered against a pathological history — the bar is never crash, never divide by zero, never fabricate a statistic

The thin watch-only view structs aren't in the iOS test bundle (watchOS tests run separately), but all their logic — statistics, KPIs, form model, chart components — is the shared code covered above.

## Privacy

FuelTracker keeps your data on your device — there's no server, no account, and no analytics or third-party tracking. Data syncs only to your own private iCloud (optional, off by default), and station detection sends coordinates to Apple Maps only when you use it. Full details, plus the App Store "App Privacy" data-disclosure checklist, are in [`docs/privacy.md`](docs/privacy.md). (Before submitting to the App Store, fill in the contact/URL placeholders there and host the policy at a public link.)

## Roadmap

Where the app is headed — phased plan with links to tracking issues — is in [`docs/ROADMAP.md`](docs/ROADMAP.md). In short: infrastructure & quality first (CI, accessibility), then deepening the core on the free account (export, reminders, EV support, maintenance log, trip tagging), with iCloud/CloudKit/App-Store features deferred until a paid Apple Developer account.

## Documentation

The project ships a **DocC catalog** (`FuelTracker/FuelTracker.docc`) with browsable reference docs for the domain logic — including two essays, *How MPG Is Computed* and *Scanning Heuristics*, plus symbol docs for the core types. Build it in Xcode with **Product → Build Documentation** (**⌃⌘D**); it opens in the Developer Documentation window. Nothing needs to be hosted — building locally is enough.

## Contributing

Before making changes, read [`CONTRIBUTING.md`](CONTRIBUTING.md) for the working conventions (the `FuelEntryDraft` write chokepoint, the CloudKit-shaped model rules, the empty-entitlements constraint, and the testing bar) and [`ARCHITECTURE.md`](ARCHITECTURE.md) for how the targets and layers fit together. [`CLAUDE.md`](CLAUDE.md) is the same guidance as a terse operating manual — written for AI assistants, handy for anyone getting oriented fast.
