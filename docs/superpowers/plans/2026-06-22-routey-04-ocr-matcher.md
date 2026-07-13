# Routey Plan 04 — OCR Snap-to-Add (perception + matcher)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Turn a photo of a parcel label into a confident match against the route — extract the address + recipient name + keywords (incl. **Signature**, customs), and rank candidate addresses with a deterministic, offline matcher.

**Architecture:** `RouteyOCR` module, fully on-device, no network. A `LabelReader` wraps Apple **Vision** (text + barcode) behind a protocol so the matcher is testable without a camera. A pure-Swift `AddressMatcher` does `normalize → block → weighted-score → rank → threshold`, with civic-number agreement gated and **occupant name as the tie-breaker** for shared-civic complexes. Output is a `MatchResult` (ranked candidates + detected flags) consumed by Plan 05's snap-to-add flow — **this plan does not persist parcels** (Parcel/Today's Run are Plan 05).

**Tech Stack:** Swift 6, Vision, Swift Testing. No third-party deps.

**Depends on:** Plan 01 (`Address`), Plan 03 (`SearchIndex` blocking is reused for candidate generation). The camera UI shell is finished in Plan 05.

**Status 2026-06-28:** PR #15 merged the headless `RouteyOCR` core into
`nightly`: normalization, gated/ranked matching, keyword detection, `LabelReading`
protocol, and `SnapPipeline` are tested with fixture text. A concrete Vision reader,
camera capture, barcode detection, and parcel persistence remain deferred to app/UI
work.

## Global Constraints

- Inherited from Plan 01.
- **On-device only.** Vision: `recognitionLevel = .accurate`, `recognitionLanguages = ["en-CA","fr-CA"]`, **`usesLanguageCorrection = false`** (correction corrupts civic/RR/postal), seed `customWords` with route street names + rural keywords (RR, CONC, HWY, LOT, SS, PO BOX), always pass EXIF orientation, read `topCandidates(3)`. Run all Vision work off the main thread.
- **Civic agreement is gated:** a confidently-read mismatched civic number disqualifies a candidate ("12 Example Lane" never matches "21 Example Lane").
- **Foundation Models extraction is out of scope** here — the deterministic parser/matcher is the backbone.

---

## File structure

```
RouteyKit/
  Package.swift                         # add RouteyOCR
  Sources/RouteyOCR/
    AddressComponents.swift             # parsed/normalized fields
    AddressNormalizer.swift             # raw text -> AddressComponents (bilingual abbrev table)
    EditDistance.swift                  # Damerau-Levenshtein (no dependency)
    AddressMatcher.swift                # candidates + components -> ranked MatchResult
    LabelKeywords.swift                 # detect Signature / customs / etc. in OCR text
    LabelReader.swift                   # Vision wrapper behind a protocol (#if canImport(Vision))
  Tests/RouteyOCRTests/
    AddressNormalizerTests.swift
    AddressMatcherTests.swift
    LabelKeywordsTests.swift
app/Routey/Snap/  (finished in Plan 05)
```

---

### Task 1: Address normalizer (bilingual)

**Files:** `AddressComponents.swift`, `AddressNormalizer.swift`, `EditDistance.swift`, `AddressNormalizerTests.swift`, `Package.swift` (+ `RouteyOCR` target, deps `RouteyModel`).

**Interfaces:**
- `struct AddressComponents: Equatable, Sendable { var civic: Int?; var unit: String?; var routeNumber: String?; var streetTokens: [String]; var occupant: String?; var postal: String?; var rawLines: [String] }`
- `enum AddressNormalizer { static func normalize(_ text: String) -> AddressComponents }`
- `enum EditDistance { static func damerauLevenshtein(_ a: [Character], _ b: [Character]) -> Int }` (or on `String`).

**Normalization rules:** lowercase + fold diacritics; expand a bilingual abbreviation table (`st/rue→street`, `ave→avenue`, `rd/ch→road`, `hwy→highway`, `conc→concession`, `rr→rural route`, `ss→sub station`, `apt/unit/suite→unit`, `n/s/e/o/w` directionals); extract a leading or trailing integer as `civic`; extract `RR <n>`, `Conc Rd <n>`, `Hwy <n> Lot <n>` as `routeNumber`; extract a Canadian postal code (`A#A #A#`) into `postal`; remaining street words → `streetTokens`. Rural formats may have no civic.

