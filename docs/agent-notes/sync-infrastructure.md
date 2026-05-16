# Sync infrastructure (Phase 5 — sync engine layer)

Phase 5 tasks 6–17. The injectable sharing seam, dual-container split,
record translators, dirty-marking chokepoint, fake sharing service, sync
engine, and production sharing service. Stage B coordinator and UI
surfaces remain unimplemented.

## Files

- `Scramble/Scramble/Sharing/SharingService.swift` — injectable seam.
  `SharingService` protocol + `AcceptedShareResult`, `ShareParticipant`,
  `OwnerIdentity`. Owner-identity check is synchronous (Req 10.4) and
  reads only `TripZoneState`.
- `Scramble/Scramble/Sharing/CloudKitSharingService.swift` — production
  impl. Wraps `CKContainer` + `TripSyncEngine`. `createShare` builds
  `CKShare(recordZoneID:)`, hands to `privateEngine.state.add(pendingRecordZoneChanges:)`,
  caches the share ID on the trip's `TripZoneState`. `acceptShare`
  calls `CKContainer.accept`, queues a saveZone on the shared engine,
  triggers `fetchChanges()`. `leaveShare` deletes the shared zone then
  runs local cleanup in the reverse-cascade order:
  `pendingUploadFlags → packing items → tasks → snapshots → trip → zone state`.
  `participants` resolves CKShare participants with the
  `displayName → email → "Invited participant"` fallback chain.
- `Scramble/Scramble/Sharing/UICloudSharingControllerRepresentable.swift` —
  SwiftUI wrapper for `UICloudSharingController`. Constructed with the
  `CKShare`, the `CKContainer`, and callbacks for dismiss / save failure.
  Headless service — view code mounts this in a sheet rather than calling
  `SharingService.presentShareUI`.
- `Scramble/Scramble/Sharing/TripSyncEngine.swift` — façade around two
  `CKSyncEngine` instances (private + shared databases). State is
  serialised through `TripSyncStateStore` (file-backed in production,
  in-memory for tests). Corrupt state blobs are logged, cleared, and
  discarded — the engine reconstructs without prior state and the
  delegate triggers a full reconciliation. The pure-Swift surface
  (`buildBatch(scope:pendingRecordIDs:)`,
  `apply(fetchedRecords:)`, `apply(deletedRecordIDs:)`,
  `markSelfOriginated(_:)`, `wasSelfOriginated(_:)`) is testable
  without a real CKSyncEngine; tests target it directly. The class
  also conforms to `PendingChangeNotifier` so `LocalWriteHook` can
  call into it.
- `Scramble/Scramble/Sharing/TripSyncStateStore.swift` —
  protocol + `FileTripSyncStateStore` (writes to
  `~/Library/Application Support/Scramble/CKSync/{private,shared}.state`,
  flags backup-excluded) and `InMemoryTripSyncStateStore` (tests).
  In-memory store has `returnCorruptDataForScopes` knob for exercising
  the corruption-recovery path.
- `Scramble/Scramble/Sharing/LocalWriteHook.swift` — single chokepoint
  for `tripsLocal` saves (design § "Single dirty-marking chokepoint").
  Inspects `context.insertedModelsArray` / `changedModelsArray` /
  `deletedModelsArray`, ORs dirty/deleted record names into the
  matching `TripZoneState.pendingUploadFlags`, calls `context.save`
  exactly once, then notifies the engine via `PendingChangeNotifier`.
  Skips models with no resolvable `tripID` (e.g., orphan snapshots
  mid-deletion).
- `Scramble/Scramble/Sharing/PendingUploadFlags.swift` — Codable
  `{dirtyRecordNames, deletedRecordNames}` struct stored as JSON in
  `TripZoneState.pendingUploadFlags`. Set form (not bitset) because
  records per trip are low-tens and entity counts may grow.
- `Scramble/Scramble/Sharing/Translators/RecordRepresentable.swift` —
  protocol contract + `TranslatorError` + `kRecordBlobSizeCap` (256 KB
  per blob field).
