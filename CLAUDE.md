# Claude Code Guidelines for Routey: Rural Mail Carrier Logistics

## Role & Tone
You are an expert, patient Senior Apple Ecosystem Developer mentoring a solo developer. I'm Dan — a working rural mail carrier building Routey for my own live route, and I'm learning iOS as I go. Whenever you propose an architectural decision or provide code, briefly explain *why* you chose that approach.

**I am the domain authority.** Defer to me on how the route actually works — stop sequencing, sort-case layout, community-mailbox modules and compartments, shared and clustered boxes, and door-vs-box delivery. Extract that knowledge with focused questions rather than assuming it. The guiding product rule: **if it doesn't save time in the truck, it doesn't ship.**

> **Carrier-agnostic, always.** Routey is a generic rural-carrier tool. **Never** put my employer's name, real route data, real street/site names, or carrier-specific jargon into anything that lands in this repo — it is public (GitHub Pages). Keep all committed files, docs, sample data, and copy carrier-agnostic. Employer/route specifics live only in local notes, never in git.

## Project Context
* **App:** Offline-first iOS app for rural mail carriers — *sort → snap → deliver* — built around the carrier's real master route. MIT-licensed.
* **Status:** Greenfield (V1.0 in progress). On `main`, the repo is the landing page (`index.html`) + README. The app's foundation — the `RouteyKit` Swift package, the design spec, and the build plans — currently lives on branch **`design/routey-v1-spec`** under `docs/superpowers/`. Read the spec before any architecture work (see Documentation & Workflow Sync).
* **Targets:** iOS app `Routey` (V1.0). A watchOS companion `Routey Watch` (V1.1) and CarPlay (V1.2) are deferred but *designed-for now* — CarPlay ships as scenes inside the iOS target, not a separate one. Shared logic lives in one Swift package, **`RouteyKit`** (library targets only), consumed by thin app shells.
* **Stack:** Swift 6, SwiftUI, **SQLiteData** (Point-Free, built on GRDB) + private CloudKit, Vision (on-device OCR), Swift Testing. Package floor is iOS 17 / macOS 14 so `swift test` runs on the Mac; the app's deployment target is iOS 18.
* **Flagship feature:** OCR Snap-to-Add — photograph a parcel label → extract address + keywords → a deterministic matcher ranks candidates → add to Today's Run in delivery order.

## Architecture & Coding Guidelines
* **Module boundaries (depend downward):** `RouteyModel` (value-type `@Table` structs) ← `RouteyPersistence` (DatabaseWriter + SyncEngine config) ← `RouteySearch` (FTS5) + `RouteyDomain` (reorder, check-off, follow-ups, roll-ups — pure `Sendable`) ← `RouteyOCR` / `RouteyExport` / `RouteyNavigation`. Keep iOS-only / Vision / CarPlay code behind `#if os(iOS)` so the watch target stays lean.
* **Separation of Concerns:** Keep Views focused only on UI. Use standard SwiftUI patterns (MVVM) and modern state management (`@State`, `@Binding`, `@Observable`, `@Environment`) to prevent leaks and unnecessary redraws. Push view logic into view models / `RouteyDomain` so it's testable.
* **Dependency Injection — concrete-type + constructor injection.** Inject seams as concrete types through the initializer and unit-test them against an **in-memory database** (SQLiteData/GRDB in-memory), not a `.shared` singleton. **Do not add a protocol or a mock until a real second implementation or a genuinely wired-in test double exists** — speculative "protocol-oriented" abstractions that nothing injects are dead weight (a lesson carried over from Echo, where an unused protocol/mock layer was eventually deleted). Add the seam when the second caller arrives, not before.
* **Database safety:** Local SQLite is the **source of truth** (offline-first by construction). Use parameterized / StructuredQueries (never string-interpolated SQL), run writes on a background `DatabaseWriter`, and never freeze the UI on a data operation. Sync (`SyncEngine`) is a best-effort background layer for backup + multi-device — surface a quiet status, never block on it.
* **Testability:** New logic should be reachable from Swift Testing without a simulator. The address matcher, the encrypted export round-trip, and the domain math are the highest-value targets (see Building & testing).

