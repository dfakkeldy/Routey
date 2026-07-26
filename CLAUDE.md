# Claude Code Guidelines for Routey

@AGENTS.md

## Product context

Dan is the domain authority for route operations. Ask focused questions when a
workflow detail affects the product; do not infer it from generic carrier
practice. A feature should save time in the truck.

Routey is an offline-first iOS app with an implemented `RouteyKit` package. Its
flagship capture path photographs a parcel label, extracts address signals,
ranks candidates deterministically, and adds a stop in delivery order.

## Non-negotiable privacy

This is a public repository. Never put live route data, employer details, real
addresses or place names, photos, device identifiers, or carrier-specific
jargon into prompts, code, tests, fixtures, screenshots, docs, logs, commits, or
PR text. Use invented placeholders; keep the real route local.

## Architecture notes

- Local SQLite is authoritative; private CloudKit sync is best effort.
- Preserve the Delivery Point / Address distinction and the append-only synced
  schema rules in `AGENTS.md`.
- Prefer concrete constructor injection and in-memory SQLite tests. Do not add
  speculative protocol/mock layers.
- Read the relevant current design or plan for architecture and data-model work.
  Do not treat an old branch-status description as current repository state.
- Update documentation only when implementation makes the existing text
  inaccurate.

## Build and release notes

Use `swift build` and `swift test` from `RouteyKit` for package changes. Physical
device sync or locked-phone checks remain separate acceptance gates. The
promotion ladder and publication rules are canonical in `AGENTS.md`.
