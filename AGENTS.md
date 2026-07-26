# Agent guide for Routey

Routey is a public, offline-first iOS app for rural carriers: sort, snap, and
deliver. `RouteyKit` holds the model, persistence, search, domain, OCR, export,
and navigation logic used by thin app shells.

## Privacy boundary

- Keep every committed file carrier-agnostic. Never commit an employer name,
  real route details, addresses, street/site/place names, civic numbers, photos,
  device identifiers, or carrier-specific jargon.
- Use invented placeholders in code, tests, fixtures, screenshots, logs, docs,
  issue text, and PR text.
- Keep live route data strictly local. Do not print or paste it into chat,
  commands, build logs, or public artifacts.

## Product and platform boundaries

- The app targets iOS 18. `RouteyKit` supports iOS 17 and macOS 14 so package
  tests run on the Mac.
- The current stack is Swift 6, SwiftUI, SQLiteData/GRDB, private CloudKit,
  Vision, and Swift Testing.
- SQLite is the offline source of truth. CloudKit sync is background backup and
  multi-device support; user flows must not wait for the network.
- watchOS and CarPlay are deferred. Do not prebuild speculative abstractions or
  product behavior for them. Guard genuinely iOS-only framework code where
  package compilation requires it.
- Do not introduce a new third-party dependency without user authorization.

## Domain and persistence invariants

- Keep Delivery Point (the receptacle) separate from Address (the customer or
  door); their relationship is many-to-many.
- Synced records use globally unique primary keys. Avoid non-primary-key unique
  constraints and unsupported foreign-key actions.
- Once CloudKit sync is live, synced schema changes are additive: new tables and
  optional/defaulted columns. Keep freely rebuildable derived data in local,
  non-synced tables.
- Use parameterized or StructuredQueries, never interpolated SQL. Keep database
  work off the UI actor.
- Reorderable sequences use `sortIndex`; do not model them as native ordered
  relationships.
- Keep encrypted `.routey` transfer DTOs separate from persistence models so the
  file format can version independently. Imported borrowed routes remain
  read-only.

## Implementation guidance

- Follow the established architecture in the touched module. Modules depend
  downward from model and persistence into search/domain and feature modules.
- Prefer concrete constructor injection and in-memory databases for tests. Add a
  protocol only for a real alternative implementation or wired test double.
- Keep SwiftUI views focused on presentation and lightweight interaction; place
  domain behavior in testable types.
- Use structured concurrency and current APIs available at the deployment
  target. Do not turn a focused change into unrelated modernization.
- Read the relevant design or plan before architecture or data-model work.
  Update documentation only when a change makes the current description
  inaccurate.

## Verification

For package changes, start with the narrowest relevant Swift Testing filter and
use the full package gate when warranted:

```bash
cd RouteyKit
swift build
swift test
```

CloudKit sync and locked-phone behavior require explicit physical-device proof;
a simulator or package test is not equivalent. Instruction-only edits do not
require a package or app build.

## Repository workflow

- Routey uses `feature/* -> nightly -> weekly -> main`.
- Normal feature work branches from and opens a PR to `nightly`. Promotions are
  separate PRs and should be opened only when requested.
- Hotfixes branch from and PR to `main`, then flow back to `weekly` and `nightly`.
- Never push directly to protected branches.
- Inspect branch, upstream, and working tree before editing. Preserve unrelated
  changes and user-owned history.
- Use coherent Conventional Commits. Publish when the task type and user request
  call for it; do not auto-rebase or force-push as a standing rule.
- Report local tests, hosted CI, merge, deployment, and device acceptance as
  separate states.