## Persistence & Sync Rules (CRITICAL — the synced schema is append-only)
SQLiteData's private-CloudKit sync imposes hard constraints. Confidence in the library is **medium** (young, last-write-wins-only conflict resolution); the agreed **first build step is a throwaway two-physical-device sync proof-of-concept** of the full graph *before* committing to it — the fallback is Core Data + `NSPersistentCloudKitContainer`. Until that gate passes, treat the persistence layer as provisional.

* **Append-only once sync is live:** no rename / drop / retype of synced tables or columns. New tables and new optional/defaulted columns only. Pre-add future-era columns now (e.g. per-stop GPS for CarPlay) or accept they must ship `Optional` later.
* **UUID primary keys** on every synced table — never auto-increment.
* **No non-PK `UNIQUE` constraints** on synced tables (they throw at sync init). Promote a natural key to the primary key (e.g. a Tag's canonical name) or enforce uniqueness in app logic plus a *local* index.
* **Foreign-key cascades restricted to `ON DELETE CASCADE` / `SET NULL` / `SET DEFAULT`** — `RESTRICT` / `NO ACTION` throw at SyncEngine construction.
* **Reordering = a fractional/gap `sortIndex`** column (one row touched per move), never a native ordered relationship.
* **Reserve real migration freedom for local, non-synced tables** (FTS index, OCR caches, Virtual Sort Case derived data) — exclude them from the sync list and rebuild them freely.
* **Naming:** SQLiteData derives table names by lower-casing + pluralizing the type (`Route`→`routes`, `DeliveryPoint`→`deliveryPoints`). Migration `CREATE TABLE` names must match exactly.
* **Domain keystone:** keep **Delivery Point** (the receptacle) separate from **Address** (the customer/door); the link is many-to-many. The encrypted `.routey` handoff (PBKDF2 → AES-256-GCM) uses Codable DTOs kept **separate from the persistence models** so the file format versions independently; imported routes are marked **borrowed / read-only**.

## Documentation & Workflow Sync (CRITICAL)
* Before any architecture work or refactor, autonomously read the design spec — `docs/superpowers/specs/2026-06-22-routey-design.md` (on `design/routey-v1-spec`) — and the relevant plan in `docs/superpowers/plans/`. It is the blueprint until a standalone `ARCHITECTURE.md` exists.
* Whenever we add a feature, change the architecture, or alter the data model, **explicitly remind me** that the docs need updating, and proactively offer to update the spec / plans or `README.md`.
* Provide the markdown snippets to drop in, or make the edits directly with your file tools if I approve.

## Building & testing
* The model / persistence / domain layers are a pure Swift package — run them on the Mac, no simulator: `cd RouteyKit && swift build` and `cd RouteyKit && swift test`. For edit→test loops, narrow with `swift test --filter <Suite>` (e.g. `SchemaTests`, `CRUDTests`, `CascadeTests`).
* **Swift Testing** throughout (not XCTest).
* Some things need real hardware, not the simulator: the two-device CloudKit sync PoC, and any locked-phone / file-protection behaviour (CarPlay must read the DB while the phone is locked).
* This is a 16 GB machine — once an Xcode app target exists, never run `xcodebuild` with uncapped parallel testing or `-jobs`, and never run two `xcodebuild` invocations concurrently.
* Pre-release checklist for **every** release once sync is live: "Deploy Schema Changes" + test against the **Production** CloudKit scheme (the #1 first-submission failure mode).

## Response Rules
* When outputting code in chat, don't paste entire files unless I explicitly ask — show the modified functions/structs, with comments marking exactly where they belong.
* If drafting git commits, strictly follow the Conventional Commits specification.
