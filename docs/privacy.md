# FuelTracker Privacy Policy

_Last updated: 2026-07-23_

> **Template note.** This is a complete, accurate description of how the app
> handles data as built. Before submitting to the App Store, fill in the
> **contact** and **published-URL** placeholders below and host this page at a
> public URL (App Store Connect requires a privacy-policy link). Keep it in sync
> with the code — if a future change starts collecting or transmitting data,
> update this document and the disclosure checklist in the same PR.

## The short version

FuelTracker keeps your data **on your device**. There is **no FuelTracker
server**, no account to create, and **no analytics, advertising, or third-party
tracking**. The developer cannot see your fill-ups, photos, or locations.

Your data leaves your device only in ways **you** turn on or trigger:

- **iCloud sync** (optional, off by default) stores your data in **your own
  private iCloud account**, which the developer cannot access.
- **Station detection** (optional) sends your current coordinates to **Apple
  Maps** to find the nearest gas station, the same way any Maps search works.

Everything else — logging fill-ups, scanning a pump or receipt, computing your
MPG and costs — happens entirely on your device.

## What the app stores

All of the following is stored **locally on your device** (and, only if you
enable iCloud sync, in your private iCloud):

- **Vehicles** — the nickname, make, model, and year you enter.
- **Fill-ups** — date, odometer reading, volume, price, fuel grade, whether it
  was a full tank, and any station name or notes you add.
- **Location of a fill-up** — the coordinates where a fill-up happened, **only
  when you allow location capture** (see "Your controls").
- **Receipt and pump photos** — images you scan or attach, stored re-encoded and
  size-bounded alongside the fill-up.
- **Pending submissions** — if someone submits a fill-up for your review, their
  submitted values (and optional photo) are held until you approve or dismiss.
- **App preferences** — units and privacy/security settings, stored in the
  system preferences store.

## Where your data lives

- **On device.** The primary store is a local database on your device. When you
  have a device passcode or biometrics set, the store is encrypted at rest — its
  files stay locked until the first time you unlock the device after it powers
  on — so it isn't readable from a device that's been taken while powered off.
- **Your private iCloud (optional).** If you enable iCloud sync, your data syncs
  across your devices through **your** private iCloud database. This is handled
  by Apple under [Apple's privacy policy](https://www.apple.com/legal/privacy/);
  the developer has no access to it. Sync ships **disabled by default**.

## What leaves your device

| Flow | When | Where it goes | Who can see it |
| --- | --- | --- | --- |
| iCloud sync | Only if you enable it | Your private iCloud (Apple) | You, on your devices |
| Station lookup | Only when you use "detect station" / import a geotagged photo with capture on | Apple Maps (MapKit) | Apple, per its privacy policy |
| Pump / receipt / odometer scanning | When you scan or import a photo | **Nowhere** — text recognition runs **on device** (Apple Vision) | You |

There is **no developer backend**, and the app contains **no third-party
analytics, advertising, or tracking SDKs**. Nothing is sold or shared with data
brokers.

## Permissions the app asks for

The app requests these only when a feature needs them, and each is optional:

- **Location (While Using the App)** — to detect the gas station you're at.
  Declining still lets you type a station name; you can also disable location
  capture entirely (below).
- **Photo Library** — to import a pump or receipt photo you already took.
- **Camera** — to scan a pump display, receipt, or odometer live.

## Your controls

- **Turn off location capture** — Settings → Location. When off, the app never
  requests or uses your location and stores no coordinates.
- **Remove all saved locations** — Settings → Location clears the coordinates
  from every fill-up you've logged, keeping the fill-ups themselves.
- **Lock the app** — Settings → Security can require Face ID / Touch ID / your
  passcode to open the app.
- **Delete data** — delete individual fill-ups or a whole vehicle in the app;
  deleting the app removes its local data from your device. Data already synced
  to your private iCloud is removed per your iCloud settings.
- **Turn iCloud sync on/off** — controlled by your iCloud account settings; the
  app ships with sync disabled.

## Children

FuelTracker is a general-audience utility and is not directed at children. It
does not knowingly collect data from anyone, of any age — there is no
collection to begin with.

## Changes to this policy

If the app's data handling changes, this document will be updated and the "Last
updated" date changed. Material changes will be reflected before the affected
version ships.

## Contact

Questions about privacy: **<your-contact-email>** (fill in before publishing).

---

# Appendix — App Store "App Privacy" data-disclosure checklist

This maps every piece of data the app touches to Apple's
[App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
questions, so the App Store Connect questionnaire can be answered truthfully.

## Recommended top-level answer: **Data Not Collected**

Apple defines "collect" as transmitting data off the device in a way that makes
it accessible **to you (the developer) or your third-party partners**. On that
definition, FuelTracker appears to qualify for **"Data Not Collected,"** because:

- There is **no developer server** and **no third-party analytics/ads/tracking**.
- On-device storage that never leaves the device is **not** "collection."
- **Private CloudKit** data lives in the user's own iCloud; Apple states data in
  the user's private database that you don't access is **not** collected by you.
- **MapKit** station lookup is processing by **Apple**, not collection by the
  developer.
- Scanning/OCR runs **on device** (Apple Vision) and transmits nothing.

> **Confirm before you submit.** Apple's definitions are the source of truth and
> can change. Re-read the current "Data Not Collected" criteria against the
> table below, especially the CloudKit and MapKit rows. If you later add any
> analytics, crash reporting, a backend, or any third-party SDK, this answer
> almost certainly changes — revisit it.

## Per-data-type mapping

If, after reviewing Apple's criteria, you determine any row must be disclosed
(rather than "Data Not Collected"), here is the truthful mapping to use. In all
cases: **not linked to identity** (no account/identifier exists) and **not used
for tracking** (no cross-app/website tracking, no data shared with brokers); the
**only** purpose is **App Functionality**.

| Data (Apple category) | In the app | Stored where | Leaves device? | Linked to identity | Tracking | Purpose |
| --- | --- | --- | --- | --- | --- | --- |
| **Precise Location** | Fill-up coordinates | On device / private iCloud | Only to Apple Maps for lookup, and only with capture on | No | No | App Functionality |
| **Photos** (User Content) | Receipt / pump images | On device / private iCloud | No (private iCloud only if sync on) | No | No | App Functionality |
| **Other User Content** | Fill-ups, vehicle names, stations, notes | On device / private iCloud | No (private iCloud only if sync on) | No | No | App Functionality |

## Explicitly **not** touched

Declare these as not collected — the app has no code path that produces them:
contact info, identifiers (no account, no device ID collection, no
IDFA/advertising), purchases/payment/financial info (fuel *prices* you type are
user content, not payment data), health & fitness, browsing/search history,
contacts, messages, audio, usage data / product interaction analytics,
diagnostics / crash logs, and sensitive info.

## Keeping this honest

The disclosure must track the code. This mapping reflects, and cross-references,
the actual behavior documented in
[`docs/security-review.md`](security-review.md):

- Location capture is **user-controllable** (opt-out + purge) — issue #47.
- On-device data is protected at rest, with an optional biometric/passcode lock
  — issue #46.
- iCloud sync ships **disabled** by default — see the README's "Enabling iCloud
  sync" section.
