# Prerequisites for Packing Item Categories

These steps require human action outside of code.

## Before Release

- [ ] **Promote the CloudKit schema to Production** for the `iCloud.me.nore.ig.scramble` container, after the new fields exist in the Development environment. Promote the auto-mirrored `MasterPackingItem.category` (private database, created by the SwiftData CloudKit mirror) and the `TripPackingItem.category` field on the shared-zone record type. Local development and the test suite do not need this (Development auto-creates the schema), but a production release that ships category sync does. Tracked in the checklist updated by task 21 (`docs/release-prep.md`).
