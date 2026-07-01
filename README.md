# Routey

**Rural mail carrier logistics — built from the truck, not the boardroom.**

Routey is an offline-first iOS app for rural delivery workflows, with watchOS
and CarPlay planned after the iPhone app is ready. The product direction is
simple: sort -> snap -> deliver.

## Why Routey?

Official handheld tools are slow, broken, and designed by people who've never run a rural route. Routey is built by a carrier who lives the problem every day.

## Current Nightly

- SQLiteData/GRDB local database with private CloudKit sync hooks.
- Route import, route editing, and local predictive search in the iOS shell.
- Camera Snap-to-Add with Vision OCR/barcode reading and route address matching.
- Today's Run drive-loop UI with check-off, stop detail, parcel/warning badges,
  and drag reorder.
- Tested package cores for OCR matching, Today's Run generation/operations,
  history search, report content, and encrypted route handoff.
- Release automation can build, upload, process, and distribute nightly builds
  to internal TestFlight testers.

## Still In Progress

- Proof-of-delivery/outcome logging UI, run filters, PDF/print/share, and
  encrypted `.routey` file UI.
- Production CloudKit schema deployment and production-device release testing.
- External TestFlight/App Store metadata, screenshots, privacy nutrition labels,
  age rating, review notes, and final support/privacy pages.
- watchOS and CarPlay surfaces.

## Status

Early development. The package-first nightly train is green, but V1.0 is not
yet App Store-ready. Landing page live at
[dfakkeldy.github.io/Routey](https://dfakkeldy.github.io/Routey).

## Project Docs

- [Architecture](ARCHITECTURE.md) — module boundaries, persistence rules, app
  shell, release train, and App Store constraints.
- [Roadmap](ROADMAP.md) — current V1.0 status and remaining release gates.
- [App Store next steps](docs/release/app-store-next-steps.md) — the next ten
  concrete tasks required before first submission.
- [Branch/worktree audit](docs/release/branch-worktree-audit.md) — cleanup and
  salvage map for current local/remote branches and worktrees.
- [Build devlog](docs/guides/devlog.md) — weekly generated public build record.
- [Fastlane setup](fastlane/SETUP.md) — local credentials, metadata, TestFlight,
  and release-train commands.

## Release Engineering — Promotion Ladder

Routey uses a one-way promotion ladder: `feature/*` → `nightly` → `weekly` → `main`.
Feature work branches from `nightly`, and normal PRs target `nightly`. `weekly` is promoted from `nightly`, and `main` is the stable default branch promoted only from `weekly`.

| Branch | Purpose | Required protection |
| --- | --- | --- |
| `nightly` | Integration and daily TestFlight train | `Build gate + tests` |
| `weekly` | Weekly beta train | Strict `Build gate + tests`; review approval optional |
| `main` | Stable App Store release base | Strict `Build gate + tests`; review approval optional |

Hotfix exception: branch from `main`, PR to `main`, then merge `main` back down into `weekly` and `nightly`.

## License

GPL-3.0 — see [LICENSE](LICENSE). An App Store distribution exception applies; see [LICENSE-APP-STORE-EXCEPTION.md](LICENSE-APP-STORE-EXCEPTION.md).
