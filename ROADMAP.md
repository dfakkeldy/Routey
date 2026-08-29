# Routey Roadmap

Routey V1.0 is tracked in the execution plan at
[`docs/superpowers/plans/2026-06-25-routey-roadmap-execution.md`](docs/superpowers/plans/2026-06-25-routey-roadmap-execution.md).

Current V1.0 cut line: ship the iPhone workflow Dan can use in the truck:
Run/Routes/Search tabs, paste/CSV import, route/address/tag editing,
predictive search, Snap-to-Add, Today's Run check-off, "done through here",
and drag reorder.

The tested package code for history, report content, encrypted handoff,
delivery-outcome logging, and follow-up tasks stays in `RouteyKit`. The visible
UI for reports/PDF/print/share, encrypted `.routey` handoff, delivery outcomes,
Today's Run filters, and follow-up tasks moves to V1.1.

Before V1.0 is treated as install-ready, the release gate is an airplane-mode
physical-iPhone smoke test plus current CI/TestFlight evidence from the
`nightly` release train. Production CloudKit schema deployment remains a release
readiness gate, not something the app UI should block on.
