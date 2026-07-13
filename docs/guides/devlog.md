# Building Routey - The Devlog

Routey's public build record is generated from the real commit history, with room for hand-written notes when a week needs more context.

This repo is public and carrier-agnostic. Keep hand-written notes free of real route data, real street or site names, employer names, civic numbers, and carrier-specific jargon.

---

<!-- AUTO-DEVLOG:START -->
## Automated update - Jun 22-28, 2026

*Generated from 11 commits merged during the week.*

### Shipped
- Add CloudKit proof setup ([9f1ea54](https://github.com/dfakkeldy/Routey/commit/9f1ea54))
- Add predictive search screen ([9ead5c7](https://github.com/dfakkeldy/Routey/commit/9ead5c7))
- Add local address search index ([e09c78c](https://github.com/dfakkeldy/Routey/commit/e09c78c))
- Add manual route editing ([1d93d8e](https://github.com/dfakkeldy/Routey/commit/1d93d8e))
- Add route import workflow ([ac53679](https://github.com/dfakkeldy/Routey/commit/ac53679))
- Add iOS app shell wired to SQLiteData ([15b516a](https://github.com/dfakkeldy/Routey/commit/15b516a))

### Build, docs, and housekeeping
- Weekly automated update ([d1527df](https://github.com/dfakkeldy/Routey/commit/d1527df))
- Route nightly builds to internal testers ([10b538a](https://github.com/dfakkeldy/Routey/commit/10b538a))
- Add reviewed AI draft PR bodies ([a2f7ef0](https://github.com/dfakkeldy/Routey/commit/a2f7ef0))
- Add release ladder CI ([6cd7cac](https://github.com/dfakkeldy/Routey/commit/6cd7cac))
- Add weekly automation ([4aa156e](https://github.com/dfakkeldy/Routey/commit/4aa156e))

<!-- AUTO-DEVLOG:END -->

## Notes

The generated weekly digest above is safe to refresh automatically. Hand-written launch notes can live below this section when there is a story worth telling in more detail.

### Jun 28, 2026 - M1 sync proof decision

PR #13 merged to `nightly` at `54f9ceb` after GitHub's Build gate + tests
passed in 14m13s. The documented manual proof now covers a physical iPhone
clean reinstall matching the Mac proof database's invented placeholder proof
rows, with no unsynced rows observed.

Decision: proceed with SQLiteData + private CloudKit unless the remaining
manual graph matrix reveals a hard failure. The synced schema is now
append-only: preserve existing synced tables and columns, keep UUID primary
keys, avoid non-primary-key uniqueness on synced tables, and add only new
optional/defaulted synced columns or new synced tables.

Remaining manual follow-up: signed Mac app install evidence, nested iPhone edit
pullback, `sortIndex` move propagation, delete/cascade propagation, and same-row
or concurrent reorder behavior. Today's Run remains single-device-per-day until
the reorder behavior is written down.

### Jun 28, 2026 - Headless V1.0 train

PRs #14 through #19 merged the remaining package-first V1.0 slices into
`nightly`: search freshness, OCR matching, Today's Run domain, history archive
and search, report content, and encrypted route handoff. The app still needs
explicitly approved visible Today's Run screens plus later PDF/share and
encrypted file UI, but the tested offline domain layer now covers the major
non-camera workflows without depending on the network.

PR #20 reconciled the roadmap's release-readiness checklist with that merged
headless train. The docs now call out the remaining visible Today, camera,
PDF/share, `.routey` file UI, and Production CloudKit gates instead of treating
them as complete.
