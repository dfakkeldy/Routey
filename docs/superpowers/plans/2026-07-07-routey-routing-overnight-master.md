# Routey Routing Overnight Workflow

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute the on-the-fly routing work as five linked plans, updating each next plan with lessons from the previous implementation before continuing.

**Architecture:** Build from offline, package-testable core logic outward. Routey owns parcel delivery ordering and offline fallback; MapKit is a provider for coordinate lookup, leg directions, ETA, and map display.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, MapKit, Core Location, SQLiteData/GRDB.

## Global Constraints

- Routey is public and carrier-agnostic. Do not commit employer names, real route data, real street/site/place names, civic numbers, or carrier-specific jargon.
- App target is iOS 18.0. `RouteyKit` package floors at iOS 17 / macOS 14.
- Swift 6 or later. Prefer async/await and strict concurrency-safe value types.
- Persistence is SQLiteData/GRDB plus private CloudKit, not SwiftData or Core Data.
- Local SQLite remains the source of truth. UI must not block on network, geocoding, MapKit directions, or sync.
- Do not introduce third-party frameworks.
- New package logic must be testable with `cd RouteyKit && swift test`.
- Feature work branches from `nightly`, commits autonomously, pushes, and opens PRs against `nightly`.

---

## Execution Protocol

- [ ] Start on `origin/nightly` in an isolated worktree and create a `codex/` branch.
- [ ] Run baseline: `cd RouteyKit && swift test`.
- [ ] Implement Plan 1.
- [ ] Before Plan 2, edit `docs/superpowers/plans/2026-07-07-routey-routing-02-coordinate-cache-geocoder.md` in its "Learning Log From Previous Plan" section with concrete lessons from Plan 1.
- [ ] Implement Plan 2.
- [ ] Before Plan 3, edit Plan 3's "Learning Log From Previous Plan" section with concrete lessons from Plan 2.
- [ ] Implement Plan 3.
- [ ] Before Plan 4, edit Plan 4's "Learning Log From Previous Plan" section with concrete lessons from Plan 3.
- [ ] Implement Plan 4.
- [ ] Before Plan 5, edit Plan 5's "Learning Log From Previous Plan" section with concrete lessons from Plan 4.
- [ ] Implement Plan 5.
- [ ] After each plan, run the plan-specific tests, commit with a Conventional Commit, and run `git status --short --branch`.
- [ ] After Plan 5, run `cd RouteyKit && swift test`, app build when feasible through the Xcode build gate, `git diff --check`, push, open a PR to `nightly`, and check hosted CI.

## Plan Files

1. [Offline Optimizer](2026-07-07-routey-routing-01-offline-optimizer.md)
2. [Coordinate Cache and Geocoder](2026-07-07-routey-routing-02-coordinate-cache-geocoder.md)
3. [Apply Optimized Order to Today's Run](2026-07-07-routey-routing-03-apply-optimized-run-order.md)
4. [Map Preview and Directions Handoff](2026-07-07-routey-routing-04-map-preview-directions.md)
5. [Snap Temporary Route Builder](2026-07-07-routey-routing-05-snap-temporary-route.md)

## Definition of Done

- Routey can optimize a list of coordinate-backed delivery stops offline.
- Routey can cache coordinates on existing synced `Stop` / `Address` fields without a schema change.
- Routey can apply an optimized suggestion to Today's Run while leaving manual reorder intact.
- Routey can show a map preview and hand off individual legs to Apple Maps or render MapKit directions when available.
- Routey can create a temporary parcel-only route from snapped labels when no master route match exists.
- The implementation never requires network access to keep the parcel list usable.
