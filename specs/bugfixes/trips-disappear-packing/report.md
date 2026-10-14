# Bugfix Report: Trips disappear during packing (T-2459)

**Date:** 2026-10-15
**Status:** Synthetic deletion defect fixed; baseline UI verification in progress

## Description of the Issue

A user reported that trips disappeared while checking packing items on a trip.
The report does not establish whether the trip left the current screen, moved
into Previous, or was deleted from persistence. No live trips or cloud records
are used by this investigation, and no historical deletion or recovery is claimed.

## Investigation Summary

- Started from current `origin/main` (`0a37052`), including T-1670's separate
  zone creation and reinstall restoration fixes. Original checkout and its
  untracked `.kiro` directory were preserved.
- Trip List filters Active/Previous exclusively by `endDate`; packing completion
  does not participate in the predicate.
- Packing toggles only modify `TripPackingItem.state` and commit through
  `LocalWriteHook`. Rules evaluation flags unmatched items rather than deleting trips.
- Checked the navigation stack, packing sheet dismissal, lifecycle rules pass,
  local write hook, sync translations, and inbound record deletion path.
- Existing legacy packing UI fixtures seed globals while Trips reads tripsLocal;
  a new synthetic fixture uses `TripPersistence.create` across separate containers.
- `TripSyncEngine.apply(deletedRecordIDs:)` discards each deletion's zone identity,
  then deletes models with matching UUIDs. A focused regression supplies a foreign
  zone tombstone after a packing save; the pre-fix test failed both trip and packing-item retention assertions.

## Discovered Root Cause

Verified synthetic defect: the inbound deletion handler reduces CloudKit record IDs
to bare UUIDs, losing zone name and owner. A tombstone from `legacy-zone` with the
same record name as a current trip removes the current local trip and cascades its
packing items. The regression failed both retention assertions before the fix.

Why: incoming deletions trigger local fetches by UUID; the owning namespace was
discarded before those fetches; the local identity schema has only UUID fields;
existing tests did not exercise foreign-zone deletion. This is a sync identity
validation defect, not a packing-completion filter.

The pre-fix ordinary packing saves plus synthetic record echoes preserved the trip,
its navigation identity/hash, relationships, and final packing state across a
SQLite reopen. The focused UI test passed in 116.786 seconds, including eight check/uncheck
actions, background/reactivation, sheet dismissal, and final trip-list retention.
The activation step had a long XCTest delay; a stack sample showed the synthetic
app's main thread idle. The surrounding make command was interrupted during
teardown, so this is a passed test with an interrupted command, not a clean run exit.

The reported last-trip event has no device log or store evidence available.
Matching historical foreign-zone tombstones have not been observed. This defect
is verified, but attribution of the historical report remains unproven.

## Resolution for the Issue

- Match full CloudKit identity before staging any delete. Owning trip zones are
  derived from the canonical `TripZoneStateRecordTranslator.zoneID(for:)`, retaining
  its empty-owner normalization. Trips without a zone row use cached owner identity
  or the private-database default. An orphan child requires its exact cached identity.
- Resolve all candidates before mutation, then remove items, tasks, snapshots,
  trips and corresponding zone rows in reverse-cascade order. Snapshot cleanup
  includes the canonical `snapshot.trip` backlink as well as the convenience array.
- Keep inbound saves local; reuse of `TripDeletion.delete` would wrongly invoke
  the outgoing write hook and echo server deletions.
- No schema migration, recovery operation, cloud mutation, or phone installation.
- Added `TEST_ARGS` to Makefile test recipes for focused selectors; the default
  full-suite command is unchanged.

This is a narrow correction of sync identity matching. Changing trip filters or
navigation without a reproduced failure was rejected as speculative. Restoring
historical trips requires separate evidence about the local store and server data.

## Regression Tests

`PackingSheetUITests.testRepeatedPackingTogglesPreserveTripAcrossForeground`:
repeated check/uncheck, background/reactivation, sheet dismissal, and trip-list return.

