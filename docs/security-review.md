# Security review

A security review of the FuelTracker app, documenting the threat model, the
vulnerabilities found, the fixes applied, and the items reviewed and
deliberately accepted.

## Scope & threat model

FuelTracker is an on-device iOS/watchOS app. It has:

- **no server we operate**, no custom API, no authentication, no secrets or
  API keys in the codebase;
- **no custom URL scheme, deep links, or WebView** that parse untrusted input;
- local persistence via **SwiftData**, optionally synced through the user's
  **private CloudKit database** (Apple-encrypted, entitlement ships disabled);
- SwiftData queries use compiled `#Predicate`s — **no string-built predicates**,
  so there is no query-injection surface.

That leaves one meaningful source of attacker-controllable input: **a photo the
user imports**. A photo library can hold images that arrived from anyone — via
Messages, AirDrop, email, or a shared album — so both a photo's **raw bytes**
(fed to the image-decode/OCR pipeline) and its **OCR-recognized text** (fed to
the pump/receipt/odometer parsers) must be treated as untrusted.

The realistic risk in that surface is **resource exhaustion (denial of
service)** — a crafted image that crashes or freezes the app — and it requires
user interaction (importing the image). Severity is therefore **Low–Medium**
(local DoS, user-in-the-loop), not remote code execution.

## Findings & fixes

### 1. Image decompression bomb → memory-exhaustion crash — FIXED

**Where:** `ReceiptImage.compressed(from:)` and `PumpPhotoImporter.process(_:)`.

**Issue:** Decoding went through `UIImage(data:)` /
`CGImageSourceCreateImageAtIndex`, which decompress the **entire** image into a
bitmap *before* any downsizing. A small but maliciously crafted file that
declares enormous pixel dimensions (e.g. 30000×30000 ≈ 3.4 GB as RGBA) exhausts
memory and gets the app jetsam-killed — a classic decompression bomb. The OCR
importer decoded the full-resolution image on every import, and the receipt
compressor did the same before shrinking.

**Fix:** Both paths now decode through ImageIO's thumbnail generator
(`CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize`),
which decodes straight to a bounded size and never materializes the
full-resolution bitmap. Storage is capped at 1600px; OCR at 4096px (far more
than Vision needs to read a pump or receipt).

### 2. Algorithmic-complexity DoS (O(n³)) in the pump parser — FIXED

**Where:** `PumpScanParser.applyConsistentTriple(_:into:)`.

**Issue:** To identify an unlabeled (gallons, price, total) triple by
arithmetic consistency, the parser ran a **triple-nested loop over every
number token** recognized in the image, with no upper bound. A real pump or
receipt shows a handful of numbers, but a crafted, number-dense image (a photo
of a spreadsheet, a page of digits) could yield hundreds — and n³ grows fast
(600 tokens ≈ 2×10⁸ iterations), freezing the UI thread.

**Fix:** The search now filters to in-range values and caps the working set at
40 candidates. Legitimate fills stay far under that, so accuracy is unchanged,
while the worst case is bounded to ~64k iterations.

### 3. Unbounded/undecodable payload persisted — FIXED

**Where:** the receipt/photo import call sites in `AddEditFillUpView`.

**Issue:** Each stored `ReceiptImage.compressed(from: data) ?? data`. When
compression failed — exactly the case for an oversized or malformed image — the
code fell back to persisting the **raw, unbounded bytes** into SwiftData (and
onward to CloudKit sync). Those bytes would then be re-decoded whenever the
receipt was viewed, repeating the bomb and bloating the store/sync.

**Fix:** The call sites now persist **only a non-nil, re-encoded, size-bounded
result**. Undecodable or oversized input is dropped, never stored.

## Reviewed and accepted (no change)

- **Receipt images and GPS coordinates are PII.** They are stored in the local
  SwiftData store and, when the user enables it, the **private** CloudKit
  database. This is the user's own data, held on their device/account by
  design; there is no third-party transmission. Accepted.
- **`StationLocator` continuation re-entrancy.** Calling `detectStation()`
  again while a previous call is still awaiting a location fix would leak the
  first continuation (a hang, not a crash). The UI already guards every entry
  point with a disabled/`isLocating…` state, so the reentrant path isn't
  reachable in practice. Low risk; left as-is to avoid churn in the
  concurrency path.
- **Future/garbage EXIF dates flow through to the form.** By design: the
  importer reports what the photo says and the user reviews every imported
  value before saving; the statistics layer already tolerates odd dates.
- **CloudKit entitlement ships disabled.** Intentional, so free-Apple-ID
  builds work locally; documented in the README. Not a vulnerability.

## Tests

`FuelTrackerTests/SecurityHardeningTests.swift` covers the fixes: the parser
survives an 800- and 1000-token number flood without hanging and never
fabricates out-of-range fuel values, a real triple is still found amid noise,
and the image path bounds a 15–16-megapixel source below the cap while
returning `nil` (so nothing is stored) for undecodable bytes.
