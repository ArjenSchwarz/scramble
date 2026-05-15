# Design: Phase 5 — CloudKit Sharing

## Overview

One `CKShare` per trip, one CloudKit custom zone per trip. Persistence is split into two SwiftData containers: a private-cloud-paired **globals** container for `Person` / master lists, and a **local-only** SwiftData container for trip-zone entities (`Trip`, `TripTask`, `TripPackingItem`, `TripPersonSnapshot`, `TripZoneState`). Cross-device sync of the local container's records is driven by two `CKSyncEngine` instances — one bound to the private database (owner-side trip zones), one to the shared database (participant-side accepted zones). `SchemaV3` adds the snapshot + zone-state entities and the migration journal. Phase 5 also lands the share-creation / acceptance / leave plumbing and the Trip Detail UI surfaces.

## Architectural pivot from earlier draft

Codex's read of the iOS 26.4 SDK headers established that `ModelConfiguration.CloudKitDatabase` exposes only `.automatic`, `.private(String)`, and `.none` — there is no `.shared` case. The earlier "one `ModelContainer` per trip zone" plan worked for owners only; participants could not mount accepted shared zones through SwiftData. This design uses `CKSyncEngine` (iOS 17+) instead, which is the supported public-API path for both owner and participant scopes. See [Decision 13](decision_log.md#decision-13-pivot-from-per-zone-modelcontainers-to-cksyncengine-for-trip-zone-sync-supersedes-decision-6).

## Validation gate (still front-loaded)

Before tasks for the rest of Phase 5 are written, validate the CKSyncEngine lifecycle on iOS 26 end-to-end:

1. Owner device A: create a private-DB `CKSyncEngine`, create a custom zone, write a record, observe `sentRecordZoneChanges` event.
2. Owner device A: create a `CKShare` rooted at that record, present `UICloudSharingController`, send invite.
3. Participant device B: accept share via `UIApplicationDelegateAdaptor.application(_:userDidAcceptCloudKitShareWith:)`. Stand up a shared-DB `CKSyncEngine`. Observe `fetchedRecordZoneChanges` event delivering the record.
4. B writes back; A observes the change.

| Outcome | Action |
|---|---|
| Both directions work via `CKSyncEngine` on iOS 26 | Proceed |
| Either direction fails | Stop. Re-evaluate Decision 13 with a fallback (raw `CKDatabase` operations + manual zone-change tokens) |

The validation lands as the first commit on the Phase 5 branch and gates merging anything else.

## Architecture

### Persistence layout

Two SwiftData containers, both `@MainActor`-mounted at app start:

| Container | `cloudKitDatabase` | Holds |
|---|---|---|
| `globals` | `.private("iCloud.me.nore.ig.scramble")` | `Person`, `MasterTaskItem`, `MasterPackingItem`, `MigrationJournalEntry` |
| `tripsLocal` | `.none` | `Trip`, `TripTask`, `TripPackingItem`, `TripPersonSnapshot`, `TripZoneState` |

`globals` continues to use SwiftData's CloudKit mirror — no sharing, just per-user private sync. `tripsLocal` is the local cache for everything sharable; cloud sync is driven by `TripSyncEngine` (below), not by SwiftData's mirror.

`ModelStore` (Phase 1) becomes the factory for both containers. `EnvironmentProbe` branches as before; tests get in-memory variants of both.

### Single dirty-marking chokepoint

Every local mutation of a `tripsLocal` `@Model` flows through `LocalWriteHook.commit(_:)` (in `Sharing/LocalWriteHook.swift`). Call sites (Trip CRUD, Tasks UI, Packing Sheet, rules engine, snapshot maintenance) all invoke `LocalWriteHook.commit` instead of `context.save()` directly. The hook:

1. Inspects `context.insertedModels`, `context.changedModels`, `context.deletedModels`.
2. For each affected entity, computes its `tripZoneID` and dirty-bit position.
3. Reads the corresponding `TripZoneState`, ORs the new dirty flags into `pendingUploadFlags`, persists.
4. Calls `context.save()`.
5. Notifies `TripSyncEngine.privateEngine.state.add(pendingRecordZoneChanges:)` with the dirty record IDs (or `sharedEngine` for participant-side edits).

This is the single chokepoint — no call site marks records dirty by hand. Lint rule (or code-review checklist item): direct `context.save()` on `tripsLocal` is forbidden outside `LocalWriteHook`.

### `TripSyncEngine`

Wraps two `CKSyncEngine` instances behind one façade:

```swift
@MainActor
final class TripSyncEngine {
    init(local: ModelContext, container: CKContainer)
    let privateEngine: CKSyncEngine   // database scope: .private
    let sharedEngine: CKSyncEngine    // database scope: .shared
    var events: AsyncStream<TripSyncEvent> { get }
}

enum TripSyncEvent {
    case zoneChanged(CKRecordZone.ID, scope: CKDatabase.Scope, isSelfOriginated: Bool)
    case recordsFetched([CKRecord], in: CKRecordZone.ID)
    case shareAccepted(CKRecordZone.ID, ownerName: String)
    case zoneRemoved(CKRecordZone.ID)
    case error(CKSyncEngine.Event.SendChangesError)
}
```

`CKSyncEngine` invokes a delegate (`CKSyncEngineDelegate`) for two responsibilities:

1. **Provide pending changes to send** — `nextRecordZoneChangeBatch(_:syncEngine:)`. We iterate `tripsLocal` for records the local app has marked dirty (`TripZoneState.pendingUpload` flag, plus per-record dirty bits maintained by the write path) and translate them to `CKRecord` modifications.
2. **Receive fetched changes** — `handleEvent(_:syncEngine:)`. We translate `CKRecord` updates into local `@Model` writes, and propagate share-acceptance / zone-removal events upward.

Both engines persist their own state (last-known server change tokens, pending operations) using `CKSyncEngine.Configuration.stateSerialization` — opaque blob we store in a side-file alongside the SwiftData store URL. SwiftData is not aware of the sync state.

### `@Model` ↔ `CKRecord` translation