`TripSyncEngineTests.packingSavesPreserveTrips`: repeated commits and synthetic
full-record echoes, then reopen a temporary SQLite store; CloudKit is disabled.

`TripSyncEngineTests.foreignZoneDeletionPreservesPackingTrip`: 12 combinations
cover legacy zone, another trip zone and another owner against root/item/task/snapshot.
All graph rows and the packing state must remain.

`matchingZoneDeletionRemovesTripGraph`: genuine private/shared/default-owner
root deletions remove only the targeted graph. `matchingZoneChildDeletionPreservesTrip`
checks child-only deletion. `orphanDeletionRequiresCachedIdentity` checks cached
full-identity matching for children whose parent has not arrived.

The final disk regression performs 24 transitions through unpacked, packed and
repacked, validates navigation hash/identity, and reopens the synthetic SQLite store.

## Verification

All tests use synthetic data, `.none` for CloudKit persistence, an engine that is
never started, and retained ModelContainers. The UI uses an in-memory two-store
fixture and a dedicated empty iOS 27.0 simulator.

- Red: focused `TripSyncEngineTests` ran 17 tests; one intended foreign-zone test
  failed both trip and packing-item retention assertions; 16 passed. The make
  command was terminated after native results during stalled teardown.
- Initial green: expanded `TripSyncEngineTests` ran 20 declarations, including 12
  foreign-zone and two genuine-deletion parameter cases; all passed. This precedes
  the review refinements (default-owner case and canonical snapshot cleanup).
- Focused UI: lifecycle regression passed; command interrupted during teardown.
- Strict lint: `swiftlint lint --strict --no-cache` passed, zero violations across
  228 files. `make lint` initially encountered the sandboxed user-cache write;
  the equivalent no-cache invocation avoids it.
- Final focused run: `make test SIMULATOR='Scramble Packing Regression 20261015,OS=27.0'
  XCBEAUTIFY= TEST_ARGS='-parallel-testing-enabled NO
  -only-testing:ScrambleTests/TripSyncEngineTests
  -only-testing:ScrambleUITests/PackingSheetUITests/testRepeatedPackingTogglesPreserveTripAcrossForeground'`
  completed with exit 0 and `TEST SUCCEEDED`. Native xcresult summary: 21 passed
  declarations (20 sync + one UI), zero failures/skips; dynamic parameters account
  for 34 executions, including 12 foreign-zone and three genuine-deletion cases.
  UI regression: 32.854 seconds. Result: `Test-Scramble-2026.10.15_10-15-25-+1100.xcresult`.
- Required full suite: completed once on unchanged Swift source, result bundle
  `/tmp/scramble-full-final.xcresult`; `make` exited 2 after xcodebuild exited 65.
  Native summary: **806 passed, 38 failed, 12 skipped, 856 total declarations**.
  All unit suites passed (`785 tests in 93 suites` in Swift Testing's log).
  UI results: 27 passed, 38 failed, nine skipped. The new packing regression passed.
  A single targeted run of exactly those 38 UI methods is now running against
  unchanged baseline app source at `0a37052`, with only Makefile test-selector
  forwarding added. Baseline results pending. No full-suite rerun is planned.

Default simulator lookup was ambiguous; an explicit dedicated simulator and
`-parallel-testing-enabled NO` avoid unrelated cloned-device startup delays.

## Review

Independent code quality, reuse, efficiency and evidence reviews completed.
Reuse review identified empty-owner normalization; the canonical resolver and a
regression were added. Quality review prompted canonical snapshot backlink cleanup.
Evidence review corrected a test-result attribution. No personal trips or secrets
were included in the reviewed diff.

## Historical Data and Recovery Limits

No historical trip store, device logs or live cloud data was inspected. The fix
prevents the reproduced wrong-zone local deletion; it does not establish that any
particular past trip was deleted, that a matching foreign tombstone occurred, or
that anything was recovered. The earlier T-1670 reinstall fix is already in the base.
