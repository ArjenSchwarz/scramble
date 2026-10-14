# Bugfix Report: Trips disappear during packing (T-2459)

**Date:** 2026-10-15
**Status:** Investigation in progress

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

Twenty ordinary packing saves plus synthetic record echoes preserved the trip,
its navigation identity/hash, relationships, and final packing state across a
SQLite reopen. Eight UI check/uncheck actions also retained the sheet. The first
UI lifecycle attempt had a long XCTest activation delay; it was interrupted before
its final list assertion completed, and is not a passed test.

The reported last-trip event has no device log or store evidence available.
Matching historical foreign-zone tombstones have not been observed. This defect
is verified, but attribution of the historical report remains unproven.

## Resolution for the Issue

Pending.

## Regression Tests

`PackingSheetUITests.testRepeatedPackingTogglesPreserveTripAcrossForeground`:
repeated check/uncheck, background/reactivation, sheet dismissal, and trip-list return.

`TripSyncEngineTests.packingSavesPreserveTrips`: repeated commits and synthetic
full-record echoes, then reopen a temporary SQLite store; CloudKit is disabled.

`TripSyncEngineTests.foreignZoneDeletionPreservesPackingTrip`: foreign-zone
inbound deletion after packing must preserve the local trip and packing item.

## Verification

Runtime checks pending. Test commands use the Makefile with `TEST_ARGS` selectors
and a dedicated empty simulator; no device installation is part of this task.
