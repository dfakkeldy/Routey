# Routey — Design Spec (V1.0)

- **Date:** 2026-06-22
- **Status:** Product design plus implementation checkpoint
- **Author:** Dan Fakkeldy (rural mail carrier & creator), with Claude
- **Scope of this doc:** the full product vision + the V1.0 cut line + the technical architecture to build it.

---

## 1. Summary

Routey is an **offline-first iOS app for rural mail carriers** that replaces the
notebook-and-scanner workflow with **sort → snap → deliver**, built around the carrier's
master route. V1.0 is scoped as an iPhone app with on-device OCR; a watchOS companion
(V1.1) and CarPlay navigation (V1.2) reuse the same shared code and data after the
iPhone app is ready.

The app is privately validated against real-world rural delivery workflows; committed
fixtures and public examples use invented rural-style data only. The guiding rule: **if
it doesn't save time in the truck, it doesn't ship.**

### Implementation status, 2026-06-28

The current `nightly` train has the tested package-first foundations for the V1.0
workflow: route import/edit/search, the headless OCR matcher, Today's Run domain
operations, history search, report content, and encrypted route handoff. The visible
Today's Run screens, camera Snap-to-Add UI, PDF/print/share UI, encrypted file UI,
Production CloudKit schema deployment, and production-device release testing are still
open gates.

The sync decision is to proceed with SQLiteData + private CloudKit under append-only
schema discipline unless the remaining manual graph matrix reveals a hard failure.

---

## 2. Goals & non-negotiables

These constraints shape every decision below:

1. **Offline-first.** Every feature works in a dead zone. Nothing blocks on signal.
   Sync/backup is a background nicety layered on top of a local source of truth.
2. **Speed.** Built for the pace a carrier sorts at — instant predictive search,
   one-tap delivery logging, no spinners.
3. **Privacy.** Route data (addresses, dog warnings, customer flags) is sensitive.
   It stays on-device and in the carrier's own private iCloud; it only leaves the
   device as a deliberately **encrypted** file the carrier chooses to share.
4. **A living route.** The route changes constantly and official artifacts (tie-out
   sheet, case strips) lag reality. Routey is the carrier's living source of truth and
   can **regenerate those artifacts on demand**.

---

## 3. Users

- **Primary:** the route holder — a rural/suburban mail carrier (e.g. a contracted rural route)
  who knows their route and wants to work faster and stop relying on paper + memory.
- **Secondary:** the **relief carrier** — someone covering a route they don't know.
  They receive the route as an encrypted file, import it read-only ("borrowed"), and
  rely on full detail (every stop, tag, dog warning, slot).

---

## 4. Scope

### V1.0 — iPhone
- Master Route management (create/import/edit), always editable (route is living).
- Full domain model: Stops, Delivery Points (boxes/compartments), CMB sites with
  Modules, Addresses, Tags, shared boxes, clustered roadside boxes.
- **Virtual Sort Case** — search + membership + slot lookup; shared-slot disambiguation;
  per-slot color flags + notes.
- **OCR Snap-to-Add** (flagship) — photograph a parcel label → extract address +
  keywords (incl. **Signature**, customs) → match to route → add to Today's Run in
  delivery order. Running "today's signatures" count/list.
- **Today's Run** — daily working instance: reorderable drive sequence, parcel loading,
  progress/check-off (incl. last-stop bulk check-off), rich delivery outcomes,
  cross-stop follow-up tasks. Archived to History nightly.
- **Proof of delivery** — outcome + GPS + timestamp + optional photo (file-referenced).
- **History / Delivery Intelligence** — full-text searchable past deliveries (by
  address, date, tag, photo), flag/dog filters.
- **Setup/import** — CSV (Reminders export) + **sort-case photo OCR**, plus manual
  build/edit. Tie-out sheet is a helpful reference, not required.
- **Print / Reports** (PDF + AirPrint) — **tie-out sheet**, **case strips**, and
  **filtered lists** (e.g. all `no-flyers`, parcels delivered on a date).
- **Encrypted `.routey` export/import** for relief handoff (sole sharing mechanism).
- **Private iCloud sync** for backup + multi-device, fully offline-capable.

### V1.1 — watchOS (deferred, but designed-for now)
- Next stop on the wrist, dog/warning alerts, one-tap delivery log, auto-advance.

### V1.2 — CarPlay (deferred, but designed-for now)
- Turn-by-turn stop-to-stop on the dash. Requires per-stop GPS coordinates
  (geocoded once at route-build time and synced).

