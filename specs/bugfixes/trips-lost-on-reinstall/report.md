# Bugfix Report: Trips lost on reinstall (T-1670)

**Date:** 2026-07-05
**Status:** Fixed (pending on-device CloudKit verification)

## Description of the Issue

Installing a new build over an existing install (or deleting + reinstalling) leaves
the trip list empty. The master lists (tasks + per-person packing items) survive,
but every trip is gone. Reproducible on every debug reinstall; release builds are
expected to behave the same.

**Reproduction steps:**
1. Create one or more trips (do not share them).
2. Delete the app (or install a fresh build that resets the app container).
3. Launch. Observe: master lists are restored from iCloud, but no trips appear.

**Impact:** High. Trips are the app's primary object. Any user who reinstalls, or
moves to a new device, silently loses all unshared trips — the data was never in
iCloud to begin with, so it is unrecoverable.

## Investigation Summary

- **Two persistence paths.** Master lists live in the `globals` SwiftData container
  (`cloudKitDatabase: .private`) — SwiftData's native `NSPersistentCloudKitContainer`
  mirror, which auto-restores on reinstall. Trips live in the `tripsLocal` container
  (`cloudKitDatabase: .none`, local-only); their CloudKit sync is hand-rolled via
  `TripSyncEngine` / `CKSyncEngine` into per-trip custom zones (`trip-{uuid}`). A
  reinstall wipes the local trips store, so trips only return if the bespoke pipeline
  both uploaded them and re-fetches them on first launch.
- **Zone-creation sites.** The only `.saveZone` call sites are `ZoneMigrationCoordinator`
  (Stage B migration) and `CloudKitSharingService.createShare` (sharing). There is no
  zone creation for an ordinary, unshared, newly-created trip.
- **CKSyncEngine does not auto-create zones** (confirmed against Apple's docs and
  `apple/sample-cloudkit-sync-engine`): saving a record into a missing zone fails with
  `.zoneNotFound`, which must be handled by creating the zone and retrying.

## Discovered Root Cause

**Primary (upload):** a newly-created unshared trip's CloudKit zone is never created,
so its records never reach iCloud.

- `TripPersistence.create` inserts a local `TripZoneState` but queues no `.saveZone`.
- `LocalWriteHook` only queues `.saveRecord` changes — never a zone save.
- The engine sends the records into a zone that does not exist → CloudKit returns
  `.zoneNotFound` per record. `TripSyncEngine.handleSentChanges` had no recovery; it
  just emitted `.recordsFailed`.
- Because `create` already inserted a `TripZoneState`, `ZoneMigrationCoordinator.enqueueAll`
  permanently skips the trip (`!migratedTripIDs.contains(tripID)` is false), so Stage B
  never creates the zone either.
- Net: the trip's records never upload. On reinstall there is nothing to restore.
  Only shared trips (createShare does `saveZone`) or pre-Phase-5.1 migrated trips
  survive.

**Secondary (download):** even for trips that *are* in iCloud, restore was not
deterministic. `TripSyncEngine.makeEngine` called `engine.state.add(pendingDatabaseChanges: [])`
on fresh/corrupt state — an empty array, i.e. a no-op — despite the comment claiming it
forced a reconciliation. A reinstalled device relied solely on `automaticallySync` to
discover its zones, with no explicit launch fetch.

**Defect type:** Missing zone-creation step + a no-op that never delivered its intended
reconciliation.

## Fix

`Scramble/Sharing/TripSyncEngine.swift`
- **Zone-not-found recovery** in `handleSentChanges`: `.zoneNotFound` record failures now
  create the missing zone (`.saveZone`) and re-queue the records (`.saveRecord`), marking
  them self-originated. This is Apple's documented pattern. Only genuinely-unrecoverable
  failures still emit `.recordsFailed`. Recovery relies on CKSyncEngine's own send
  scheduling/backoff rather than a manual loop guard (a valid private-DB zone save
  effectively always succeeds).
- Extracted the pure `classifyFailedSaves(_:)` helper (returns `FailedSaveClassification`)
  so the recovery decision is unit-tested without a live engine.
- `needsInitialFetch()` + `fetchChangesOnLaunch()`: replaced the no-op `add(pendingDatabaseChanges: [])`
  with an explicit cold-launch fetch of both databases, keyed on the private scope having
  no persisted state (fresh install / reinstall / corrupt-and-cleared blob).

`Scramble/ScrambleApp.swift`
- `prepareLaunch` captures `needsInitialFetch()` before `syncEngine.start()` and, when
  true, kicks `fetchChangesOnLaunch()` in a detached task so the migration gate still
  releases promptly and restored rows land reactively.

## Tests

`ScrambleTests/Sharing/TripSyncEngineTests.swift` (Swift Testing):
- `classifyFailedSavesPartitions` — `.zoneNotFound` failures route to zone-create + retry;
  other errors route to unrecoverable.
- `classifyFailedSavesNoRecovery` — no `.zoneNotFound` ⇒ nothing recovered.
- `needsInitialFetchFreshStore` / `needsInitialFetchCorruptStore` — fresh and corrupt
  private-scope state both request the launch fetch.

`make test-quick` passes; `make lint` clean.

## Verification still needed (cannot run against real CloudKit here)

The unit tests cover the pure decision logic. The end-to-end path — new trip → first send
`zoneNotFound` → zone created → records uploaded → reinstall → `fetchChangesOnLaunch`
restores the trip — must be confirmed on a real device with an iCloud account (the
simulator and tests use `cloudKitDatabase: .none`). Suggested manual check: create a trip,
confirm the `trip-{uuid}` zone and records appear in the CloudKit dashboard (private DB),
delete + reinstall, confirm the trip returns.

## Follow-up worth considering (not in this fix)

The reactive recovery costs one failed send round-trip per new trip. A proactive
`.saveZone` at trip creation would avoid it, but requires threading the engine into the
create path; deferred to keep this fix contained and low-risk.
