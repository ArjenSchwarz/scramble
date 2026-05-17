# Prerequisites for Phase 5 — CloudKit Sharing

These tasks must be completed by the user before or during implementation.

## Before Starting

- [ ] Verify the Xcode project has the iCloud capability enabled with the CloudKit service ticked and the container `iCloud.me.nore.ig.scramble` selected (already required since Phase 1; confirm it is still configured)
- [ ] Verify the Xcode project has the Push Notifications capability enabled (required for silent CKSyncEngine push delivery)
- [ ] Verify the Xcode project has the Background Modes capability enabled with the "Remote notifications" mode ticked
- [ ] Confirm the Apple Developer Provisioning Profile for the app includes the `aps-environment` entitlement (development for debug builds, production for TestFlight/App Store)

## During Implementation

- [ ] Before running Task 1 (CKSyncEngine validation harness), have two iCloud-signed-in test devices (or a device + a Simulator with a separate iCloud account) available so the share-acceptance half of the validation can be exercised end-to-end

## Before Testing

- [ ] When manually testing share invite/accept flows end-to-end, ensure both devices are signed in to distinct iCloud accounts and have network connectivity

## Before Release

- [ ] Promote the SchemaV3 record types (`TripPersonSnapshot`, `TripZoneState`, `MigrationJournalEntry`, plus any V3 field additions to existing types) and the per-trip zone topology from the Development environment to the Production environment via the CloudKit Dashboard. This blocks Task 36's checklist item from being satisfied at release time.
