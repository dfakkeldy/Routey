# Routey

**Rural mail carrier logistics — built from the truck, not the boardroom.**

Routey is an iOS + watchOS app that streamlines parcel management and delivery for rural mail carriers. It replaces the notebook-and-scanner workflow with three steps: sort, snap, deliver.

## Why Routey?

Official handheld tools are slow, broken, and designed by people who've never run a rural route. Routey is built by a carrier who lives the problem every day.

## Key Features

- **📸 OCR Snap-to-Add** — Photograph a parcel label, auto-match to route order
- **⌚ watchOS Companion** — Next-stop display, one-tap delivery logging, auto-advance
- **📋 Master Route List** — Searchable database with community-mailbox compartments, flags, and notes
- **🗺️ Flexible Views** — Parcels-only or full route, last-stop bulk checkoff

## Status

🚧 Early development — landing page live at [dfakkeldy.github.io/Routey](https://dfakkeldy.github.io/Routey)

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