- [x] **Step 1:** Add target; `swift build`.
- [x] **Step 2: Write failing tests** — assert: `"9900 Example County Rd 12"` → civic 9900, streetTokens include `["example","county","road","12"]`; `"8800 Sample Concession Rd 6"` → civic 8800, routeNumber/street capture "concession"; `"RR 2 Fictional Hamlet A1A 1X0"` → routeNumber "rr 2", postal "a1a1x0", civic nil; diacritic + abbrev folding (`"123 Rue Exemple O"` → street tokens normalized). Damerau-Levenshtein: `dl("recieve","receive")==1`, transposition counted as 1.
- [x] **Step 3:** Run — FAIL.
- [x] **Step 4: Implement** the normalizer (deterministic, table-driven) + Damerau-Levenshtein (standard DP, ~30 lines). No network.
- [x] **Step 5:** Run — PASS.
- [x] **Step 6:** Commit `"Add bilingual address normalizer + edit distance"`.

---

### Task 2: Address matcher (gated, ranked, three-band)

**Files:** `AddressMatcher.swift`, `AddressMatcherTests.swift`.

**Interfaces:**
- `struct Candidate: Sendable { var address: Address }` (caller supplies candidates — e.g. from `SearchIndex` blocking on civic/street tokens).
- `struct ScoredCandidate: Equatable, Sendable { var addressID: UUID; var score: Double }`
- `enum MatchBand: Sendable { case autoAccept(UUID); case disambiguate([ScoredCandidate]); case manual }`
- `enum AddressMatcher { static func rank(_ components: AddressComponents, against candidates: [Address]) -> [ScoredCandidate]; static func band(_ ranked: [ScoredCandidate], civicWasConfident: Bool) -> MatchBand }`

**Scoring (component-weighted, not one global distance):**
- **Civic gate:** if `components.civic != nil` and a candidate has a civic and they differ → score 0 (disqualified). If both present and equal → strong positive.
- **Street:** token-set overlap (Jaccard) + per-token Damerau-Levenshtein closeness; weight ~0.5.
- **Occupant tie-breaker:** if civic+street agree across several candidates (a complex), occupant-name closeness breaks the tie; weight ~0.2 but decisive among equals.
- **Postal/route:** agreement adds confidence; weight ~0.1.
- **Bands:** auto-accept when top ≥ ~0.90, margin to #2 ≥ ~0.15, and civic agrees (or no civic on either); disambiguate (2–5) in the mid band; manual below a floor.

- [x] **Step 1: Write failing tests** with invented rural-style fixtures:
  - exact civic+street → `autoAccept`.
  - confident mismatched civic ("12 Example Lane" vs candidate "21 Example Lane") → disqualified (not top).
  - two units at "31 Example St" differing only by occupant → occupant name picks the right one (auto-accept or top of disambiguate).
  - near-miss street with same civic → reasonable ranking.
  - no plausible candidate → `manual`.
- [x] **Step 2:** Run — FAIL.
- [x] **Step 3: Implement** `rank` + `band`. Pure functions; deterministic.
- [x] **Step 4:** Run — PASS.
- [x] **Step 5:** Commit `"Add gated, occupant-aware address matcher with confidence bands"`.

---

### Task 3: Label keyword detection

**Files:** `LabelKeywords.swift`, `LabelKeywordsTests.swift`.

**Interfaces:**
- `struct LabelFlags: OptionSet, Sendable { ... static let signature, customs, registered, ... }`
- `enum LabelKeywords { static func detect(in text: String) -> LabelFlags }` — case-insensitive scan for "signature"/"signature required"/"signature requise", customs/duty/"douane", "registered"/"recommandé", etc.

