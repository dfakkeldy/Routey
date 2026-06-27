# Routey Roadmap

Routey V1.0 is tracked in the execution plan at
[`docs/superpowers/plans/2026-06-25-routey-roadmap-execution.md`](docs/superpowers/plans/2026-06-25-routey-roadmap-execution.md).

Current checkpoint: M1 Mac+iPhone sync proof setup is implemented but the live CloudKit
round-trip is blocked on Apple provisioning. Routey keeps `Tag` on UUID primary keys,
with canonical tag-name reuse enforced in app/domain logic. Next gate: sign
`RouteyMacProof` with an iCloud-enabled Mac profile for `iCloud.com.routey.app`, then run
the Mac+iPhone proof on the same iCloud account.