For each trip-zone entity there is a small translator that maps both ways. The mapping is mechanical (one record type per `@Model` class; record name = entity `id.uuidString`; zone = the entity's `tripZoneID`).

```swift
protocol RecordRepresentable {
    static var recordType: String { get }
    var recordID: CKRecord.ID { get }                 // computed from id + zoneID
    func toRecord(existing: CKRecord?) -> CKRecord    // merge into existing if present
    static func from(_ record: CKRecord, into context: ModelContext) throws
}
```

Translator rules (apply uniformly across all entity translators):

- **Relationships are stored as UUID-valued record fields**, not `CKRecord.Reference`. A `TripPackingItem`'s `personSnapshot` is encoded as `personSnapshotID: String` on the `CKRecord`; lookup at decode-time happens against `tripsLocal`. This avoids cross-record dependency ordering inside `CKSyncEngine` batches.
- **System fields are preserved on every write.** `existing: CKRecord?` is constructed by decoding the entity's `ckRecordSystemFields` blob via `CKRecord(coder:)`. If absent, a new record is created. After every send/fetch, the translator re-encodes system fields back into the entity.
- **Codable blob fields** (`TripAttributes`, `ItemConditions`) are encoded with `JSONEncoder` into `Data` fields on the record. Hard size cap of 256 KB per blob — exceeded blobs throw a translator error and surface as a migration/save failure.
- **Enum-valued fields** continue to use the Phase 1 raw-string convention (`stateRaw`, `phaseRaw`, etc.) — the record field is the same `String`.
- **Optional → Optional** maps directly. Non-Optional Swift fields with no record value (e.g., default-only fields added in V3 to a record fetched from a V2-shaped older device) decode to the Swift default.

Translators live in `Sharing/Translators/` (one file per entity).

### Schema and data model

`SchemaV3` is the third versioned schema. The relationship retypes from Phase 2 are reframed as **additive** to avoid the same-name-retype risk Codex flagged: V3 introduces new fields with new names, V3 backfills them, V4 removes the deprecated fields.

Phase 5 ships V3 only. V4 cleanup is deferred (added to the spec's Non-Goals).

New entities (in `tripsLocal`):

```swift
@Model
final class TripPersonSnapshot {
    var id: UUID
    var personID: UUID                              // owner-side Person.id; opaque to participants
    var name: String
    var colourID: String
    var initialSource: String
    var isRosterMember: Bool                        // toggled when added/removed from trip.participantSnapshots
    @Relationship var trip: Trip?                   // inverse of Trip.participantSnapshots (V3 field name)
    @Relationship var tripPackingItems: [TripPackingItem]?  // inverse of TripPackingItem.personSnapshot
    var ckRecordSystemFields: Data?                 // CKRecord system fields cache (encoded)
}

@Model
final class TripZoneState {
    var tripID: UUID
    var zoneOwnerName: String                       // CKCurrentUserDefaultName for owned zones
    var zoneScope: String                           // "private" | "shared"
    var shareID: String?                            // CKShare.recordID.recordName
    var pendingUploadFlags: Data                    // bitset / Codable struct of which records dirty
    var ckRecordSystemFields: Data?
}
```

In `globals`:

```swift
@Model
final class MigrationJournalEntry {
    var tripID: UUID
    var stateRaw: String                            // .pending | .stageADone | .stageBInProgress | .completed | .failed
    var errorMessage: String?
    var updatedAt: Date
}
```

V3 changes to existing entities (additive — old fields kept, marked deprecated):

| Entity | New V3 field | Deprecated V2 field (removed in V4) |
|---|---|---|
| `Trip` | `participantSnapshots: [TripPersonSnapshot]?` (inverse) | `participants: [Person]?` |
| `Trip` | `tripZoneID: UUID?` (links to `TripZoneState.tripID`) | — |
| `Trip` | `ckRecordSystemFields: Data?` | — |
| `TripTask` | `ckRecordSystemFields: Data?` | — |
| `TripPackingItem` | `personSnapshot: TripPersonSnapshot?` | `person: Person?` |
| `TripPackingItem` | `ckRecordSystemFields: Data?` | — |

`Trip.participantSnapshots` cascade rule is `.cascade` for snapshot lifetime; per-element removal is handled by the cleanup routine below, not by the relationship setter.

### Snapshot cleanup routine

Lives in `Sharing/SnapshotMaintenance.swift`. Runs in three triggers on the owner's device:

1. **Person removed from trip roster** (`Trip.participantSnapshots` element removed): set `snapshot.isRosterMember = false`. If `snapshot.tripPackingItems?.isEmpty == true`, delete the snapshot in the same transaction. Otherwise leave it for [3].
2. **TripPackingItem deleted**: if its `personSnapshot.isRosterMember == false` AND that snapshot now has no remaining `tripPackingItems`, delete the snapshot.
3. **Periodic sweep** (engine post-run): scan `TripPersonSnapshot` where `!isRosterMember && tripPackingItems.isEmpty`, delete.

This satisfies Req [2.4](requirements.md#2.4) without depending on SwiftData's relationship cascade rules (which only fire on parent deletion, per Codex's design-critic finding).

### `Person → TripPersonSnapshot` propagation

Trigger: any `Person` write on the owner's device. Implementation:

1. SwiftData `@Observable` notification on `Person` change — wired via `ModelContext.modelChangedNotification`.
2. For the changed `Person`, query all `TripPersonSnapshot` where `personID == person.id AND trip.tripZoneID != nil` (i.e., across every accessible trip zone the owner participates in).
3. Update `name`, `colourID`, `initialSource` on each snapshot in a single context save.
4. Mark the corresponding `TripZoneState.pendingUploadFlags` for those snapshot records dirty.
5. Schedule `TripSyncEngine.privateEngine.sendChanges()`.

Owner-only — gated by `isCurrentUserOwner(of:)` on `TripZoneState`. Eventual consistency for participants per Req [2.3](requirements.md#2.3).

### Migration pipeline

Two stages at launch, read from `MigrationJournalEntry`. Both stages live in `Persistence/Migrations/`.

**Stage A — `SchemaV2 → SchemaV3` (additive, lightweight where possible).**

The schema additions (new fields + new entities) are lightweight per `MigrationStage.lightweight`. The non-lightweight piece — backfilling `TripPersonSnapshot` rows from existing `Person` references — runs in a `MigrationStage.custom` post-step:

- For every `Trip` in V2: for each `Person` in `trip.participants`, insert a `TripPersonSnapshot(personID: person.id, name: person.name, colourID: person.colourID, initialSource: person.initialSource, isRosterMember: true)` and append to `trip.participantSnapshots`.
- For every `TripPackingItem`: look up the snapshot for `item.person.id` within the same trip and set `item.personSnapshot = snapshot`.
- The deprecated V2 fields are not modified — they remain populated and will be removed in V4.

Stage A is offline-safe (no CloudKit) and runs unconditionally — Req [11.3](requirements.md#11.3) signed-out condition does not skip it.

**Stage B — Default zone → per-trip zones via `CKSyncEngine` (online-only).**

For each trip with no `TripZoneState`:

1. Insert `MigrationJournalEntry(tripID: trip.id, state: .stageBInProgress)` in globals.
2. Compute deterministic `zoneID = CKRecordZone.ID(zoneName: "trip-\(trip.id.uuidString)", ownerName: CKCurrentUserDefaultName)` (Req [4.9](requirements.md#4.9)).
3. Insert `TripZoneState(tripID: trip.id, zoneOwnerName: CKCurrentUserDefaultName, zoneScope: "private", shareID: nil, pendingUploadFlags: <all-records-dirty>)` in `tripsLocal`.
4. Set `trip.tripZoneID = zoneState.tripID`.
5. Tell `TripSyncEngine.privateEngine` to create the zone (`CKSyncEngine.State.add(pendingDatabaseChanges: [.saveZone(zoneID)])`).
6. Compute the **expected record-ID set** for the trip (`Trip` + every `TripTask` + every `TripPackingItem` + every `TripPersonSnapshot`); persist that set on the journal entry. Mark every record dirty in `TripZoneState.pendingUploadFlags`.
7. Tell `privateEngine.state.add(pendingRecordZoneChanges:)` for the record IDs; trigger `sendChanges()`. `CKSyncEngine` handles batching, retries, conflict resolution.
8. Stage B for this trip is `.completed` when **all** of the following hold: (a) every expected record ID has appeared in cumulative `sentRecordZoneChanges.savedRecords` across one or more events with `failedRecordSaves` empty for those IDs, (b) `privateEngine.state.pendingRecordZoneChanges` no longer contains any of the expected IDs, and (c) the zone-save event for this trip's zone succeeded. Single-event detection is unreliable; correlate across events.

Step 7 is **not** a synchronous wait — `MigrationGate` releases the UI as soon as Stage A completes (or as soon as journal entries hit terminal-or-`stageBInProgress`). Stage B continues in the background after launch. The Trip List shows a per-trip "Syncing…" badge for trips whose journal is `.stageBInProgress`; trips are interactable during this period (writes accumulate in `pendingUploadFlags` and flow up when Stage B finishes).

**Cleanup of records in CK default zone.** After Stage B for a trip completes, the design relies on the participant's view of the records being sourced exclusively from the trip zone. Old records in CK default zone become orphaned; they don't appear locally because the local cache is canonical and the owner's device knows to look in the trip zone. A separate sweep deletes them via `CKDatabase.modifyRecords(deleting:)` after journal `.completed` — failures here are non-blocking and logged.

**Concurrent-device migration race.** Two of the owner's devices both running V3 will both target the same deterministic zone. `CKSyncEngine` handles record-level deduplication by `recordID` (last-writer-wins on the actual fields). For zone creation, `CKModifyRecordZonesOperation` is idempotent — second device's zone-create is a no-op. The original Decision 11 claim record is not needed; `CKSyncEngine`'s state machine performs the equivalent coordination. Decision 11 is updated accordingly.

**Resume after kill.** On launch, read `MigrationJournalEntry` rows; for `.stageBInProgress` entries, re-run Stage B from step 5 (zone create is idempotent; record uploads use `CKSyncEngine`'s own pending-changes state).

**UI modality.** `MigrationGate` releases the UI when no `MigrationJournalEntry.state == .pending` (i.e., Stage A has completed for every existing trip). Stage B continues in the background after release; trips with `.stageBInProgress` show a "Syncing…" badge in the Trip List. Failed Stage B trips surface a retry banner. Signed-out: skip Stage B entirely; show all locally migrated trips in local-only mode.

**Stage A → engine startup ordering.** `TripSyncEngine` is constructed only after `MigrationGate` releases. This guarantees `tripsLocal` has been backfilled with `TripPersonSnapshot` rows and V3-shaped fields before either `CKSyncEngine` instance starts fetching. If an engine were started earlier, fetched records arriving for V2-shaped local entities would have nowhere to merge into.

**`CKSyncEngine.State` corruption recovery.** State serialization blobs are stored at `~/Library/Application Support/Scramble/CKSync/{private,shared}.state`. On launch, decode failure for either blob triggers: (a) discard the corrupt blob, (b) construct the engine with no prior state, (c) request a full `fetchChanges()` to reconcile against server truth. The `tripsLocal` cache is unaffected — re-fetched records collide with existing local rows by record ID and translators apply LWW. The blobs are excluded from iCloud Backup via the standard `URLResourceKey.isExcludedFromBackupKey`.

### Sharing service

```swift
protocol SharingService {
    func createShare(forTrip tripID: UUID) async throws -> CKShare
    func presentShareUI(for share: CKShare, rootRecord: CKRecord) async       // wraps UICloudSharingController
    func acceptShare(_ metadata: CKShare.Metadata) async throws -> AcceptedShareResult
    func leaveShare(forTrip tripID: UUID) async throws
    func participants(forTrip tripID: UUID) async throws -> [ShareParticipant]
    func ownerIdentity(forTrip tripID: UUID) -> OwnerIdentity?                // synchronous; reads TripZoneState
}

struct AcceptedShareResult {
    let zoneID: CKRecordZone.ID
    let ownerDisplayName: String?
}

enum OwnerIdentity { case currentUser; case otherUser(displayName: String?) }
```

Subscriptions are managed by `CKSyncEngine` automatically — the engine registers `CKDatabaseSubscription` on the shared DB and `CKRecordZoneSubscription` on owned zones via its own internal logic. We do not register subscriptions manually. This supersedes the per-zone subscription detail in Decision 12 (see decision-log update).

`createShare` flow (zone-wide share, not root-record share — Codex's SDK-header reading confirmed this is the right primitive when each trip already has a dedicated zone, and dissolves the "save root-record + share atomically" complication):

1. Build `CKShare(recordZoneID: zoneState.zoneID)`. Set `publicPermission = .none`.
2. Tell `privateEngine`: `state.add(pendingRecordZoneChanges: [.saveRecord(share.recordID)])`. The delegate's `nextRecordZoneChangeBatch(_:syncEngine:)` returns the actual `CKRecord` for the share when the engine asks.
3. On `sentRecordZoneChanges` confirming the share record was saved, set `TripZoneState.shareID = share.recordID.recordName` and resolve the `async throws` return.
4. `presentShareUI(for:)` wraps `UICloudSharingController` initialised with the share. The wrapper is a `UIViewControllerRepresentable` in `Sharing/UICloudSharingControllerRepresentable.swift`.

`acceptShare` flow:

1. `CKContainer.accept(_:)` for the metadata.
2. Call `sharedEngine.fetchChanges()`. Participants do not call `.saveZone` — they don't create the zone; the zone arrives via `fetchedDatabaseChanges` event followed by `fetchedRecordZoneChanges` events from the engine itself.
3. As records arrive in the delegate, translator inserts the trip + records into `tripsLocal` and creates `TripZoneState(zoneScope: "shared", zoneOwnerName: <metadata.ownerIdentity.userRecordID.recordName>, ...)`.

`leaveShare` flow:

1. `CKDatabase.delete(withRecordZoneID: zoneID)` on the shared DB (the participant's "leave" affordance).
2. Local cleanup: in trip-deletion order (packing items → tasks → snapshots → trip → zone state), delete from `tripsLocal`.

Concrete impl `CloudKitSharingService`. Test impl `FakeSharingService` implements an in-process two-side transport — see Testing Strategy.

### Engine ownership gate

The Phase 2 rules-engine entry point gains a single guard:

```swift
guard sharingService.ownerIdentity(for: trip.id) == .currentUser else { return }
```

Engine triggers (Phase 2 set + the Req [8.6](requirements.md#8.6) addition):

| Trigger | Source | Owner-only? | Echo guard |
|---|---|---|---|
| Trip created | Trip CRUD | yes (creator owns) | n/a |
| Trip attribute edited | Trip editor | yes (gate) | n/a |
| Master item edited | Master Lists tab | yes (fan-out filtered) | n/a |
| App launch | `Scene.onChange(of: scenePhase) { _, new in if new == .active }` | yes (per-trip gate) | n/a |
| **CloudKit-received change** | `TripSyncEngine.events` filtered to `.zoneChanged` | yes (gate) | **yes — ignore events where `isSelfOriginated == true`** |

`isSelfOriginated` flag is set by the translator when applying changes that were just sent by this device — `CKSyncEngine` provides the originating change token via the event. This prevents the owner's engine from re-triggering on its own writes.

### UI surfaces

| Surface | File | Notes |
|---|---|---|
| Share toolbar button | `Views/TripDetail/ShareToolbarButton.swift` | Trip Detail header trailing toolbar item; matches existing toolbar style; visible iff `OwnerIdentity == .currentUser` |
| Participants section | `Views/TripDetail/ParticipantsSection.swift` | Sits between header and timeline; renders `[ShareParticipant]`; tap opens `UICloudSharingController` for owners; static for participants. Pending-name placeholder per Req [7.8](requirements.md#7.8) |
| WhyDisclosure participant branch | `Views/Common/WhyDisclosure.swift` | Existing component; for shared-trip items where `masterItemID` does not resolve in `globals`, the affordance is hidden (no view rendered) per Req [3.3](requirements.md#3.3) |
| "Rules last evaluated" subline | Existing Trip Detail header subline | Append clause for participant-viewed shared trips; uses Phase 1 `RelativeDateFormatter` |
| Migration retry banner | `Views/TripList/MigrationRetryBanner.swift` | One row per `.failed` `MigrationJournalEntry`; tap → re-runs Stage B for that trip |
| Trip List "Syncing…" badge | Existing TripRow | Shown for `.stageBInProgress` entries |
| "Network required to share" alert | Existing alert pattern | Phase 1 helper |
| Sign-out / iCloud unavailable | Existing local-only fallback (Phase 1 `ModelStore`) | Hides Share affordance and skips Stage B |

### File / module placement

```
Scramble/Scramble/Sharing/
    SharingService.swift                  // protocol + DTOs
    CloudKitSharingService.swift          // production impl (uses TripSyncEngine + CKContainer + UICloudSharingController)
    FakeSharingService.swift              // test impl with in-process two-side transport
    TripSyncEngine.swift                  // CKSyncEngine wrapper + delegate
    LocalWriteHook.swift                  // single dirty-marking chokepoint for tripsLocal saves
    SnapshotMaintenance.swift             // Person→snapshot propagation + cleanup routines
    UICloudSharingControllerRepresentable.swift  // UIViewControllerRepresentable wrapper
Scramble/Scramble/Sharing/Translators/
    TripRecordTranslator.swift            // @Model ↔ CKRecord per entity
    TripTaskRecordTranslator.swift
    TripPackingItemRecordTranslator.swift
    TripPersonSnapshotRecordTranslator.swift
    CKShareRecordHandler.swift            // share record write/read
Scramble/Scramble/Persistence/Migrations/
    SchemaV3MigrationStage.swift          // Stage A
    ZoneMigrationCoordinator.swift        // Stage B (CKSyncEngine-driven)
Scramble/Scramble/Models/
    Schema.swift                          // existing — add SchemaV3, TripPersonSnapshot, TripZoneState, MigrationJournalEntry
Scramble/Scramble/App/
    MigrationGate.swift                   // launch-blocking root wrapper for Stage A
    AppDelegate.swift                     // new: UIApplicationDelegateAdaptor for share-acceptance + remote notifications
    ScrambleApp.swift                     // existing — add UIApplicationDelegateAdaptor + scenePhase trigger
Scramble/Scramble/Views/TripDetail/
    ShareToolbarButton.swift
    ParticipantsSection.swift
Scramble/Scramble/Views/TripList/
    MigrationRetryBanner.swift
```

## Components and Interfaces

Non-obvious behavioural contracts:

- **`TripSyncEngine.events` is the single propagation point.** All view code observes via `@Query` on `tripsLocal`; the engine writes into that container and views update through SwiftData's normal change-notification path. There is no second observation channel to UI.
- **`ckRecordSystemFields` must be preserved.** Every translator that converts `@Model → CKRecord` for an existing remote record must use the existing `CKRecord` (decoded from cached system fields) as the base. Failing to preserve system fields causes every save to look like a new record to CloudKit.
- **`CKSyncEngine.State` is per-engine-instance and must outlive the engine across launches.** Stored in a side-file `~/Library/Application Support/Scramble/CKSync/{private,shared}.state`. On reset (e.g., user sign-out), discard.
- **`SharingService.ownerIdentity(for:)` is synchronous and reads only `TripZoneState` (Req [10.4](requirements.md#10.4)).** No I/O. The cached value is invalidated when the engine receives a `zoneRemoved` event for that zone or the user signs out.
- **`MigrationGate` blocks UI only on Stage A.** Stage B runs in the background after release; trips with `.stageBInProgress` are interactable but show a "Syncing…" badge.
- **Trip-deletion ordering.** Owner deletes a trip by deleting the trip's `CKRecordZone`. Local cleanup is: (a) clear `pendingUploadFlags`, (b) delete `TripPackingItem` and `TripTask` rows, (c) delete `TripPersonSnapshot` rows, (d) delete `Trip`, (e) delete `TripZoneState`. Done in one transaction. The reverse-cascade order avoids the snapshot-cascade issue from the previous design draft.
- **Share-acceptance entry point** is `AppDelegate.application(_:userDidAcceptCloudKitShareWith:)` because the SwiftUI scene-level `.userDidAcceptCloudKitShare` modifier does not exist.
- **Push notification routing** branches on the notification's `databaseScope`: `.private` → call `privateEngine.fetchChanges()`; `.shared` → call `sharedEngine.fetchChanges()`. Handler lives in `AppDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`. The engines emit delegate callbacks asynchronously after the fetch completes; the completion handler is called once the relevant engine signals fetch completion.

## Data Models

Covered in Architecture > Schema and data model.

## Error Handling

`CKSyncEngine` surfaces failures via its delegate event stream. Categorisation (informs Req [11.4](requirements.md#11.4)):

| Category | Examples | Surfacing |
|---|---|---|
| Transient | `.networkUnavailable`, `.requestRateLimited`, `.zoneBusy`, `.serviceUnavailable` | Logged; `CKSyncEngine` retries automatically with backoff. UI alert only when blocking a user-initiated share/accept/leave. |
| Quota | `.quotaExceeded` | Logged + always surfaced to user. Pending writes remain queued. |
| Conflict | `.serverRecordChanged` | `CKSyncEngine` surfaces the server record; translator applies LWW per attribute. No UI. |
| Account / permission | `.notAuthenticated`, `.permissionFailure`, `.userDeletedZone` | Logged + actionable alert. `userDeletedZone` for participants triggers automatic local cleanup (zone gone → Trip removed locally). |
| Migration-specific | Any error thrown during Stage B | Captured into `MigrationJournalEntry.errorMessage`; surfaced via Trip List banner; tap retries. |

## Testing Strategy

| Concern | Vehicle |
|---|---|
| Schema V3 plan shape | `SchemaV3MigrationTests` — verifies `AppMigrationPlan.schemas`, `stages`, lightweight + custom stage typing. Mirrors persistence-note pattern. |
| Stage A backfill | `SchemaV3MigrationStageTests` — seed V2-shaped in-memory store with `Trip + Person + TripPackingItem`; run Stage A; assert `TripPersonSnapshot` inserted, `Trip.participantSnapshots` populated, `TripPackingItem.personSnapshot` set, deprecated `participants`/`person` fields untouched. Idempotent on second run. |
| Stage B + `TripSyncEngine` | `ZoneMigrationCoordinatorTests` against `FakeSharingService` — happy path, kill-mid-migration resume, signed-out skip + later resume, failure + retry. |
| Snapshot maintenance | `SnapshotMaintenanceTests` — Person edit propagation; cleanup on roster removal; cleanup on packing-item deletion; periodic sweep. |
| Sharing flows | `SharingServiceTests` — share creation, acceptance (in-process two-side transport), leave, participant fetch. |
| Engine ownership gate + echo suppression | `RulesEngineOwnershipGateTests` — engine no-op for non-owned trips; engine runs for owner; engine ignores `isSelfOriginated` events. |
| Trip-global flag semantics | `TripFlagSyncTests` — pinned/userDeleted toggles propagate via fake events. |
| Owner-side echo loop | `EchoSuppressionTests` — owner write → fake engine echoes back → assert engine does not re-run. |
| Trip-deletion cascade ordering | `TripDeletionTests` — deletion order verified; no orphaned snapshots; `TripZoneState` cleared. |
| Push notification routing | `RemoteNotificationRoutingTests` — `.private`-scope notification routes to `privateEngine`; `.shared` to `sharedEngine`. |
| UI: Share affordance visibility | `ScrambleUITests` — owner sees, participant does not. |
| UI: Participants section | `ScrambleUITests` — pending vs accepted distinction; display-name fallback chain. |
| Production schema deployment | Manual checklist item in `docs/release-prep.md` (or equivalent) per Req [13](requirements.md#13). |
| End-to-end real CloudKit | Manual test plan in `specs/phase-5-cloudkit-sharing/manual-test-plan.md`. |

**`FakeSharingService` design.** A `final class` exposing a `Bus` connecting two `TripSyncEngine`-shaped fake endpoints. Each endpoint has its own `tripsLocal` `ModelContext`. `simulateOwnerWrite(_:)` on side A propagates to side B's fetched-event stream after a controllable async delay (`bus.deliveryDelay`). This makes Reqs [8.6](requirements.md#8.6) / [8.8](requirements.md#8.8) genuinely CI-testable.

**Property-based testing — `ZoneMigrationCoordinator`.** Properties:
- **Idempotence** — running the coordinator twice produces the same `[MigrationJournalEntry]` end state.
- **Convergence** — for any sequence of partial-failure → retry events, the system reaches a terminal state where every entry is `.completed` or `.failed`, with no records duplicated or lost in `tripsLocal`.
- **Resume totality** — for any combination of (in-progress journal entry, partial `pendingUploadFlags`), the resume logic reaches a defined action.

Vehicle: Swift Testing's `@Test` parameterised inputs over hand-rolled generator structs.
