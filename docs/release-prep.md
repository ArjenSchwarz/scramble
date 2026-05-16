# Release prep checklist

Pre-release work that has to land before any TestFlight or App Store
submission. Items here are not enforceable from CI — keep them honest
by walking the list every time.

## CloudKit

- [ ] **Promote the CloudKit schema from Development to Production.**
  Open the CloudKit Dashboard for container `iCloud.me.nore.ig.scramble`
  and promote every new record type and zone topology introduced by
  `SchemaV3` (Phase 5 — Req
  [13.1](../specs/phase-5-cloudkit-sharing/requirements.md#13.1) /
  [13.2](../specs/phase-5-cloudkit-sharing/requirements.md#13.2)).
  Skipping this step results in real users hitting "schema not
  deployed" errors on first launch of the Phase 5 build.
  - Record types to verify in Production after promotion:
    `Trip`, `TripTask`, `TripPackingItem`, `TripPersonSnapshot`,
    `TripZoneState`, plus `cloudkit.share` references for trip zones.
  - Confirm custom per-trip zones (`trip-<uuid>`) are creatable in
    Production by exercising a fresh-account end-to-end test (see
    `specs/phase-5-cloudkit-sharing/manual-test-plan.md`).