### Explicitly out of scope (and why)
- **CloudKit record *sharing*** — cannot carry Routey's multi-parent / many-to-many
  graph; the encrypted file is the handoff path instead.
- **Automated parsing of the official route-doc table** — dense bilingual multi-column
  table OCR is the single hardest feature; candidate for a V1.x power-import.
- **Argon2id/scrypt KDF** — not native to Apple platforms; PBKDF2 ships now, header
  reserves a slot to upgrade later.
- **Foundation Models address extraction** — optional accelerator layered on later; the
  deterministic matcher is the V1.0 backbone.
- **Chunked/streaming encryption & full History-archive lifecycle** — the single-shot
  `.routey` export is sized for a route handoff; large-archive strategy is a later design.

---

## 5. Domain data model

The core realization: **separate the receptacle from the address.** A *Delivery Point*
(box/compartment) is a different thing from an *Address* (customer/door), and the
relationship between them is many-to-many.

### Entities

**Route** — the master template (what syncs, what gets exported).
Fields: id (UUID), name, RTA/FSA, metadata.

**Stop** — a place the carrier physically stops, in drive order.
Fields: id, route, **tieOut** code (`33`, `20`), **sortIndex** (fractional/gap-based for
cheap reordering), **kind** (`pointOfCall` | `rmbCluster` | `cmbSite` | `doorVisit`),
**displayName** (nickname — "Cornerstore", "The Manor"), optional officialSiteId (`A1A1001`)
+ locationText + sharesLocationWith, optional GPS, notes.
Holds one or more **Delivery Points** (and, if `cmbSite`, **Modules**).

**Module** (CMB sites only) — groups compartments within a site. Ordered.

**Delivery Point** — the actual receptacle.
Fields: id, stop, optional module, **kind** (`roadsideBox` | `compartment`),
label (box #, or module+compartment + tie-out letter), isParcelLocker,
**status** (`active` | `vacant` | `closed` — the "CLOSED/FERMÉ" inserts), notes,
color flags. **Serves one or more Addresses** (shared box/compartment).
Vacant/closed points are excluded from flyer/parcel roll-ups.

**Address (point of call / customer)** — the customer and their door.
Fields: id, civic number (+ optional civic range from/to, + suite), street,
**occupant name(s)** (optional), **door location** (may be far from the box), postal/FSA,
optional GPS (geocoded once), tags, notes. Linked to its Delivery Point(s).
At multi-unit buildings/complexes (e.g. the Elm St seniors complex) many addresses share
one civic number and are **disambiguated by occupant name**.

**Tag** — extensible flag. Fields: id (UUID primary key), canonical name, warning flag.
Canonical-name reuse is enforced in app/domain logic, not with a synced database `UNIQUE`
constraint (see §7). Examples: `no-flyers`, `dog`, `scary-dog`, `don't-card`,
`signature`, `customs`, `catalogue`. Some are **warning-class** → surfaced when the stop
is next or when a parcel for that address is scanned. Many-to-many with Address (join table).

### The four mailbox cases (all one shape)

| Real world | Model |
|---|---|
| Normal roadside box | Stop → 1 Delivery Point → 1 Address |
| Shared box/compartment | 1 Delivery Point → **N Addresses** |
| Clustered roadside boxes | Stop → **N Delivery Points**, addresses **located elsewhere** |
| CMB site | Stop → Modules → Delivery Points (compartments) → address(es) |

### Daily entities (one carrier, one device, per day)

**Today's Run** — generated from the Route for a date; a reorderable copy with
progress/check-off state. Single-device working instance (see §7). Archived to History.

**Parcel** — today's item on an Address. Source (OCR snap | manual), type/size,
goes-to-compartment vs door, flags (signature/customs auto-detected from the label).

**Delivery Record** — outcome (`delivered` | `safedrop` | `mailbox` | `inPerson` |
`notHome-carded` | `leftAtDoor` | `nextDay`) + GPS + timestamp + optional photo
(stored as an external **file reference**, not inline). Links to parcel/address.

**Follow-up Task** — cross-stop reminder (e.g. "drop notice card in Compartment M2-C7"),
spawned by a failed door attempt, surfaces at its target stop.

### Cross-cutting

**Virtual Sort Case** — on-screen mirror of the physical case: ordered slots labeled by
**civic # + tie-out**, each slot mapped to a Delivery Point (so a shared slot shows
**all** its civic numbers), with **per-slot color flags + notes**. Local + FTS-indexed
(derived data; excluded from sync, rebuilt from the graph).