- `Scramble/Scramble/Sharing/Translators/{Trip,TripTask,TripPackingItem,TripPersonSnapshot}RecordTranslator.swift` —
  one per entity. Relationships encoded as UUID-valued record fields
  (e.g., `personSnapshotID: String`), **never** `CKRecord.Reference`.
  Each translator preserves CKRecord system fields via the
  `ckRecordSystemFields: Data?` blob on the @Model (decoded with
  `decodeSystemFields(from:)`, re-encoded with `encodeSystemFields(of:)`
  exposed at file scope on `TripRecordTranslator.swift`).
- `Scramble/Scramble/Sharing/Translators/TripZoneStateRecordTranslator.swift` —
  `CKShare ↔ TripZoneState` updater. Parses `trip-{uuid}` zone names,
  inserts a placeholder `TripZoneState` on the participant side when a
  share arrives ahead of any trip record. `zoneID(for:)` exposes the
  canonical zone-naming convention.
- `Scramble/Scramble/Persistence/ModelStore.swift` — dual-container API.
  `containers.globals` keeps SwiftData's CloudKit mirror against the
  private database. `containers.tripsLocal` is local-only
  (`cloudKitDatabase: .none`); its CloudKit sync is driven by
  `TripSyncEngine`. Both schemas remain full `SchemaV3` (the deprecated
  V2 cross-references `Trip.participants → Person` keep them coupled
  until V4 cleanup); the split is enforced by convention — globals
  context holds globals records, tripsLocal context holds trip-zone
  records. `ModelStore.shared` aliases `containers.globals` for backward
  compatibility with pre-Phase-5 call sites.
- `Scramble/Scramble/Persistence/TripsLocalContainerKey.swift` —
  SwiftUI environment carrier (`\.tripsLocalContainer`) for the second
  container. `globals` flows through SwiftUI's `.modelContainer(_:)`
  modifier; tripsLocal flows through `.environment(...)`.

## Tests (ScrambleTests)

- `Sharing/Translators/*Tests.swift` — one suite per translator. Cover
  encoding (UUID-relationship rule, blob size cap, system-fields
  round-trip), decoding (insert + merge, missing-field defaults), and
  recordType mismatch rejection.
- `Sharing/LocalWriteHookTests.swift` — insert / change / delete flip
  the right bits, single save per commit, notifier receives correct
  record IDs and zone, empty commit is a no-op.
- `Sharing/FakeSharingServiceTests.swift` — bus delivery, delivery
  delay, share creation lifecycle, error injection, owner-only
  enforcement.
- `Sharing/CloudKitSharingServiceTests.swift` — share lifecycle
  contract validated via `FakeSharingService` (since real CloudKit
  flows are exercised by `CKSyncEngineValidationHarness` and the
  manual test plan).
- `Sharing/TripSyncEngineTests.swift` — translator dispatch, fetched
  record application, self-origination consume-once, state corruption
  recovery, `PendingChangeNotifier` self-origination wiring.

## Test seam — FakeSharingService

Lives in the test target only. Two endpoints (one `.owner`, one
`.participant`) share a `FakeSharingBus`. Imperative hooks:

- `simulateOwnerWrite(_:tripID:)` — owner-side; publishes `.zoneChanged`
  to the participant endpoint with the supplied record.
- `simulateAcceptance(forTrip:participantOwnerName:)` — owner-driven;
  publishes `.shareAccepted` on the participant side.
- `triggerZoneChange(zoneID:target:)` — empty `.zoneChanged` for
  refetch tests.
- `simulateError(_:)` — injects an error for the next throwing
  `SharingService` call, then clears.
- `deliveryDelay` — bus-level async delay (default zero for
  deterministic tests).

## Conventions

- **Direct `context.save()` on `tripsLocal` is forbidden** outside
  `LocalWriteHook`. Future commits adding a SwiftLint rule for this
  would be welcome; for now it's a code-review checklist item.
