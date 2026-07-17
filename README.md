# FuelTracker

A native iPhone app for tracking gas fill-ups and fuel economy, inspired by Fuelly. Built with SwiftUI, SwiftData, and Swift Charts — no third-party dependencies.

## Features

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

### Apple Watch app
A companion watchOS app for logging fill-ups from your wrist. The main screen is a quick-entry form (odometer, gallons, price per gallon, live auto-calculated total, full-tank toggle); scroll down for compact KPIs (avg/last MPG, total spent, cost per mile, avg price per gallon, miles tracked) and mini charts (MPG trend, gas price, monthly spend). Data syncs with the iPhone app through iCloud, and the watch app can also run standalone.

To run it in Xcode: select the **FuelTrackerWatch** scheme, pick an Apple Watch simulator, and hit Run. (Xcode needs the watchOS platform downloaded — Settings → Components.)

### iCloud sync
Your vehicles and fill-up history sync automatically across all your devices through your private iCloud database (SwiftData + CloudKit). Nobody else can see your data — it lives in your personal iCloud account. If iCloud isn't available (not signed in, or the capability isn't set up yet), the app falls back to local-only storage and keeps working.

## Requirements

- Xcode 16 or later
- iOS 17.0+ (uses SwiftData and Swift Charts interactive selection)

## Getting started

1. Open `FuelTracker.xcodeproj` in Xcode.
2. In the target's *Signing & Capabilities* tab, select your development team and change the bundle identifier from `com.example.FuelTracker` to something unique (e.g. `com.yourname.FuelTracker`). If you rename it, also update the watch target: its bundle identifier must be `<your bundle id>.watchkitapp` and its *WKCompanionAppBundleIdentifier* build setting must equal the iPhone app's bundle identifier.
3. Build and run on an iPhone or the iOS Simulator.
4. Add a vehicle in the **Vehicles** tab, then log fill-ups with the **+** button.

### Enabling iCloud sync

Sync requires a **paid Apple Developer Program membership** (free personal teams can't use the iCloud capability). One-time setup:

1. In *Signing & Capabilities*, the **iCloud** (CloudKit) and **Push Notifications** capabilities are already declared in `FuelTracker/FuelTracker.entitlements`.
2. Update the iCloud container identifier to match your bundle identifier: replace `iCloud.com.example.FuelTracker` in **both** entitlements files (`FuelTracker/FuelTracker.entitlements` and `FuelTrackerWatch/FuelTrackerWatch.entitlements`) with `iCloud.<your bundle id>` — the iPhone and watch apps must share the same container for sync to work.
3. Let Xcode register the App ID and container with your team (automatic signing does this on first build).
4. Run on devices signed into the same iCloud account — changes sync automatically, including in the background via silent push.

Without those steps the app still runs; data just stays on-device.

## Project structure

```
Shared/                           # Compiled into both apps — single source of truth
├── Models/                       # SwiftData models (Vehicle, FuelEntry, FuelGrade)
├── Statistics/
│   ├── FuelStatistics.swift      # All KPI & chart math (MPG segments, monthly rollups)
│   └── KPI.swift                 # Formatted KPI definitions for both dashboards
├── Views/
│   └── MetricCharts.swift        # Generic line/bar chart components (full & compact modes)
└── Support/
    ├── ModelContainerFactory.swift  # CloudKit container with local fallback; in-memory for tests
    ├── FillUpFormModel.swift        # Form state, validation & saving for both entry screens
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

Press **⌘U** in Xcode (or Product → Test) with the FuelTracker scheme selected. The suite covers the statistics engine — full-tank MPG segmentation, partial-fill handling, weighted averages, cost per mile, monthly rollups — and the shared fill-up form model (validation, saving, editing, odometer sanity check).
