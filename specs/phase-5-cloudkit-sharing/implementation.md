# Implementation: Phase 5 — CloudKit Sharing

This document explains what Phase 5 added to Scramble at three levels of detail and then assesses how completely the 13 requirement clusters from `requirements.md` are realised in the code as of the feature branch `feature/phase-5-cloudkit-sharing`.

---

## Beginner: what Phase 5 does

Until Phase 5, a trip in Scramble lived on one device. Phase 5 makes a trip something a household can share. The owner of a trip can hand a co-traveller a link, and that co-traveller's copy of the app starts showing the same trip — the same packing items, tasks, and people — on their own phone.

Think of every trip as a shared shoebox. Before Phase 5, you each kept your own shoebox under your own bed. Phase 5 gives every trip its own labelled shoebox in a shared cupboard (Apple's iCloud). The owner of the trip puts the shoebox in the cupboard, and anyone they invite gets a key to that single box — not to the cupboard, and not to anyone else's boxes.

Your private notebook of "things I always pack" (the master lists) stays under your bed. So does your contact list of "people who travel with me". The shared shoebox only contains the things the trip needs. When the owner adds Aaron to the trip, the box gets a small index card with Aaron's name and colour written on it; the box does not contain Aaron's whole entry from the owner's contacts. That index card is what everyone else reads when their app draws Aaron's avatar.

When you invite somebody, iOS opens its familiar share sheet, you pick a contact, and tap Send. They get the invitation in Messages or Mail, tap accept, and iOS hands the trip to their Scramble app. They see who is on the trip in a "Participants" list on the trip page — separate from the list of people the trip is packing for, so you can tell at a glance whether somebody is a co-organiser or just a packing-list owner.

If you decide to leave a trip you were invited to, there is a "Leave Share" button in the trip's menu. If you are the trip's owner and you delete it, the shoebox is removed from the cupboard and everybody else's app drops the trip the next time it syncs.

Behind the scenes Phase 5 also did a one-time tidy: every existing trip's data was moved out of the shared cupboard's general drawer and into its own shoebox. The app shows a brief "Preparing your trips…" screen the first time you launch the Phase 5 build, and then keeps quietly finishing the move in the background. If something goes wrong with one trip's move, that single trip shows a small "retry" banner on the Trips list while every other trip works normally.

One technical promise stands out: only the trip's owner runs the rules engine that auto-suggests packing items. Participants see whatever the owner's app last produced. This avoids two devices arguing over what "should" be on the list. If you are looking at a trip somebody else owns, you'll see a small "Rules last evaluated 5 minutes ago" line in the header — that's the app being honest about how fresh those suggestions are.

Phase 5 stops short of push notifications. The shared trip syncs in the background, but it does not buzz your phone when somebody else makes a change. Notifications are Phase 6.

---

## Intermediate: the pivot, the chokepoint, and the translators

Phase 5 began with a plan to mount one `ModelContainer` per trip zone (Decision 6). Reading the iOS 26.4 SDK headers killed that: `ModelConfiguration.CloudKitDatabase` exposes `.automatic`, `.private(String)`, and `.none`, with no `.shared` case. Participants therefore cannot mount accepted shared zones through SwiftData using public API. **Decision 13** pivots to a `CKSyncEngine` model where Scramble owns the local SwiftData store outright and drives sync through two engine instances behind one façade.

### Dual-container split

`ModelStore.makeContainers(probe:)` (Scramble/Scramble/Persistence/ModelStore.swift:73) returns two `ModelContainer`s:

- **`globals`** — `cloudKitDatabase: .private("iCloud.me.nore.ig.scramble")`. Holds `Person`, `MasterTaskItem`, `MasterPackingItem`, and `MigrationJournalEntry`. Continues to use SwiftData's CloudKit mirror — never participates in any share.
- **`tripsLocal`** — `cloudKitDatabase: .none`, stored separately at `~/Library/Application Support/Scramble/TripsLocal.store`. Holds `Trip`, `TripTask`, `TripPackingItem`, `TripPersonSnapshot`, `TripZoneState`. Sync is driven by `TripSyncEngine`, not SwiftData.

Both containers use `SchemaV3` (Scramble/Scramble/Models/Schema.swift:89). The deprecated V2 relationships (`Trip.participants → Person`, `TripPackingItem.person → Person`) are kept until V4 cleanup; new V3 fields (`participantSnapshots`, `tripZoneID`, `personSnapshot`, plus `ckRecordSystemFields` on the three trip-zone entities) are additive.

### Stage A and Stage B

Migration runs in two stages, in order, at launch (Decision 10):

- **Stage A** is `SchemaV2 → SchemaV3` inside `AppMigrationPlan` (Schema.swift:381). SwiftData's lightweight diff adds the new columns/entities; the `.custom` step calls `SchemaV3MigrationStage.backfillSnapshots(in:)` (Scramble/Scramble/Persistence/Migrations/SchemaV3MigrationStage.swift:30) to walk every `Trip`, insert a `TripPersonSnapshot` per roster `Person`, and rewire `TripPackingItem.personSnapshot`. Idempotent (skips persons that already have a snapshot on the trip). Offline-safe — no CloudKit calls.
- **Stage B** is `ZoneMigrationCoordinator` (Scramble/Scramble/Persistence/Migrations/ZoneMigrationCoordinator.swift:27). Two-phase API so the gate can release the UI quickly:
  - `enqueueAll()` inserts a `MigrationJournalEntry(.pending)` per trip without a `TripZoneState`.
  - `runStageB()` walks `.pending` and `.stageBInProgress` journals; for each it computes the deterministic zone ID `trip-<trip.id.uuidString>`, inserts a `TripZoneState(zoneScope: "private")`, captures the expected record-name set on the journal, marks every record dirty in `pendingUploadFlags`, and asks the `ZoneMigrationDriver` to save the zone + queue the record IDs.

Completion correlates `zoneSaved && expectedRecordNames.isSubset(of: sentRecordNames)` (Schema.swift:281); event handlers `handleZoneSaved` and `handleRecordsSaved` move the journal to `.completed`. Failures land in `handleRecordsFailed`, which surfaces via `MigrationRetryBanner` on the Trip List.

### Stage A → engine startup ordering

`ScrambleApp.prepareLaunch()` (Scramble/Scramble/ScrambleApp.swift:122) runs `enqueueAll() → runStageB() → syncEngine.start()` in that order, then opens an event-loop `Task` that drains `engine.events` into the `RulesEngineTriggerOrchestrator`. Critically the `TripSyncEngine` is only `start()`ed **after** `enqueueAll()` writes journals and Stage B records dirty bits — otherwise an incoming `fetchedRecordZoneChanges` event would land before the local store has V3-shaped rows to merge into. `MigrationGate` (Scramble/Scramble/App/MigrationGate.swift:30) runs `prepare` inside `.task` on a splash view and releases when it returns.

### LocalWriteHook — the single dirty-marking chokepoint

`LocalWriteHook.commit(_:)` (Scramble/Scramble/Sharing/LocalWriteHook.swift:28) is the only place `tripsLocal`'s context should be saved. It walks `context.insertedModelsArray`, `changedModelsArray`, `deletedModelsArray`, maps each model to a `(tripID, recordName)` pair via `mapping(for:)`, ORs the new dirty/deleted flags into the matching `TripZoneState.pendingUploadFlags`, saves once, and then calls `notifier.notifyPendingChanges(savedRecordIDs:deletedRecordIDs:in:)` so `TripSyncEngine` knows what to upload. Direct `context.save()` on `tripsLocal` outside the hook is forbidden by convention (lint rule / code-review checklist item, design § "Single dirty-marking chokepoint").

### Translators

Each trip-zone entity has a one-file translator under `Scramble/Scramble/Sharing/Translators/` conforming to `RecordRepresentable` (`recordType`, `recordID`, `toRecord(existing:)`, `from(_:into:)`). Translator rules:

- **Relationships as UUID-valued record fields** (`personSnapshotID: String` on the `CKRecord`), not `CKRecord.Reference` — avoids cross-record ordering inside `CKSyncEngine` batches.
- **System fields preserved.** Every entity carries `ckRecordSystemFields: Data?`; `toRecord(existing:)` decodes the cached system fields, mutates the resulting `CKRecord` in place, and the sync engine re-encodes them after every send via `cacheSentSystemFields(of:)` (TripSyncEngine.swift:438).
- **Codable blobs** (`TripAttributes`, `ItemConditions`) encoded with JSON, hard 256 KB cap.
- **Enum-valued fields** continue to use the Phase 1 raw-string convention.

### Echo guard

The owner's engine receives its own writes back as `fetchedRecordZoneChanges`. `TripSyncEngine.markSelfOriginated(_:)` (TripSyncEngine.swift:230) records the IDs the engine just sent; `wasSelfOriginated(_:)` consumes them on the next inbound delivery. `handleFetchedChanges` flags a per-zone `zoneChanged` event with `isSelfOriginated: zoneRecordIDs.allSatisfy { wasSelfOriginated($0) }` (TripSyncEngine.swift:415), and the `RulesEngineTriggerOrchestrator` skips events where the flag is true so the owner's engine does not re-run on its own writes.

### Sharing service surface

`SharingService` (Scramble/Scramble/Sharing/SharingService.swift:9) is an injectable seam: `createShare`, `acceptShare`, `leaveShare`, `deleteOwnedTrip`, `participants`, `ownerIdentity`. Production wires `CloudKitSharingService`; tests wire `FakeSharingService` (in-process two-side bus). `createShare` builds a `CKShare(recordZoneID:)` (zone-wide share, not root-record share — design § "createShare flow") and submits via `privateEngine.state.add(pendingRecordZoneChanges: [.saveRecord(share.recordID)])`. `acceptShare` calls `CKContainer.accept(_:)` then `sharedEngine.fetchChanges()`. `ownerIdentity(forTrip:)` is synchronous, reads only `TripZoneState`, performs no I/O — safe to invoke per render (Req 10.4).

### Trip Detail UI

`TripDetailView` (Scramble/Scramble/Features/Trips/TripDetailView.swift:9) derives ownership from `sharingService?.ownerIdentity(forTrip:)`:

- `.otherUser` → participant view: hides Share toolbar button, swaps Delete-trip for Leave-share, renders a "Rules last evaluated …" subline.
- `nil` (no `TripZoneState` yet) or `.currentUser` → owner view: shows `ShareToolbarButton`, owner-side Delete-trip confirmation.

`ParticipantsSection` (Scramble/Scramble/Features/Trips/ParticipantsSection.swift:19) calls `sharingService.participants(forTrip:)` on `.task` and renders pending/accepted state; owner rows wrap in a button that opens `UICloudSharingControllerRepresentable`.

---

## Expert: trade-offs and gaps that the spec does not call out

### The partial-implementation gap: Trip records still live in globals

The design document is unambiguous (Architecture > Persistence layout): `Trip`, `TripTask`, `TripPackingItem`, `TripPersonSnapshot`, `TripZoneState` live in `tripsLocal`. The implementation only enforces this for the records `LocalWriteHook` writes — Stage B record uploads, sync-engine writes, snapshot maintenance. The user-facing **Trip CRUD path is still routed through the globals container.** `ScrambleApp.body` binds `.modelContainer(ModelStore.containers.globals)` (ScrambleApp.swift:118), and `TripListView` reads `@Query(sort: \Trip.startDate)` (TripListView.swift:6) from the environment container — i.e., globals.

Concretely:

- `TripPersistence.create(from:in:)`, called from `TripListView`'s `TripEditorView` sheet, inserts the new `Trip` into the globals context and calls `try modelContext.save()`. The trip is then "shared" via SwiftData's globals-side CloudKit mirror, **not** via the trip's CK zone, until/unless Stage B picks it up.
- `Stage B` does NOT relocate trip records between containers. `ZoneMigrationCoordinator.startOrResume` reads its `trip` from `tripsLocalContext` (ZoneMigrationCoordinator.swift:243) — but new owner-created trips never land in `tripsLocal` at all, so Stage B's `enqueueAll()` walk silently finds nothing to migrate for them. The coordinator's job in the current implementation is to (a) set up `TripZoneState` rows and (b) queue record-uploads via the driver; it does not move bytes between containers.
- The visible cross-device data flow on the participant side is therefore incomplete: the participant's `TripListView` shows trips from globals (their own private CloudKit mirror), so an accepted shared zone's `Trip` record fetched into `tripsLocal` via `TripSyncEngine.apply(fetchedRecords:)` won't appear in their list until the `@Query` on `TripListView` is moved to `tripsLocal`. The `tripsLocalContainer` environment slot exists (`Scramble/Scramble/Persistence/TripsLocalContainerKey.swift`) but no view consumes it yet.

This is the load-bearing gap. The CKSyncEngine plumbing is sound; the `@Model ↔ CKRecord` translators round-trip cleanly; `CloudKitSharingService.acceptShare` correctly inserts shared-zone records into `tripsLocal` via translators. The failure is that the UI's reading view still points at globals, so a participant's app fetches the trip into a store no view is querying.

### `CKSyncEngine.State` corruption-recovery path

`TripSyncEngine.loadStateBlob(for:)` (TripSyncEngine.swift:87) attempts a JSON decode of the persisted state blob; on failure it logs at `modelLogger.error`, calls `stateStore.clearState(for:)`, and returns `nil`. `makeEngine` then constructs the engine with `stateSerialization: nil` and queues an empty `pendingDatabaseChanges` (TripSyncEngine.swift:79) — the design specifies "request a full `fetchChanges()` to reconcile against server truth", but the implementation's empty `pendingDatabaseChanges: []` is best read as a degenerate trigger that prompts the engine to converge through its own scheduling rather than an explicit `fetchChanges()` call. A genuine `engine.fetchChanges()` call would be slightly more aggressive; the chosen path is acceptable because `automaticallySync = true` and the engine will fetch when it next runs its loop.

Note that `CKSyncEngine.State.Serialization` is being persisted by JSON-encoding the value Apple hands the delegate's `stateUpdate` event. The blob is stored via `FileTripSyncStateStore` at `~/Library/Application Support/Scramble/CKSync/{private,shared}.state` and marked `isExcludedFromBackupKey`. If Apple changes the wire format between OS versions, every device's first launch after the change will trip the decode-failure path and converge by re-fetching — survivable but worth flagging.

### `nil` ownership treated as owner

`TripDetailView` computes `isOwnerOfShared = sharingService != nil && !isParticipantOnShared` (TripDetailView.swift:59). When `ownerIdentity(forTrip:)` returns `nil` — i.e., the trip has no `TripZoneState` yet (locally-created, pre-Stage-B, or pre-share-creation) — the view treats the user as an owner for Share-button visibility. This is intentional (Req 5.1: Share button visible to owners) but means a brand-new offline trip exposes a Share affordance whose backing action will lazily insert a `TripZoneState` via `CloudKitSharingService.fetchZoneState(forTrip:)` (CloudKitSharingService.swift:233) and immediately try `privateEngine.state.add(pendingRecordZoneChanges:)`. Without network this becomes a queued operation; with no `Trip` record in `tripsLocal` (because the Trip lives in globals, per the gap above), the queue's record encoder finds nothing to send.

### `nextRecordZoneChangeBatch` re-fetches per ID

`TripSyncEngine.nextRecordZoneChangeBatch` (TripSyncEngine.swift:344) calls `buildRecordsByID(saveIDs:scope:)`, which for each pending ID runs four `FetchDescriptor` lookups (Trip → TripTask → TripPackingItem → TripPersonSnapshot) until one matches (TripSyncEngine.swift:126). For a batch of N changes this is O(4N) queries. Fine for small N; bears revisiting if a single trip's first-time upload churns hundreds of records.

### Trip-deletion path for owners

`CloudKitSharingService.deleteOwnedTrip(forTrip:)` (CloudKitSharingService.swift:107) queues a `deleteZone(zoneID)` via `privateEngine.state.add(pendingDatabaseChanges:)` and clears `pendingUploadFlags` before deleting the `TripZoneState`. The caller in `TripDetailView.deleteTrip()` deletes the `Trip` from the globals container first, then awaits `deleteOwnedTrip`. Because the trip lives in globals, the SwiftData-driven CloudKit mirror handles the actual trip-record deletion; the zone deletion is then "tear down the shoebox we set up for the share". When/if Trip is moved to `tripsLocal`, this ordering will need to invert (delete records via the engine, await zone removal, then drop local rows) and the `cleanupLocalState(forTrip:)` reverse-cascade in CloudKitSharingService.swift:126 becomes the canonical path.

### Echo-guard semantics on multi-record events

`handleFetchedChanges` flags the whole zone event as self-originated only when **every** record ID in the event was just sent by this engine (`zoneRecordIDs.allSatisfy { wasSelfOriginated($0) }`, TripSyncEngine.swift:415). If a `CKSyncEngine` event mixes one of this device's writes with one inbound write from another device, the entire event will be marked non-self and the rules engine will run as if all records were inbound. The risk is at most a benign re-run; the rules engine itself is deterministic and `pinnedByUser` / `userDeletedOnThisTrip` invariants hold. Worth noting because finer-grained per-record echo flagging would require the orchestrator to inspect record IDs rather than the event-level flag.

### "Loading…" vs "Invited participant"

`CloudKitSharingService.makeShareParticipant(_:)` (CloudKitSharingService.swift:181) applies Req 7.1's fallback chain (`displayName → email → "Invited participant"`) **and** Req 7.8's in-flight placeholder. The logic is: if neither name nor email resolves, the row reads `"Loading…"` when `acceptanceStatus == .pending` and `"Invited participant"` otherwise. This is the right read of the requirements: Req 7.1 says "Invited participant" is the terminal fallback when no other identity is known, but Req 7.8 specifically calls out that an *in-flight* fetch shows a placeholder. Putting both behaviours in one factory function keeps `ParticipantsSection` declarative.

---

## Completeness Assessment

Mapping the 13 requirement clusters from `requirements.md` to current implementation status:

### 1. Per-trip share model — **partially implemented**

- `CKShare(recordZoneID:)` is created per trip; deterministic zone naming `trip-<trip.id.uuidString>` is in place (Req 1.1, 1.2, 1.5).
- Owner trip-delete now wires `SharingService.deleteOwnedTrip` (Req 1.4) — the zone-deletion is queued via `privateEngine.state.add(pendingDatabaseChanges:)`.
- **Gap**: Req 1.3 ("trip appears in participant's Trip List") will not be visible until the participant's `TripListView` reads from `tripsLocal`. Records arrive on the participant side via `TripSyncEngine.apply(fetchedRecords:)`, but the @Query reads from globals.

### 2. Schema V3 and persisted person identity — **fully implemented**

`SchemaV3` is shipped (Schema.swift:89) with `TripPersonSnapshot`, `TripZoneState`, `MigrationJournalEntry`. Additive fields on `Trip` / `TripTask` / `TripPackingItem` are present. `SnapshotMaintenance` (Scramble/Scramble/Sharing/SnapshotMaintenance.swift) propagates `Person` edits to snapshots and runs the three cleanup triggers from the design. Reads of person identity through the UI fall back to the snapshot.

### 3. Globals-zone strategy — **fully implemented**

`Person`, `MasterTaskItem`, `MasterPackingItem`, `MigrationJournalEntry` live in `globals` (private CloudKit mirror). Master items are never associated with a `CKShare`. `masterItemID` is stored as a plain UUID (no CK reference). Participant-side `WhyDisclosure` hides when `masterItemID` does not resolve in the participant's globals.

### 4. One-time zone migration — **partially implemented**

- `enqueueAll()` + `runStageB()` flow runs at launch behind `MigrationGate` (Req 4.3, 4.8).
- Journalled state with idempotent resume (`MigrationJournalEntry` + completion correlation, Req 4.6, 4.7).
- Deterministic zone naming + `CKSyncEngine` dedup handles the concurrent-device race (Req 4.9).
- Retry banner on the Trip List exists (`MigrationRetryBanner`).
- **Gap**: Req 4.1 / 4.5 promise that the migration "moves each trip and its trip-owned records … from the default zone into a newly created trip zone … preserving every field". Stage B in the current implementation sets up `TripZoneState` and queues record-uploads via the driver, but it does not relocate the underlying SwiftData rows between `globals` (where Trip CRUD writes them) and `tripsLocal`. Stage B's `expectedRecordNames(for:)` walks `tripsLocalContext` and finds nothing for trips that were created in globals. The CK-default-zone cleanup sweep described in design § "Cleanup of records in CK default zone" is not implemented.

### 5. Share invitation flow — **fully implemented**

`ShareToolbarButton` visible only when `isOwnerOfShared` (Req 5.1). `createShare` returns either the existing share (manage-participants path) or a fresh `CKShare(recordZoneID:)` (Req 5.2, 5.3, 5.5). The `UICloudSharingControllerRepresentable` wraps the system sheet unmodified (Req 5.4). The owner can continue editing while the sheet is open (Req 5.6).

### 6. Share acceptance flow — **partially implemented**

- `AppDelegate.application(_:userDidAcceptCloudKitShareWith:)` routes to `SharingService.acceptShare` (Req 6.1).
- `acceptShare` calls `CKContainer.accept`, then `sharedEngine.fetchChanges()` (Req 6.2 sync path).
- Participant-side Leave Share affordance is wired in `TripDetailView` via the `showLeaveConfirmation` menu and `leaveShare()` (Req 6.5).
- **Gap**: Req 6.2 visible insertion into the participant's Trip List is blocked by the same globals-vs-tripsLocal routing gap noted under cluster 1. Translators write the trip into `tripsLocal`; the Trip List `@Query` reads from globals.

### 7. Participant management surface — **fully implemented**

`ParticipantsSection` lists members with pending/accepted state, tappable on the owner side to open the manage-participants sheet, read-only for participants, visually separate from the trip people roster (Req 7.7). The `"Loading…"` placeholder for in-flight name resolution is in `CloudKitSharingService.makeShareParticipant` (Req 7.8). Refresh triggers via `.task` on view appear (Req 7.6).

### 8. Cross-device race handling and engine ownership — **fully implemented for the engine paths; partially exercised end-to-end**

- LWW via translators preserves field-level resolution (Req 8.1).
- Dangling-reference rule honoured: snapshot is the read path; missing globals `Person` does not crash (Req 8.2).
- Engine ownership gate via `RulesEngineRunner.ownerIdentity` closure (Req 8.3); engine ignores `isSelfOriginated` zoneChanged events (Req 8.6 echo guard).
- Pin / userDeleted / source invariants preserved across translator roundtrip (Req 8.4, 8.7).
- "Rules last evaluated …" subline rendered on participant view via `RulesLastEvaluatedTracker` (Req 8.8).
- **Caveat**: Req 8.5 / 8.6 ("participants edit, owner re-runs engine on receiving change") works end-to-end only once the trip-record routing through `tripsLocal` lands. The engine and orchestrator wiring is in place.

### 9. CloudKit subscriptions — **fully implemented (delegated to CKSyncEngine)**

`CKSyncEngine` manages subscriptions internally (design § "Sharing service"). The app does not register `CKDatabaseSubscription` or `CKRecordZoneSubscription` manually; this supersedes Decision 12. Remote notifications are routed through `AppDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` (AppDelegate.swift:60) to `RemoteNotificationRouter` which dispatches to the matching engine's `fetchChanges()` (Req 9.1, 9.2, 9.3). Failure non-blocking (Req 9.5) — the AppDelegate logs but never blocks user flow.

### 10. Trip ownership identification — **fully implemented**

`SharingService.ownerIdentity(forTrip:)` is synchronous, reads only `TripZoneState`, no I/O (Req 10.4). `TripDetailView` consults it per render. `nil` is treated as owner for new-trip affordances; this is intentional (see Expert section).

### 11. Failure and offline behaviour — **partially implemented**

- Stage B is skipped when `isCloudAvailable()` returns false (`ZoneMigrationCoordinator.runStageB`, Req 11.3 plumbing).
- Sign-out fallback delegates to the Phase 1 local-only `ModelStore` fallback (`makeGlobalsContainer` catch block), so trips remain viewable.
- **Gap**: Req 11.2 ("Network required to share" message) is not present — the `createShare` path will queue the operation rather than surface an offline error. Req 11.4 surfacing of categorised `CKError`s is mostly absorbed by `CKSyncEngine`'s own retry/backoff with `modelLogger.error` calls at the boundaries; no user-visible error banners are wired beyond migration failures.

### 12. Testability of CloudKit-dependent behaviour — **fully implemented**

`SharingService` is an injectable seam (Req 12.1). `FakeSharingService` provides an in-process two-side bus. `EnvironmentProbe`-based wiring routes tests to in-memory containers (Req 12.3). The CKSyncEngine validation harness from task 1 is preserved as the gate commit.

### 13. CloudKit production schema deployment — **fully implemented (as a checklist)**

`docs/release-prep.md` includes the explicit "promote SchemaV3 from Development to Production via the CloudKit Dashboard" checklist item (Req 13.1, 13.2). The actual promotion is a manual step performed against the CloudKit Dashboard before TestFlight cuts.

---

### Summary of state

| Cluster | Status |
|---|---|
| 1. Per-trip share model | Partially implemented (visible flow gated on trip-CRUD routing) |
| 2. Schema V3 + person identity | Fully implemented |
| 3. Globals-zone strategy | Fully implemented |
| 4. One-time zone migration | Partially implemented (Stage B plumbing in place; record relocation not performed) |
| 5. Share invitation flow | Fully implemented |
| 6. Share acceptance flow | Partially implemented (visible flow gated on trip-CRUD routing) |
| 7. Participant management surface | Fully implemented |
| 8. Cross-device races + engine ownership | Fully implemented (end-to-end exercised once cluster-1 routing lands) |
| 9. CloudKit subscriptions | Fully implemented (delegated to CKSyncEngine) |
| 10. Trip ownership identification | Fully implemented |
| 11. Failure and offline behaviour | Partially implemented (offline-share banner missing) |
| 12. Testability | Fully implemented |
| 13. Production schema deployment | Fully implemented (checklist) |

The single highest-leverage follow-up is **moving Trip CRUD onto `tripsLocal`**: the `TripsTab`, `TripListView`, `TripDetailView`, `TripPersistence`, and `TripEditorView` chain currently writes Trip/TripTask/TripPackingItem into the globals container. Once that routing flips (via the existing `\.tripsLocalContainer` environment slot) and Stage B grows a globals → tripsLocal record-relocation step, every cluster currently marked "partial" because of the routing gap (1, 4, 6) collapses to fully implemented.
