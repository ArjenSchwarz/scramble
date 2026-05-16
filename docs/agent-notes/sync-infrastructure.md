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

## Open Phase 5 work (not yet implemented)

- Stage B `ZoneMigrationCoordinator` (tasks 18–23) — the per-trip
  default-zone → trip-zone data move driven by `TripSyncEngine`. This
  is what actually populates `tripsLocal` from existing data.
- `MigrationGate` + Stage A → engine startup ordering (tasks 24+).
- Share-acceptance entry point in `AppDelegate` (task 26).
- Trip Detail UI surfaces — `ShareToolbarButton`, `ParticipantsSection`,
  `MigrationRetryBanner` (tasks 28–32).
- Snapshot maintenance routines (tasks 33–35).

The current scaffolding lets these later tasks land without rebuilding
the persistence split or the sync engine; the production
`CloudKitSharingService` is wired into `TripSyncEngine` and ready to
serve once `MigrationGate` releases the UI.
