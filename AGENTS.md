# Routey

Public, offline-first iOS app for rural mail carriers: sort, snap, deliver.
The flagship flow photographs a parcel label, extracts address signals, ranks
candidates deterministically, and adds a stop in delivery order. `RouteyKit`
holds the model, persistence, search, OCR, export, and navigation logic; the
app targets are thin shells.

Dan is the authority on route operations. When a workflow detail affects the
product, ask Dan rather than assume generic carrier practice. Features
should save time in the truck.

## Privacy (public repo)

Never commit or paste into chat an employer name, real route details,
addresses, street or place names, civic numbers, photos, device identifiers,
or carrier-specific jargon. That covers code, tests, fixtures, screenshots,
logs, docs, commits, and PR text. Use invented placeholders. Live route data
stays on the device.

## Commands

```bash
cd RouteyKit && swift build && swift test
```

Package and simulator tests don't prove CloudKit sync or locked-phone
behavior; don't claim they do.

## Stack

iOS 18 app; `RouteyKit` also supports iOS 17 and macOS 14 so tests run on the
Mac. Swift 6, SwiftUI, SQLiteData/GRDB, private CloudKit, Vision, Swift
Testing. watchOS and CarPlay are deferred; don't build for them yet. Ask
before adding a third-party dependency.

## Data rules

- Local SQLite is the source of truth. CloudKit sync is background backup;
  user flows never wait on the network.
- Delivery Point (the receptacle) and Address (the customer) are separate and
  many-to-many.
- Synced tables use globally unique primary keys, no other unique constraints,
  and no unsupported foreign-key actions. Once sync is live, schema changes
  are additive only (new tables, optional or defaulted columns). Rebuildable
  derived data goes in local, non-synced tables.
- Ordered sequences use a `sortIndex` column.
- Encrypted `.routey` transfer DTOs are separate from persistence models.
  Imported borrowed routes are read-only.
- Use parameterized SQL or StructuredQueries, never string interpolation.
- Prefer concrete types and in-memory databases in tests over protocol/mock
  layers.

## Branches

`feature/*` → `nightly` → `weekly` → `main`. Feature PRs target `nightly`.
Hotfixes branch from `main` and are merged back down. Open promotion PRs only
when asked.
