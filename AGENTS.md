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

Simulator and package tests do not establish physical-device CloudKit sync or
locked-phone behavior. That distinction is not a gate for routine PRs, merging,
or nightly delivery; device testing follows the policy below. Instruction-only
edits do not require a package or app build.

## Repository workflow

- Routey uses `feature/* -> nightly -> weekly -> main`.
- Normal feature work branches from and opens a PR to `nightly`. Promotions are
  separate PRs and should be opened only when requested.
- Hotfixes branch from and PR to `main`, then flow back to `weekly` and `nightly`.
- Never push directly to protected branches.
- Inspect branch, upstream, and working tree before editing. Preserve unrelated
  changes and user-owned history.
- Use coherent Conventional Commits; do not auto-rebase or force-push as a
  standing rule.
- Requested repository changes finish with a ready PR and auto-merge on green
  required CI, using the supported merge method and respecting branch protections.
  If native auto-merge is unavailable, merge the verified PR head normally after
  reported checks pass. If CI is absent or blocked, leave the ready PR and report
  that limitation once. Do not ask for another merge approval for ordinary work.
- Report local tests, hosted CI, merge, deployment, and device acceptance as
  separate states.

## Device testing and nightly delivery

Routine native changes finish with the PR and green-CI merge; the established
nightly pipeline handles delivery to the Nightly TestFlight group. The user relies
on automatic updates and tests when convenient, possibly days or weeks later.
Do not request device verification, append manual acceptance checklists, send
reminders, or block subsequent changes because earlier builds remain untested.
Run proportionate automated/simulator checks and fix device issues when reported.
Overnight iPhone testing is optional, only when the user offers it for that session.

Do not claim device behavior or installation was verified without evidence.
Explicitly requested device investigations may need specific device evidence;
ordinary uncertainty is not a completion gate. Weekly/stable promotion and public
release remain separate, explicitly requested work.
