# Snap-to-Add Camera — Design Spec

- **Date:** 2026-06-29
- **Status:** Approved design, pre-implementation
- **Relates to:** Master design spec `docs/superpowers/specs/2026-06-22-routey-design.md` §4, §6 ("Snap parcels"), §7 (OCR + matcher); roadmap milestones M4 (OCR matcher — headless, done) and M5 (Today's Run — domain done, UI deferred).

## 1. Goal

Build the **visible** half of Routey's flagship feature: photograph a parcel label,
read it on-device, match it to the right Address on the route, and add a Parcel to
Today's Run in delivery order. The matcher, normalizer, keyword detector, and the
`SnapPipeline` / `LabelReading` seam already exist and are tested in `RouteyOCR`; the
domain mutation (`RunOperations.addParcel`, `RunGeneration.generate`) already exists and
is tested in `RouteyDomain`. This slice builds the **camera capture surface, the concrete
Vision reader, the orchestration view model, and the three-band confirm UI**, and wires
them end to end so a snapped label produces a real persisted `Parcel`.

This is a **full vertical slice**: camera → OCR → match → three-band confirm → create the
`Parcel` (auto-generating today's run if none exists). The Parcel is persisted now and
becomes viewable once the separate Today's Run screen lands.

## 2. Scope

**In scope**
- AVFoundation still-photo capture surface (snap one photo → `CGImage`).
- A concrete `VisionLabelReader` conforming to the existing `LabelReading` protocol,
  configured per the master spec §7 (no language correction, custom vocabulary,
  en-CA / fr-CA, accurate level) plus a barcode cross-check.
- A candidate provider that sources `AddressCandidate`s from the route's `Address` rows.
- A `SnapViewModel` that orchestrates capture → pipeline → confirm → persist.
- A three-band confirm UI (auto-accept toast / disambiguation short-list / manual search).
- Wiring `accept` to `RunGeneration.generate` (if no run today) + `RunOperations.addParcel`,
  carrying signature/customs/registered `LabelFlags` onto the Parcel and the running counts.
- An entry point: a camera button in the Routes list toolbar presenting the flow as a
  full-screen cover.

**Out of scope (YAGNI / separate slices)**
- Sort-case grid OCR (`RecognizeDocumentsRequest`) — that is the Virtual Sort Case feature.
- The `TabView` app restructure and the Today's Run *screen* — separate track (M5 UI).
- FTS-based candidate blocking — see §6; deferred until profiling proves it necessary.
- A standalone barcode-only scan mode — barcode is a cross-check here, not its own feature.

## 3. Architecture & module placement

The guiding boundary: keep the Vision/camera code thin, keep `RouteyOCR` free of any
database dependency, and keep as much logic as possible Mac-testable.

| New unit | Lives in | Responsibility / interface / dependencies |
| --- | --- | --- |
| `VisionLabelReader` | `RouteyOCR`, behind `#if canImport(Vision)` | **Does:** runs on-device text + barcode recognition on a captured image and returns a `LabelReadout(lines:barcodes:)`. **Interface:** conforms to existing `LabelReading` (`func read() async throws -> LabelReadout`); constructed with the captured image and a configuration (custom words, languages). **Depends on:** Vision + the image; no DB, no UI. Guarded on `canImport(Vision)` (not `os(iOS)`) so it compiles and runs a real OCR pass against a fixture image in `swift test` on the Mac, while still excluding watchOS. |
| `CameraCaptureView` (+ capture controller) | App target, behind `#if os(iOS)` | **Does:** AVFoundation still-photo capture; yields a `CGImage` to the view model. **Interface:** SwiftUI view bridging an `AVCaptureSession` preview + a shutter action. **Depends on:** AVFoundation, camera permission. UIKit-bridged UI — app-shell territory, not package logic. |
| `SnapViewModel` (`@MainActor @Observable`) | App target | **Does:** orchestrates captured image → builds `VisionLabelReader` + candidate provider → `SnapPipeline.process()` → exposes `band` / `ranked` / `flags` → on accept calls the domain. **Depends on:** the injected `DatabaseWriter`/`DatabaseReader`, `RouteyOCR`, `RouteyDomain`. Holds all view logic so the View stays declarative (per CLAUDE.md / AGENTS.md). |
| `SnapResultView` | App target | **Does:** renders the three-band confirm UI and the accept/undo actions. **Depends on:** `SnapViewModel`. |

**Preserved boundary:** `RouteyOCR` has no Persistence dependency today and stays that way.
The candidate provider is built in the app view model: it reads `Address` rows via the
injected reader and maps each with the existing `AddressCandidate(_ address:)` initializer,
then hands `SnapPipeline` a plain `@Sendable (AddressComponents) -> [AddressCandidate]`
closure. The package stays DB-free; the app does the wiring.

## 4. Data flow

```
[Camera] snap one photo → CGImage
    → VisionLabelReader(image:config:).read()      // Vision text (no language correction,
                                                   //   customWords) + barcode cross-check
    → SnapPipeline.process()                       // existing, tested
        → AddressNormalizer.normalize
        → candidateProvider(components)            // app closure over route Address rows
        → AddressMatcher.rank / .band
        → LabelKeywordDetector.detect
    → SnapViewModel publishes band + ranked + flags + readout
    → SnapResultView:
        .autoAccept(id) → undoable toast, add immediately      (master spec §7)
        .review([…])    → 2–5 short-list, raw OCR shown, tap to pick
        .noMatch        → manual predictive search (reuse SearchView)
    → on accept:
        RunGeneration.generate(...)   if no run exists for today's service date
        RunOperations.addParcel(...)  carrying LabelFlags (signature/customs/registered)
        → running signature/customs counts update
```

## 5. Confirm UX — three bands (per master spec §7)

- **Auto-accept** (`.autoAccept(id)`): top score is confident and the civic number agrees;
  add the Parcel **immediately** and show an **undoable toast** rather than a modal — speed
  in the truck. Undo removes the just-added Parcel.
- **Disambiguation** (`.review([…])`): show a short list of 2–5 ranked candidates with the
  **raw OCR text visible** so the carrier can pick the right door; tap to add.
- **Manual fallback** (`.noMatch`): drop straight into the existing predictive search
  (reuse `SearchView`) so the carrier finds the address by hand — never a dead end.

## 6. Candidate sourcing decision

For V1 there is effectively **one route** of a few hundred delivery points. The provider
**loads all of the route's `Address` rows and lets `AddressMatcher` score them in
memory** — simplest, fully deterministic, trivially testable. The same pass harvests the
route's **distinct street names** to seed `customWords` for the Vision reader (the rural
accuracy lever — RR / CONC / HWY / LOT / SS plus the static keyword list).

FTS-based candidate *blocking* (master spec §7) is intentionally **deferred**: the matcher
already does the scoring work, and blocking is a profiling-driven optimization we add only
if a real route proves slow. This is a deliberate divergence from the spec's stated pipeline
and is recorded here.

## 7. Navigation entry point

No `TabView` exists yet, and this slice does **not** introduce one (that restructure belongs
with the Today's Run track). For now: a **camera button in the Routes list toolbar**
(`ContentView`) presents the Snap flow as a `.fullScreenCover`. One entry point, no
structural churn; it moves into a Snap tab later without rework.

## 8. Error & empty states (offline-first, never blocks)

- **Camera permission denied** → explanation + a Settings deep link; the rest of the app is
  unaffected.
- **No camera available** (e.g. Simulator) → graceful "use a device to snap labels" message
  so the app still runs and the slice degrades cleanly.
- **OCR returns no usable text** → "couldn't read a label — retake" with a retry.
- **`.noMatch`** → straight to manual predictive search, not an error dead end.
- All Vision work runs off the main thread; the UI never spins or blocks on a snap.

## 9. Testing strategy

- **Mac-testable (`swift test`, no simulator):**
  - `VisionLabelReader`: a real OCR pass against a **bundled invented-label fixture PNG**
    (carrier-agnostic placeholder address), asserting recognized lines / barcodes.
  - `SnapViewModel`: band routing, the `addParcel` call, and run auto-generation, driven by a
    stub `LabelReading` and an in-memory database — no camera.
  - `SnapPipeline` / `AddressMatcher` / normalizer / keyword detector: already covered.
- **Device-only (manual checklist):** actual camera capture + live OCR accuracy on real
  rural labels, since the camera cannot run in `swift test` or the Simulator.

## 10. Vision API note (resolve at plan time, not in this spec)

The exact Vision symbol — modern iOS 18 Swift `RecognizeTextRequest` vs legacy
`VNRecognizeTextRequest` (and the matching barcode request) — will be confirmed against the
iOS 18 SDK via the Axiom Vision docs when writing the implementation plan. This spec stays at
the **configuration-intent** altitude (no language correction + custom vocabulary +
en-CA / fr-CA + accurate level + barcode cross-check) so it remains correct regardless of
which API the SDK exposes on the iOS 18 deployment target.

## 11. Documentation follow-ups (per CLAUDE.md / AGENTS.md)

When this lands, update:
- Master design spec `docs/superpowers/specs/2026-06-22-routey-design.md` §7 — note Snap-to-Add
  UI shipped, the in-memory candidate sourcing (no FTS blocking yet), and the customWords
  seeding from route street names.
- Roadmap `docs/superpowers/plans/2026-06-25-routey-roadmap-execution.md` — mark the M4 camera
  UI / M5 Snap-to-Add UI items addressed.

## 12. Carrier-agnostic guarantee

All fixtures, sample labels, and test addresses use invented placeholders only (no employer
name, real street/site names, or civic numbers), per the public-repo rule in CLAUDE.md and
AGENTS.md.
