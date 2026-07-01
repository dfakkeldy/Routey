# Routey Roadmap

Routey V1.0 is tracked in the execution plan at
[`docs/superpowers/plans/2026-06-25-routey-roadmap-execution.md`](docs/superpowers/plans/2026-06-25-routey-roadmap-execution.md).

Current checkpoint: the `nightly` train now has the headless V1.0 package
foundation plus the initial iPhone app shell for route import/editing, predictive
search, Snap-to-Add camera OCR, and Today's Run. A July 1, 2026 manual nightly
release run built and distributed `0.1 (4)` to internal TestFlight testers.

That is still not App Store readiness. The next release gates are:

1. Finish the visible V1.0 iPhone loop: proof-of-delivery/outcome UI, run
   filters, PDF/print/share, and encrypted `.routey` file UI.
2. Deploy and verify the CloudKit schema in Production with production-signed
   devices.
3. Run an airplane-mode device walkthrough of sort -> snap -> deliver ->
   history -> export using invented placeholder data only.
4. Complete App Store metadata, screenshots, privacy answers, accessibility
   nutrition labels, age rating, review notes, and pricing/free-vs-paid
   decisions.
5. Keep watchOS and CarPlay deferred until the iPhone cut is accepted.

See [`docs/release/app-store-next-steps.md`](docs/release/app-store-next-steps.md)
for the current ten-step submission ladder.