**History** — archived runs + delivery records; full-text searchable.

**Notes** — first-class and quick-add at Stop / Delivery Point / Slot / Address level,
optionally colored. The digital replacement for the sticky-note layer.

**Reports** — query → formatted PDF: tie-out sheet, case strips, filtered lists.

---

## 6. Key workflows

### Setup / import (occasional)
1. **CSV import** (Reminders export) builds the Master Route's stop sequence + addresses.
2. **Sort-case photo OCR** bootstraps the Virtual Sort Case (slots, civic labels) and
   helps lay out CMB sites; the carrier fixes up.
3. **Manual build/edit** anytime — the route is always changing; editing is core, fast,
   and assisted by search.

### Morning — Sort
- Today's Run auto-generates from the Route.
- **Search a civic number** → instant: *is it on my route?* + *where does it go?* →
  shows nickname site / module / compartment (or box) + door + tags. Shared slots list
  all civic numbers they serve.

### Snap parcels (flagship)
- Photograph each label → Vision OCR reads address + keywords → matcher ranks candidates
  → adds Parcel to the right Address in delivery order. Ambiguous → one-tap confirm from
  a short list; low confidence → manual predictive-search fallback.
- **Signature/customs keywords** auto-flag the parcel and update a running
  **"Today: N signatures"** count/list — so the carrier knows before organizing.
- Each cluster/CMB stop header shows computed roll-ups: parcels per module, flyers per
  module (deliverable points − no-flyer addresses).

### Pre-drive — Plan
- View Today's Run through a **filter**: *full route* / *no-flyers + parcels* /
  *today's parcels* / *signatures*.
- **Reorder** (drag) for construction, weather, or to fit a door visit "when nearest";
  optionally promote a change to the Master if permanent.

### On route — Deliver
- **Next stop** front-and-center (what the V1.1 watch mirrors). Dog/scary-dog **warning**
  fires when that stop comes up.
- At a cluster/CMB: expand to delivery points; handle mail + parcels (box vs door).
- **Log outcome** per parcel/stop with GPS + timestamp + optional photo. A failed door
  signature **spawns a follow-up task** at the relevant CMB stop.
- **Bulk check-off:** tap the last stop to mark everything before it done.

### End of day
- Today's Run archives into **History**; a fresh Run generates tomorrow.

### Print / Reports (on demand)
- **Tie-out sheet** (route in delivery order), **case strips** (printable slot labels to
  replace worn strips), **filtered lists** (by tag/date/outcome) → PDF + AirPrint/share.

---

## 7. Technical architecture

### Build shape
- One Swift package **`RouteyKit`** (library targets only), consumed by thin app shells:
  `Routey` (iOS V1.0), `Routey Watch` (V1.1). **CarPlay is scenes inside the iOS target**
  (`CPTemplateApplicationSceneDelegate` + the `com.apple.developer.carplay-maps`
  entitlement), not a separate target.
- Modules, depending downward: **`RouteyModel`** (value-type `@Table` structs) ←
  **`RouteyPersistence`** (DatabaseWriter + SyncEngine config) ← **`RouteySearch`** (FTS5)
  + **`RouteyDomain`** (reorder, check-off state machine, follow-up tasks, roll-ups; pure
  Sendable) ← **`RouteyOCR`** / **`RouteyExport`** / **`RouteyNavigation`** (V1.2).
- iOS-only/Vision/CarPlay code guarded with `#if os(iOS)` so the watch target stays lean.

### Persistence + sync
- **SQLiteData** (Point-Free, built on GRDB) as the persistence + private-CloudKit-sync
  layer, behind the package boundary. Local SQLite is the **source of truth**
  (offline-first by construction); `SyncEngine(for:tables:)` is a background private-DB
  layer for backup + multi-device.
- **FTS5** powers predictive search and OCR-candidate blocking.
- **Globally-unique UUID primary keys** in all synced tables (never auto-increment).
- Foreign-key cascades in SQL, restricted to **`ON DELETE CASCADE` / `SET NULL` /
  `SET DEFAULT`** (RESTRICT / NO ACTION throw at SyncEngine construction).
- **Reorderable sequence = fractional/gap `sortIndex`** column (a reorder touches one row),
  never a native ordered relationship.
- **Confidence: medium** (young single-vendor library, last-write-wins-only conflict
  resolution). **First build step: a throwaway two-physical-device sync proof-of-concept**
  of the full graph (Route→Stop→Site→Module→Compartment→Address + Parcel + DeliveryRecord +
  many-to-many Tags), verifying parent-before-child arrival, cascade deletes, and a
  concurrent reorder, **before committing**. Fallback: Core Data + NSPersistentCloudKitContainer.