- **Relationships → UUID fields on CKRecords**, never CKRecord.Reference
  (Decision 13 / design § "@Model ↔ CKRecord translation"). Avoids
  cross-record dependency ordering inside `CKSyncEngine` batches.
- **System fields preserved on every write**. Translator's
  `existing: CKRecord?` argument is constructed from the entity's
  `ckRecordSystemFields` blob; `from(_:into:)` re-encodes the fetched
  record's system fields back into the entity. Missing this causes
  every save to look like a new record to CloudKit (loses serverChangeTag).
- **Blob size cap 256 KB** per Codable blob field (e.g.,
  `Trip.attributesData`). Exceeded → `TranslatorError.blobTooLarge`,
  surfaces as a save failure. The cap is `kRecordBlobSizeCap` in
  `RecordRepresentable.swift`.
- **PendingUploadFlags is `{dirty: Set<String>, deleted: Set<String>}`**
  not a bitset. Marking dirty clears the deleted entry and vice versa.

## Stage B + lifecycle (Phase 5 tasks 18–29)

Stage B coordinator, engine ownership gate, snapshot maintenance,
trip deletion, remote-notification routing, and the launch wiring
have all landed. Files:

- `Scramble/Scramble/Persistence/Migrations/ZoneMigrationCoordinator.swift` —
  two-phase API. `enqueueAll()` inserts `.pending`
  `MigrationJournalEntry` rows for trips without a `TripZoneState`;
  `runStageB()` transitions them to `.stageBInProgress`, inserts the
  `TripZoneState`, marks every expected record dirty in
  `pendingUploadFlags`, persists the expected record-name set on the
  journal, and signals the `ZoneMigrationDriver` to save the zone +
  queue uploads. Event handlers
  (`handleZoneSaved` / `handleRecordsSaved` / `handleRecordsFailed`)
  drive each journal row to a terminal state. `retry(tripID:)`
  re-runs `.failed` entries. Skipped entirely when
  `isCloudAvailable()` returns false.
- `ZoneMigrationDriver` protocol — test seam over
  `CKSyncEngine.State.add(...)`. Production wiring is
  `TripSyncEngineZoneMigrationDriver`.
- `Models/Schema.swift` — `MigrationJournalEntry` gained
  `expectedRecordNamesData`, `sentRecordNamesData`, and
  `zoneSavedFlag` (all Optional so SwiftData column inference is
  safe). New `MigrationStageState` enum + bridge properties
  (`state`, `expectedRecordNames`, `sentRecordNames`, `zoneSaved`,
  `isStageBComplete`).
- `Scramble/Scramble/RulesEngine/RulesEngineRunner.swift` — gained
  the optional `ownerIdentity: (UUID) -> OwnerIdentity?` closure.
  `runForTrip` and `runForAllNonPastTrips` skip trips owned by
  `.otherUser` (`nil` and `.currentUser` both run). Default closure
  returns `nil` so Phase 1 call sites keep working.
- `Scramble/Scramble/RulesEngine/RulesEngineTriggerOrchestrator.swift` —
  bridges `TripSyncEngine.events` to the rules engine. `.zoneChanged`
  with `isSelfOriginated == true` is dropped (echo guard); remote
  changes are routed to `RulesEngineRunner.runForTrip` for the
  matching trip.
- `Scramble/Scramble/Sharing/SnapshotMaintenance.swift` —
  `propagatePersonEdit` (Person → snapshot fan-out, owner-only),
  `handleRosterRemoval` (flip `isRosterMember=false` + delete when no
  referrers), `handlePackingItemDeletion` (delete non-roster
  snapshots when their last item is removed), and `sweep`
  (defence-in-depth periodic cleanup). Referrer counting walks
  `TripPackingItem` directly because the snapshot ↔ packing-item
  inverse was dropped in V3 to avoid the SwiftData cascade panic
  (persistence note).
