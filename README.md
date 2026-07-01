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

## Still In Progress

- Proof-of-delivery/outcome logging UI, run filters, PDF/print/share, and
  encrypted `.routey` file UI.
- Production CloudKit schema deployment and production-device release testing.
- watchOS and CarPlay surfaces.

## Status

Early development. The package-first nightly train is green, but V1.0 is not
yet App Store-ready. Landing page live at
[dfakkeldy.github.io/Routey](https://dfakkeldy.github.io/Routey).

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
