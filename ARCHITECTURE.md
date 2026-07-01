# Routey Architecture

Routey is an offline-first iOS app backed by a Swift package, `RouteyKit`.
The current product cut is iPhone-first. watchOS and CarPlay are planned after
the V1.0 phone workflow is real and tested.

## Platform and Toolchain

- App target: iOS 18.0.
- Package floors: iOS 17 and macOS 14 so `RouteyKit` tests run on the Mac.
- Swift tools and language mode: Swift 6.0.
- CI and release trains currently select Xcode 26.5 on `macos-26`.
- App bundle ID: `com.danfakkeldy.routey`.
- Private CloudKit container: `iCloud.com.routey.app`.

## Package Layout

`RouteyKit` is a package of library targets consumed by thin app shells:

| Target | Role |
| --- | --- |
| `RouteyModel` | SQLiteData table models and shared model types. |
| `RouteyPersistence` | SQLite migrations, local database setup, CloudKit sync configuration. |
| `RouteyImport` | Tolerant route parsing from pasted or CSV-like route text. |
| `RouteySearch` | Local-only FTS5 index and predictive route search. |
| `RouteyDomain` | Testable workflows: import, editing, run generation, run operations, history, reports. |
| `RouteyOCR` | Label reading seams, OCR normalization, address matching, Snap-to-Add mapping. |
| `RouteyExport` | Versioned encrypted `.routey` handoff envelopes and DTO mapping. |

Dependencies flow downward through the package. Derived surfaces such as search
stay rebuildable and local-only; synced model tables remain the source of truth.

## App Shell

The iOS app under `app/Routey/Routey` owns SwiftUI presentation and device-only
adapters:

- `Routes` screens handle import, route browsing, stop detail, address editing,
  and tag picking.
- `Search` exposes local predictive lookup against the rebuilt FTS index.
- `Run` exposes the initial Today's Run drive-loop UI: generate/load a run,
  inspect progress, check off one stop, mark done-through-here, view stop
  detail, and drag reorder.
- `Snap` owns AVFoundation camera capture, Vision text/barcode reading, and the
  three-band confirmation UI that feeds `RouteyOCR` and `RouteyDomain`.
- `RouteyMacProof` is a temporary proof client for Mac+iPhone private CloudKit
  validation. It is not the shipping Mac product.

Shared UI state should stay in `@MainActor @Observable` types or view-owned
`@State`. Business rules stay in `RouteyDomain` or focused app view models so
they remain testable.

## Persistence and Sync

Local SQLite is the source of truth. Private CloudKit sync is a background
backup and multi-device nicety; UI work must not block on network availability.

Routey uses SQLiteData on top of GRDB and StructuredQueries. Synced schema is
under append-only discipline:

- UUID primary keys on synced tables.
- No non-primary-key uniqueness constraints on synced tables.
- No rename, drop, or retype of synced tables/columns after sync is live.
- Add only new synced tables or optional/defaulted synced columns.
- Reorderable lists use gap/fractional `sortIndex` writes, not native ordered
  relationships.
- Local-only derived data such as FTS indexes stays out of the sync list and may
  be rebuilt freely.

Today's Run remains a single-device-per-day product rule until remaining
ordered-sync behavior is documented across devices.

## Security and Privacy

The repository is public and carrier-agnostic. Do not commit employer names,
real route data, real street/site/place names, civic numbers, or carrier-specific
jargon. Fixtures, screenshots, docs, and metadata must use invented placeholders.

Routey currently declares camera usage for label OCR and CloudKit entitlements
for private sync. It sets `ITSAppUsesNonExemptEncryption` to `false`, because
the current encryption use is Apple/standard platform encryption for HTTPS,
CloudKit, Keychain-style storage, and CryptoKit/CommonCrypto-based handoff.
Before App Store submission, regenerate the aggregate privacy report and match
the App Store privacy answers to the actual release build.

## Release Train

Normal work flows one way:

`feature/*` -> `nightly` -> `weekly` -> `main`

`nightly` is the integration branch and internal TestFlight train. `weekly` is
the beta promotion branch. `main` remains stable and is also the GitHub Pages
source (`main /`). The release workflow lives on `main`, checks out the selected
train branch, builds with Xcode 26.5, validates package/app compilation, and
uploads through fastlane when the required secrets are present.

Current upload proof: a manual `nightly` release-train run on July 1, 2026 built
and processed Routey `0.1 (4)`, then fastlane distributed it to internal testers.
That proves the internal TestFlight lane, not App Store submission readiness.

## App Store Readiness Boundary

Routey is not App Store-ready until these gates are complete:

- Production CloudKit schema deployment and production-device validation.
- Airplane-mode end-to-end sort -> snap -> deliver -> history -> export smoke.
- Proof-of-delivery/outcome UI, run filters, PDF/print/share, and `.routey` file
  UI decisions/implementation.
- Final App Store screenshots, app icon validation, privacy answers,
  accessibility nutrition labels, age rating, support/privacy pages, and review
  notes.
- Pricing/free-vs-paid decision and marketing plan sign-off.