### Append-only synced schema (hard constraint)
- Once sync is live, **no rename/drop/retype of synced tables/columns**. Design the schema
  append-only from day one; pre-add watch/CarPlay-era columns now (e.g. per-stop GPS), or
  accept they must ship Optional later.
- **No non-PK UNIQUE constraints** on synced tables (they throw at sync init): promote
  natural keys (e.g. a Tag's canonical name) to primary keys, or enforce uniqueness in app
  logic + a **local** unique index.
- Reserve SQLiteData's real migration freedom for **local, non-synced tables** (FTS index,
  OCR caches, Virtual-Sort-Case derived data), which are excluded from the sync list and
  freely rebuildable.

### M0 schema audit checkpoint
- Current v1 synced tables are `routes`, `stops`, `modules`, `deliveryPoints`, `addresses`,
  `deliveryPointAddresses`, `tags`, and `addressTags`.
- `RouteyModel` table structs are explicitly `nonisolated` for strict Swift concurrency.
- `SchemaTests` verify table names and column lists, fresh-install migration idempotency,
  generated lowercase UUID defaults, absence of non-primary-key unique indexes, and
  CloudKit-compatible foreign-key delete actions.
- M0 decision: `Tag` keeps UUID `id` as its synced primary key. Canonical tag-name reuse is
  enforced in app/domain logic so user-visible tag labels can evolve without primary-key
  rewrites after sync is live.

### OCR pipeline (on-device, iPhone)
- `RecognizeTextRequest`: `.accurate`, languages `["en-CA","fr-CA"]`,
  **`usesLanguageCorrection = false`** (correction corrupts civic/RR/postal codes),
  `customWords` seeded with route street names + rural keywords (RR, CONC, HWY, LOT, SS,
  PO BOX), always pass EXIF orientation, read `topCandidates(3)`.
- `VNDetectBarcodesRequest` on the same frame as a high-confidence cross-check.
- `RecognizeDocumentsRequest` for the sort-case grid (structured boxes → rows/columns).
- All Vision work off the main thread.

**As-built (2026-06-29):** Snap-to-Add UI shipped using `VNRecognizeTextRequest` + `VNDetectBarcodesRequest`. Candidate sourcing loads all route addresses and scores them in memory (FTS-based blocking deferred until profiling warrants it). `customWords` seeded from the route's distinct street names + rural keywords (RR/CONC/HWY/LOT/SS/PO/BOX). Camera capture device-tested; the `.noMatch` manual fallback currently lets the carrier pick from ranked candidates (full predictive-search-to-add integration is a follow-up).

### Address matcher (pure Swift, no network/geocoding)
- `normalize → block → weighted-component-score → rank → threshold`.
- Normalize: diacritic folding + a bilingual Canadian postal abbreviation table (ST/RUE, AVE,
  RD/CH, HWY, CONC, RR, SS…); parse civic/unit/route number, rural designators, locality,
  postal code as first-class fields. Rural formats (RR 2, Conc Rd 6, Hwy 7 Lot 14,
  SS 1 Comp 5) are their own token types (often no civic number).
- **Numeric (civic) agreement is a gated, decisive factor** — a confidently-read mismatched
  number disqualifies the candidate ("12 Main" never matches "21 Main"). Street name =
  token-set overlap + Damerau-Levenshtein.
- **Occupant name as a disambiguator** — when the civic number is shared across many
  addresses (apartment/seniors complex), the parcel's recipient **name** (also read by OCR)
  selects the right address/compartment. Name matching is the tie-breaker once civic + street
  agree but resolve to multiple units.
- **Three-band confidence UX:** auto-accept (top ≥ ~0.90, margin ≥ ~0.15, number agrees;
  undoable toast) / disambiguation short-list (2–5, raw OCR shown, differing field
  highlighted) / manual predictive-search fallback.

### Encrypted `.routey` export/import
- **KDF:** PBKDF2-HMAC-SHA256 (CryptoKit has no password KDF; use CommonCrypto
  `CCKeyDerivationPBKDF` or swift-crypto `KDF.Insecure.PBKDF2`). Calibrate iterations to
  ~250–500ms on the slowest target, take `max(600k, calibrated)`, **store count in header**.
- **Encryption:** AES-256-GCM (`AES.GCM.seal/open`). Fresh random per-export salt
  (16–32B) + auto-generated 12B nonce (never reused/derived from passphrase).