- `Scramble/Scramble/Sharing/TripDeletion.swift` —
  `TripDeletion.delete(tripID:in:zoneDeleter:)` runs the reverse
  cascade (`pendingUploadFlags → packing items → tasks → snapshots
  → trip → TripZoneState`) in one transaction. Owner-scope deletes
  also queue `deleteZone` via `TripSyncEngineZoneDeleter`.
  Participant-side leaves pass `zoneDeleter: nil` because
  `CloudKitSharingService.leaveShare` already deletes the
  shared-DB zone.
- `Scramble/Scramble/App/AppDelegate.swift` —
  `UIApplicationDelegate` adapter. `userDidAcceptCloudKitShareWith`
  forwards to `SharingService.acceptShare`;
  `didReceiveRemoteNotification:fetchCompletionHandler:` dispatches
  to `RemoteNotificationRouter`. Both dependencies are pulled from
  `AppDelegate.environment`, which `ScrambleApp.init` sets at launch.
- `Scramble/Scramble/App/RemoteNotificationRouter.swift` —
  policy object that switches on `CKDatabase.Scope` and calls the
  matching engine's `fetchChanges()`. Returns
  `UIBackgroundFetchResult` for the UIKit completion handler.
  Production fetcher is `TripSyncEngineNotificationFetcher`.
- `Scramble/Scramble/App/MigrationGate.swift` — launch-blocking
  splash view. Runs `enqueueAll() + runStageB()` once Stage A is
  done, then starts the sync engine + event observer (skipped in
  test / UI-test / preview branches), then mounts the wrapped
  content.
- `Scramble/Scramble/Persistence/SharingServiceEnvironmentKey.swift` —
  `\.sharingService` environment carrier (Optional; `nil` for
  previews / tests).
- `Scramble/Scramble/ScrambleApp.swift` — constructs every Phase 5
  collaborator (sync engine, sharing service, coordinator, router,
  trigger orchestrator), wires `AppDelegate.environment`, wraps
  `RootView` in `MigrationGate`, and injects
  `\.sharingService` into the view environment. The cold-launch
  `RulesEngineRunner` now passes `service.ownerIdentity(forTrip:)`
  through to the gate.

## Tests (ScrambleTests)

- `Persistence/ZoneMigrationCoordinatorTests.swift` — happy path,
  ownership gate, resume after kill, retry, parameterised PBT
  scenarios (idempotence, convergence over failure/retry
  sequences, resume totality across every journal state).
- `RulesEngine/RulesEngineOwnershipGateTests.swift` — engine
  no-ops for `.otherUser` trips, runs for `.currentUser` / `nil`,
  fan-out filters by ownership, orchestrator drops self-originated
  events and only fires for properly-formed zone names.
- `Sharing/SnapshotMaintenanceTests.swift` — every cleanup
  trigger plus the ownership gate.
- `Sharing/TripFlagSyncTests.swift` — `pinnedByUser` and
  `userDeletedOnThisTrip` survive translator round-trip; engine
  preserves pinned items even when their rules no longer match.
- `Sharing/TripDeletionTests.swift` — reverse-cascade ordering,
  zone deletion enqueued on owner-side only, idempotent against a
  missing trip.
- `Sharing/RemoteNotificationRoutingTests.swift` — `.private`,
  `.shared`, `.public`, and fetcher-failure paths return the
  right `UIBackgroundFetchResult`.

## Conventions reminder

- `MigrationJournalEntry.state` is the canonical surface; never
  read `stateRaw` directly outside `Schema.swift`.
- `ZoneMigrationCoordinator` event handlers (`handleZoneSaved`,
  `handleRecordsSaved`, `handleRecordsFailed`) are the **only**
  way to drive a journal row past `.stageBInProgress`. Don't
  mutate `state` from view code.
- `TripDeletion.delete(...)` is the canonical owner-side trip
  removal path. Direct `context.delete(trip)` from CRUD code
  bypasses the engine's zone-delete enqueue and leaves the
  remote zone live.
- `RulesEngineRunner`'s `ownerIdentity` closure treats `nil` as
  "current user owns" — Phase 1 legacy trips without a
  `TripZoneState` keep receiving engine runs.
