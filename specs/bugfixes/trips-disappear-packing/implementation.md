# T-2459 implementation explanation

## Beginner

Each synced record has an address: its name, the zone it belongs to, and the
zone's owner. The old deletion handler kept only the name. A deletion at a
different address could therefore remove a local trip with the same UUID.
The fix checks the complete address before removing anything.

Packing completion does not control the trip list. The synthetic packing tests
retain the trip through check/uncheck actions, background/reactivation and a
return to the trip list. These results do not identify the cause of a historical
incident without its logs or stored data.

## Intermediate

`TripSyncEngine+Deletions.swift` retains incoming `CKRecord.ID` values and fetches
candidate models by UUID. A matcher derives each candidate's owning trip zone
using the existing zone-state translator, including empty-owner normalization.
Without a state row, it uses the trip's cached owner or the private default.
Orphan children require a matching cached record ID rather than guessed ownership.

All matches are resolved before mutation, since deleting a parent can nullify
relationships needed by later checks. Genuine trip deletions collect dependent
records, including snapshots reachable only through their canonical back-reference,
and delete in the existing reverse-cascade order. Inbound changes save locally
without the outgoing `LocalWriteHook`.

The alternative of changing Active/Previous filtering or replacing model-based
navigation had no reproduced failure to justify it. Calling the outgoing trip
removal helper would introduce sync feedback. Neither was adopted.

## Expert

Candidate queries remain UUID-filtered; the zone-state query is bounded by their
owning trip IDs. A root deletion additionally fetches snapshots with a matching
`trip` backlink because the convenience collection is not the declared lifetime
authority. `Set` unions avoid duplicate model deletion when a batch contains both
a root and its child. Ownership is resolved before those relationships mutate.

A missing-parent child can still receive a valid deletion if its cached system
fields establish the full identity. Without either a parent or cached evidence,
the conservative result is preservation. The change has no schema impact and
makes no attempt to repair missing historical data or broaden sync restore policy.

## Completeness assessment

The reproduced foreign-zone local deletion is fixed and has regression coverage.
The synthetic packing path, sync echoes, navigation identity and disk reopening
are covered. Final check outcomes are recorded in `report.md`. The original
last-trip incident and historical data recovery remain unproven. No live trips,
cloud mutations, phone installation or merge are part of this implementation.