- **Versioned header bound as GCM AAD:** magic `RTYE`, formatVersion, kdfID (1=PBKDF2,
  reserve 2=Argon2id), kdfIterations, salt, and a separate `payloadSchemaVersion`.
- Wrong passphrase → `authenticationFailure` (that *is* the signal; no plaintext verifier).
- Plaintext = Codable DTOs of the Route graph, **kept separate from persistence models** so
  the file format versions independently. Imported routes are marked **borrowed / read-only**.
- Custom `.routey` UTType + `FileDocument`/`Transferable` for AirDrop/Files/Mail.

### iOS ↔ watch (V1.1) & CarPlay (V1.2) data paths
- watch: CloudKit (same private store) is the **primary** path (works on an independent
  watch); **WatchConnectivity** opportunistically for the live Today's Run snapshot/events,
  never the sole path. Share an **App Group** across app/watch/widgets.
- CarPlay: persist each Stop/Address `CLLocationCoordinate2D` at route-build time (geocode
  once, sync it — never live-geocode hundreds of addresses); `MKDirections` legs between
  consecutive stops; all UI via templates.

---

## 8. Error handling & edge cases

- **Offline:** all features work; sync is best-effort background. Surface a quiet sync
  status, never block the UI.
- **OCR ambiguity:** three-band UX above; never silently mis-assign a parcel.
- **Wrong export passphrase:** `authenticationFailure` → clear "wrong passphrase" message.
- **Malformed CSV import:** row-level review/skip, not all-or-nothing failure.
- **Sync conflicts:** last-write-wins; Today's Run is single-device-per-day to avoid
  ordered-data merge hazards; the Master Route tolerates field-wise LWW.
- **CloudKit Development vs Production schema:** "Deploy Schema Changes + test against the
  Production scheme" is on the pre-release checklist for **every** release (the #1
  first-submission failure).
- **CarPlay with phone locked:** the route DB must use an available-while-locked file
  protection class (and Keychain accessibility) or it's unreadable in the car; the
  export-passphrase key is gated separately.

---

## 9. Testing strategy

- **Swift Testing** throughout.
- **Address matcher** — the highest-value unit tests: a fixture corpus of invented
  rural-style Canadian addresses (civic, RR, Conc Rd, Hwy+Lot, shared boxes, near-miss numbers)
  asserting normalization, gated numeric logic, ranking, and the confidence bands.
- **Encrypted export round-trip** — encrypt→decrypt equality; wrong-passphrase failure;
  header/version handling; tamper → auth failure.
- **Domain logic** — reorder/gap-index correctness, check-off + bulk check-off, follow-up
  task spawning, CMB roll-up math (parcels/flyers per module, shared-box counting).
- **Sync** — the two-device full-depth PoC (gating the architecture), then regression
  coverage for parent-before-child and cascade deletes.
- **OCR** — sample label + sort-case images as fixtures (recognition is on-device/
  deterministic enough to snapshot candidate output).
- **Key flows** — snapshot/UI tests for sort, snap, deliver, and print output.

---

## 10. Top risks (carry into the plan)

1. **CloudKit Dev/Prod schema split** — silent zero-results in production if not deployed.
2. **SQLiteData is young + LWW-only conflict resolution** — correctness hazard for ordered
   data; mitigated by single-device Today's Run + gap indexing + the 2-device PoC gate;
   confidence **medium**.
3. **CloudKit sharing unusable for this graph** — encrypted file is the only handoff.
4. **Append-only synced schema** — UUID PKs everywhere, no non-PK uniqueness, no
   rename/drop/retype after sync is live.
5. **CarPlay runs with the phone locked** — file-protection class must allow it.

---

## 11. Open questions & assumptions

- **Flyer counting on shared boxes:** default per-address, with a per-point "shared — one
  flyer" toggle. *(Confirm.)*
- **Civic ranges (from/to):** modeled as a range on an Address, usually from == to.
  *(Confirm semantics on multi-civic roadside entries.)*
- **No two devices edit the same day's run simultaneously.** Master Route still syncs across
  devices normally.
- **Delivery photos kept lean** (file-referenced, not inline) for healthy sync/backup.

---

## 12. First implementation step

Before committing to SQLiteData, build a **throwaway two-physical-device sync
proof-of-concept** of the full graph + many-to-many Tags + a concurrent reorder. If it
holds up, proceed; if not, fall back to Core Data + NSPersistentCloudKitContainer (same
package structure, same model, same constraints).