- [x] **Step 1: Write failing tests** — `"... SIGNATURE REQUIRED ..."` → contains `.signature`; French `"signature requise"` → `.signature`; `"CUSTOMS DUTY $4.50"` → `.customs`; plain label → empty.
- [x] **Step 2:** Run — FAIL.
- [x] **Step 3: Implement** the scanner (bilingual keyword sets).
- [x] **Step 4:** Run — PASS.
- [x] **Step 5:** Commit `"Add bilingual label keyword detection (signature/customs)"`.

---

### Task 4: Vision LabelReader (device)

**Status 2026-06-28:** Not implemented in the current nightly train. The protocol
boundary exists and the pipeline is fixture-tested; Vision/device reading remains
open.

**Files:** `LabelReader.swift`, plus a fixture-image test if a sample label is available.

**Interfaces:**
- `protocol LabelReading: Sendable { func read(_ image: CGImage, orientation: CGImagePropertyOrientation) async throws -> LabelReadout }`
- `struct LabelReadout: Sendable { var lines: [String]; var barcodes: [String] }`
- `struct VisionLabelReader: LabelReading` — uses `RecognizeTextRequest` (`.accurate`, langs, `usesLanguageCorrection=false`, `customWords`, `topCandidates(3)`) + `VNDetectBarcodesRequest`; all off the main thread. Guard `#if canImport(Vision)`.

- [ ] **Step 1:** Implement `VisionLabelReader` per the global constraints; expose `customWords` injection (route street names).
- [ ] **Step 2:** If a sample label image is added to the test bundle, write a test that reads it and asserts the address line + a barcode are extracted. Otherwise, write a unit test using a stub `LabelReading` that returns canned lines, and assert the *pipeline* (`normalize → rank → band` + `detect`) produces the expected `MatchResult` — proving the wiring without a camera.
- [ ] **Step 3:** Run — PASS. Commit `"Add Vision label reader (text + barcode) behind a protocol"`.

---

### Task 5: Snap pipeline assembly

**Files:** `RouteyOCR/SnapPipeline.swift` (+ test).

**Interfaces:**
- `struct MatchResult: Sendable { var band: MatchBand; var ranked: [ScoredCandidate]; var flags: LabelFlags; var readout: LabelReadout }`
- `struct SnapPipeline { var reader: any LabelReading; var candidateProvider: (AddressComponents) -> [Address]; func process(_ image: CGImage, orientation: CGImagePropertyOrientation) async throws -> MatchResult }` — reads → normalizes the best lines → gets candidates (via `SearchIndex` blocking on civic/street) → ranks → bands → detects flags.

- [x] **Step 1: Write failing test** with a stub reader + in-memory candidates: a "signature required" label for "31 Example St / Alex Example" yields `band == autoAccept(matchedID)` and `flags.contains(.signature)`.
- [x] **Step 2:** Run — FAIL.
- [x] **Step 3: Implement** `SnapPipeline.process`.
- [x] **Step 4:** Run — PASS. `swift test` (all). Commit `"Assemble snap pipeline (read -> match -> flags)"`.

> The camera capture screen + "add to Today's Run" + running signatures count are built in **Plan 05 Task (Snap-to-Add)**, where the `Parcel`/`TodaysRun` model exists. This plan delivers the pure perception+matching the UI calls.

---

## Plan self-review

- **Spec coverage:** bilingual normalization + rural formats ✓ (T1), gated civic + occupant tie-break + confidence bands ✓ (T2), signature/customs keyword detection ✓ (T3), `LabelReading` protocol boundary ✓ (T4), and the headless matcher pipeline ✓ (T5). Concrete Vision OCR/barcode reading, parcel creation, and signatures count remain deferred to app/UI work.
- **Placeholders:** none in the merged headless matcher/normalizer/keyword/pipeline logic; committed fixtures use invented rural-style data only.
- **Type consistency:** `AddressComponents` (T1) → `AddressMatcher.rank` (T2) → `SnapPipeline` (T5); `LabelFlags` (T3) flows into `MatchResult` (T5); `MatchBand` defined once (T2).
- **Risk honesty:** Vision accuracy on device labels is not validated in the current nightly train; the pipeline is proven with a stub reader, and the concrete device reader/manual camera flow remains open.
