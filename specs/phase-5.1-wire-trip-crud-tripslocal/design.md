# Design: Phase 5.1 — Wire Trip CRUD through `tripsLocal`

## Overview

Phase 5.1 routes Trip-domain reads, writes, and migrations through the `tripsLocal` SwiftData container that Phase 5 introduced, replaces the V2-era `Trip.participants → Person` traversals in views with `TripPersonSnapshot` reads, and forwards `TripSyncEngine` events into the `ZoneMigrationCoordinator` so journal entries terminate.

## Architecture

### Container topology after Phase 5.1

```
                 ScrambleApp.body
                 ───────────────────────────────────────
                 │
                 ▼
         MigrationGate (unchanged wrapper)
                 │
                 ▼
              RootView
            ┌──── ─┴─ ────┐
            ▼             ▼
         TripsTab     MasterListsTab
   .modelContainer(tripsLocal)   .modelContainer(globals)
   .environment(\.globalsContainer, globals)
                                  │
                                  ▼
                              PersonEditor (sheet)
                              uses default (globals)
```

The Trips tab subtree binds `.modelContainer(tripsLocal)`; the Master Lists tab subtree binds `.modelContainer(globals)`. Both subtrees can resolve cross-container reads via a new `\.globalsContainer` environment key (and the existing `\.tripsLocalContainer`). PersonEditor presented from `TripEditorView` continues to write Person rows to globals; it presents inside the Trips subtree but explicitly opens a `ModelContext` from `\.globalsContainer` for its writes.

### Save-path chokepoint topology

```
Trip-domain SwiftUI surface ───────────────┐
Rules engine `apply(plan:)` ───────────────┤
TripPersistence.apply / create ────────────┤   (caller invokes mutate-only
PackingSheet delete handler ───────────────┤    SnapshotMaintenance routines
PersonEditor save handler ─────────────────┤    on the same context, then:)
                                           │
                                           ▼
                                  LocalWriteHook.commit(_:)
                                           │
                                           ▼
                                  tripsLocal save +
                                  pendingUploadFlags update +
                                  notifier.notifyPendingChanges(...)

TripDeletion.delete(...) ────► LocalWriteHook.commitDeletion(_:zoneIDsBeingDeleted:)
                                           │
                                           ▼
                                  tripsLocal save (skips flag update for vanishing zones,
                                  partitions mixed-zone records per the concurrency contract) +
                                  notifier.notifyPendingChanges(deleted IDs)
```

`LocalWriteHook` gains a deletion-mode commit (see `LocalWriteHook` changes below) so the entire Trip-domain write surface funnels through one file. The contract test in Req [2.5](requirements.md#2.5) targets this single file. `SnapshotMaintenance` routines are mutate-only after the refactor — they no longer save; the caller is responsible for the single commit through `LocalWriteHook`.

### Stage B relocation step

`ZoneMigrationCoordinator.startOrResume` already creates `TripZoneState`, sets dirty flags, and signals the driver. Phase 5.1 inserts a relocation pre-step that copies trip+dependents from globals to tripsLocal and deletes from globals, using existence in each store as the resume signal (see `ZoneMigrationCoordinator` below). The journal's `MigrationStageState` enum is unchanged; the existing `.stageBInProgress` state covers both relocation and upload sub-phases.

### Engine event multicast

`TripSyncEngine.events` is an `AsyncStream<SyncEngineEvent>` that today is consumed by `RulesEngineTriggerOrchestrator` only. Phase 5.1 needs the same stream consumed by `ZoneMigrationCoordinator`. A small `TripSyncEventBus` owns the single iteration and re-broadcasts to both consumers via a `Continuation`-fan-out.

### Pattern-extension audit (Trip.participants / TripPackingItem.person reads)

Every site that traverses the V2-era relationships from a SwiftUI surface needs to read from `TripPersonSnapshot` instead. The contract test in Req [10.3](requirements.md#10.3) enforces the absence going forward; the table below is the one-time conversion list.

**Lookup patterns.** Two kinds of replacement appear repeatedly:

- For `TripPackingItem`: the V3 schema already provides `item.personSnapshot: TripPersonSnapshot?` as a direct `@Relationship`. Reads are a one-hop traversal that stays inside `tripsLocal`.
- For `TripTask`: there is no direct snapshot relationship; the assignee identity is `task.assigneePersonID: UUID?`. The replacement read is `task.trip?.participantSnapshots?.first { $0.personID == task.assigneePersonID }`. Centralise this as a private helper in `Components/TaskRow.swift` (`func assigneeSnapshot(for task: TripTask) -> TripPersonSnapshot?`) and reuse it in `TaskForm.swift` for the assignee picker.

| Site | Current pattern | New read |
|---|---|---|
| `Features/Trips/TripListView.swift:160` | `trip.participants ?? []` for avatar strip | `trip.participantSnapshots ?? []` |
| `Features/Trips/TripDetailView.swift:254,330` | `trip.participants ?? []` for header + roster | `trip.participantSnapshots ?? []` |
| `Features/Trips/TripDraft.swift:57` | `(trip.participants ?? []).map(\.id)` for editor draft | `(trip.participantSnapshots ?? []).map(\.personID)` |
| `Features/Trips/TripEditorView.swift` | uses globals `Person` directly via `@Query` | unchanged read; write path updates `participantSnapshots` instead of `participants` (see `TripPersistence` below) |
| `Features/Trips/PackingSheet.swift:60` | `Set((trip.participants ?? []).map(\.id))` | `Set((trip.participantSnapshots ?? []).map(\.personID))` |
| `Features/Trips/PackingItemForm.swift` | reads `item.person` (V2 relationship) | `item.personSnapshot` (V3 relationship; already on the schema) |
| `Components/PackingSummarySection.swift:50` | `trip.participants ?? []` for summary rows | `trip.participantSnapshots ?? []` |
| `Components/TaskRow.swift:174` | `task.trip?.participants ?? []` to resolve assignee avatar | `task.trip?.participantSnapshots?.first { $0.personID == task.assigneePersonID }` via the new `assigneeSnapshot(for:)` helper (see "Lookup patterns" above) |
| `Features/Trips/TaskForm.swift:58` | `mode.trip?.participants ?? []` for the assignee picker list | `mode.trip?.participantSnapshots ?? []` rendered as snapshots (the picker selects a `personID`; the form sets `task.assigneePersonID`) |
| `Features/Trips/TripPersistence.swift:65,77` | writes `trip.participants = [Person]` | writes `trip.participantSnapshots` via `TripPersonSnapshot` insert/update/remove (see below) |
| `Features/Trips/TripDetailView.swift:209` (`deleteTrip`) | `modelContext.delete(trip) + save() + sharingService.deleteOwnedTrip` | `TripDeletion.delete(tripID:in:zoneDeleter:)` once |
| `Features/Trips/PackingSheet.swift:310` | direct `modelContext.save()` | `LocalWriteHook.commit(modelContext)` |
| `Features/Trips/TaskForm.swift:145` | direct `modelContext.save()` | `LocalWriteHook.commit(modelContext)` |
| `Features/Trips/PackingItemForm.swift` | direct `modelContext.save()` (twice) | `LocalWriteHook.commit(modelContext)` |
| `Features/Trips/TripListView.swift:100` | direct `modelContext.save()` | `LocalWriteHook.commit(modelContext)` (with `TripZoneState` creation up-front per Req [1.5](requirements.md#1.5)) |
| `Features/Trips/TripDetailView.swift:181` | direct `modelContext.save()` | `LocalWriteHook.commit(modelContext)` |
| `Features/Trips/TripEditorView.swift:309` | direct `modelContext.save()` after `delete(person)` on the tripsLocal-bound context (broken under Phase 5.1's container split) | the line **moves** into `Features/Trips/TripEditorPeoplePicker.swift` (new file, see "Cross-container Trip Editor people picker" below). In its new location the context is `globalsContext` (the picker subtree is re-rooted to `.modelContainer(globals)`). The save remains direct; Person is not Trip-domain. The contract-test scan sees `modelContext.save()` in the picker file and requires the `// LocalWriteHookContract: allow — globals context, not tripsLocal` marker on that line |
| `RulesEngine/Apply.swift:21` | direct `context.save()` (errors throw; `RulesEngineRunner.runForAllNonPastTrips` catches and calls `context.rollback()`) | `LocalWriteHook.commit(context)`. `LocalWriteHook.commit` propagates throws to `apply` which propagates to `RulesEngineRunner.runForAllNonPastTrips`; the rollback semantics are preserved because `LocalWriteHook.commit` performs its mutations inside the same context and `context.rollback()` undoes them too |
| `Sharing/SnapshotMaintenance.swift:55,59,81,98,111` | every routine ends with a direct `context.save()` | refactor every routine to **mutate-only** (no save). The caller (`TripPersistence.apply`, `PackingSheet` delete handler, `RulesEngineTriggerOrchestrator`, `PersonEditor` save handler) calls `LocalWriteHook.commit(context)` once after the routine returns. This collapses each user action to a single commit and removes the manual `flagDirty` helper |
| `Sharing/TripDeletion.swift:66` | direct `context.save()` | `LocalWriteHook.commitDeletion(context, zoneIDsBeingDeleted:)` |
| `Sharing/CloudKitSharingService.swift:46` | `createShare` saves `TripZoneState.shareID` | `LocalWriteHook.commit(context)` (no records mapped → save-only, no notifier signal) |
| `Sharing/CloudKitSharingService.swift:148,169,186` | `deleteOwnedTrip` + `cleanupLocalState` reverse-cascade duplicates of `TripDeletion` | delete the methods; `TripDetailView.deleteTrip` and `CloudKitSharingService.leaveShare` call `TripDeletion.delete(tripID:in:hook:zoneDeleter:)` directly |
| `Sharing/CloudKitSharingService.swift:297` | `fetchZoneState` lazy insert + save | `LocalWriteHook.commit(context)` (TripZoneState insert; same save-only path as line 46) |
| `Components/TaskListSection.swift` | listed for audit completeness — does not traverse V2 relationships in the current source; included in the [10.3](requirements.md#10.3) test scope to prevent future regressions | no change |
| `App/MigrationGate.swift` | currently obtains `migrationCoordinator` from `ScrambleApp.init` and runs `enqueueAll() + runStageB()` in `prepare()` against the coordinator's globals + tripsLocal contexts | no API change; the coordinator's new relocation step runs inside the existing call site. `MigrationGate` itself never touches `ModelStore.shared` for trip-domain reads |
| `App/ScrambleApp.swift:58` | `AppDelegate.environment.globalsContainer = ModelStore.shared` | unchanged (alias for `containers.globals`) — kept so the AppDelegate's share-acceptance path resolves globally; documented because `ModelStore.shared` is now globals-only |
| `App/ScrambleApp.swift:104` | `runColdLaunchEnginePass` uses `ModelStore.shared.mainContext` (globals) | switch to `ModelStore.containers.tripsLocal.mainContext` |
| `RulesEngine/RulesEngineTriggerOrchestrator.swift` | per-event `RulesEngineRunner` constructed against the orchestrator's `tripsLocal` context (the constructor was already wired this way in Phase 5 per `ScrambleApp.makeTriggerOrchestrator`) | confirm and document; no code change beyond the orchestrator's `sweep` call addition |
| `Persistence/UITestSeed.swift` | per-fixture seeding writes Trip-domain entities to one of the two containers it already receives (`globalsContainer`, `tripsLocalContainer`) | fixtures that simulate pre-Phase-5.1 state (`phase5MigrationStates`) seed trips into `globalsContainer`; all other Phase 5.1+ fixtures (including the new TripCRUDPropagation fixture) seed trips into `tripsLocalContainer`. People + master items always seed into `globalsContainer` |

All `Master*Editor` and `MasterListView` files write to globals only; they stay on direct `globals` context saves.

### Concurrency and ordering contracts

These are the non-obvious invariants that hold the design together. Implementers must preserve them; reviewers must verify them at every diff that touches `LocalWriteHook`, `ZoneMigrationCoordinator`, `TripSyncEventBus`, or the sign-in resume path.

- **No engine event can interleave between step 12's two `ModelContext.save()` calls.** The two saves are synchronous `@MainActor` invocations with no `await` between them. Step 13's `driver.saveZone` / `driver.saveRecords` runs only after both saves return. The engine cannot have received the records before step 13 enqueues them, so there is no race window in which an engine event observes a half-completed relocation.
- **Stale engine events from a prior aborted Stage B do not cross-contaminate a resumed run.** Before step 9 re-marks the journal `.stageBInProgress` with `expectedRecordNames`, the coordinator clears `journal.sentRecordNames` and `journal.zoneSaved`. Any engine event that arrives after the resume targeting the same records is treated as the canonical confirmation; events that arrived during the prior aborted run and were never observed are no-ops because their record IDs are still in the (newly re-dirty-flagged) `pendingUploadFlags` set the engine will re-send.
- **`.completed` is a terminal no-op.** `MigrationJournalEntry.state == .completed` is set exactly once: when `handleZoneSaved` and `handleRecordsSaved` together satisfy `isStageBComplete` (zoneSaved && sentRecordNames ⊇ expectedRecordNames). Once set, `enqueueAll` skips the trip and `startOrResume` returns immediately. A sign-out + relocation sequence that completes locally but defers Stage B leaves the journal at `.pending` or `.stageBInProgress`, never at `.completed` with unsynced records.
- **`MigrationJournalEntry` lives in `globals`; its `tripID` is a UUID, not a SwiftData relationship.** Relocation moves the trip out of globals but leaves the journal entry in place. The coordinator's reads cross containers by UUID lookup, never by relationship traversal. Stale journal entries (trip vanished, journal orphaned) are tolerated and surface as `.failed("Trip not found")` per the existing path. Cleanup of historical entries is not a Phase 5.1 deliverable.
- **`LocalWriteHook` is the only writer of `TripZoneState.pendingUploadFlags` from view-layer code paths.** The `ZoneMigrationCoordinator` writes the flags directly during `startOrResume` (step 10) — this is the one production exception. The contract test allowlists `ZoneMigrationCoordinator.swift` alongside `LocalWriteHook.swift` and `TripDeletion.swift` via the marker comment.
- **`commitDeletion` partitions deleted and changed models by their mapped zone before deciding whether to flag-update each.** For models whose mapped zone is in `zoneIDsBeingDeleted`, the per-`TripZoneState` flag update is skipped (the row is vanishing in the same transaction). For models whose mapped zone is *not* in that set — possible when a single context contains a trip deletion and an unrelated edit to a surviving trip — the flag update proceeds exactly as in `commit`. The notifier still receives the deleted record IDs for the vanishing zone so the engine queues `deleteRecord` operations for them.

### Integration points (new and changed)

| Integration | Where it plugs in |
|---|---|
| Trips tab `.modelContainer(tripsLocal)` | `Features/Root/RootView.swift` — wrap the Trips tab's root view |
| Master Lists tab `.modelContainer(globals)` | `Features/Root/RootView.swift` — wrap the Master Lists tab's root view |
| `\.globalsContainer` env key | New: `Persistence/GlobalsContainerKey.swift`, injected in `ScrambleApp.rootContent()` |
| TripsLocal-aware `LocalWriteHook` | Inject the singleton via `\.localWriteHook` env key (new) so every Trips-tab surface calls `hook.commit(modelContext)` without holding a reference to `TripSyncEngine` |
| Engine event fan-out | New: `Sharing/TripSyncEventBus.swift`. Constructed in `ScrambleApp.init`. Subscribed by `RulesEngineTriggerOrchestrator` (existing) and `ZoneMigrationCoordinator` (new) |
| Coordinator ↔ engine signalling | `TripSyncEventBus.subscribeCoordinator(_:)` runs an iteration that calls `coordinator.handleZoneSaved`, `handleRecordsSaved`, `handleRecordsFailed` per event type |
| Person edit → snapshot fan-out | `Features/People/PersonEditor.swift` save handler calls `SnapshotMaintenance.propagatePersonEdit(_:in:ownerIdentity:)` against the tripsLocal context fetched from `\.tripsLocalContainer` — this is the new cross-container side effect |
| Trip roster removal | `Features/Trips/TripPersistence.apply(_:to:in:globals:)` is the sole caller of `SnapshotMaintenance.handleRosterRemoval(tripID:personID:in:)`. The view never invokes the routine directly; the editor's save handler calls `TripPersistence.apply` then `LocalWriteHook.commit(_:)` once |
| Packing-item delete cleanup | `Features/Trips/PackingSheet.swift` delete handler calls `SnapshotMaintenance.handlePackingItemDeletion(_:in:)` (mutate-only, no save) before `context.delete(item)` and `LocalWriteHook.commit(_:)` |
| Post-engine sweep | `RulesEngineTriggerOrchestrator.handle(event:)` invokes `SnapshotMaintenance.sweep(in:)` (mutate-only, no save); the same orchestrator run then invokes the runner whose `apply(plan:)` calls `LocalWriteHook.commit` |
| Cold-launch rules engine | `ScrambleApp.runColdLaunchEnginePass` switches from `ModelStore.shared.mainContext` (globals) to `ModelStore.containers.tripsLocal.mainContext`; `RulesEngineTriggerOrchestrator`'s per-event runs use the same tripsLocal context |
| Network detection for offline-share | `CloudKitSharingService.createShare` adds an `iCloudAvailable()` preflight check; throws a typed `SharingError.networkUnavailable` that the `ShareToolbarButton` catches and renders as a `TransientToast` |
| Sign-in resume | `SignInResumeCoordinator` (new, see below) owned by `ScrambleApp`. Registered in `init` before `MigrationGate.prepare` is awaited. Observes `NSNotification.Name.CKAccountChanged` and `UIScene.didActivateNotification`. Re-runs `migrationCoordinator.enqueueAll() + runStageB()` on each transition through a serial dispatch (single in-flight invocation) |

## Components and Interfaces

### `LocalWriteHook` (changed)

```swift
@MainActor
final class LocalWriteHook {
  init(notifier: PendingChangeNotifier)

  func commit(_ context: ModelContext) throws
  // New — Phase 5.1
  func commitDeletion(
    _ context: ModelContext,
    zoneIDsBeingDeleted: Set<CKRecordZone.ID>
  ) throws
}
```

`commitDeletion` differs from `commit` in two ways: (1) for any record whose mapped zone is in `zoneIDsBeingDeleted`, the per-`TripZoneState` flag update is skipped (the row is in `context.deletedModelsArray` for the same transaction); (2) the notifier is still called with the deleted record IDs so the engine queues `deleteRecord` operations even though the zone itself is also being deleted (this preserves last-writer-wins correctness if a participant receives the record deletions before the zone deletion).

Mixed-zone partition contract (per the concurrency-contracts section): `commitDeletion` partitions deleted and changed models by mapped zone. Records mapped to a zone NOT in `zoneIDsBeingDeleted` (the "surviving zone in the same transaction" case, e.g. a snapshot edit on one trip in the same context as a delete of another trip) follow the `commit` path: per-`TripZoneState` flag update + notifier signal. Records mapped to a zone IN the set follow the deletion path: skip flag update, still notify deleted record IDs. Models whose `mapping(for:)` returns `nil` (today: `TripZoneState` itself) are invisible to both flag update and notifier, as in `commit`. A unit test exercises this exact mixed-input shape including the `nil`-mapped row case.

The current `mapping(for:)` returns `nil` for `TripZoneState` so its own deletion is invisible to the notifier — desired.

### `TripDeletion` (changed)

```swift
@MainActor
enum TripDeletion {
  static func delete(
    tripID: UUID,
    in context: ModelContext,
    hook: LocalWriteHook,
    zoneDeleter: TripZoneDeleter? = nil
  ) throws
}
```

Implementation: stage the deletions in the context (records first, `TripZoneState` last), compute the set of zone IDs being deleted from the fetched `TripZoneState` rows, then call `hook.commitDeletion(context, zoneIDsBeingDeleted:)`. Owner-side: enqueue `deleteZone` on the driver after the commit returns. Participant-side passes `zoneDeleter: nil` as today.

### `\.localWriteHook` env key (new)

`Persistence/LocalWriteHookEnvironmentKey.swift`. Default value is a `fatalError`-only stub for previews; production injects the real hook from `ScrambleApp.rootContent()`. Trip-domain views read it via `@Environment(\.localWriteHook) private var hook` and call `try hook.commit(modelContext)` in place of `try modelContext.save()`.

### `\.globalsContainer` env key (new)

`Persistence/GlobalsContainerKey.swift`. Mirrors `TripsLocalContainerKey`: `var globalsContainer: ModelContainer`, default value is `ModelStore.containers.globals`. Injected at `ScrambleApp.rootContent()`.

### Cross-container Trip Editor people picker (new view extraction)

`@Query` does not cross containers: a view rooted in `.modelContainer(tripsLocal)` and declaring `@Query var allPeople: [Person]` resolves against tripsLocal, where `Person` rows do not live. The Trip Editor's people picker (currently inline in `TripEditorView` with the inline `+ Add person` sheet) is extracted into a child view re-rooted to the globals container:

```swift
// Features/Trips/TripEditorPeoplePicker.swift (new)
struct TripEditorPeoplePicker: View {
  @Binding var participantIDs: [UUID]
  @Environment(\.globalsContainer) private var globals

  var body: some View {
    PickerContent(participantIDs: $participantIDs)
      .modelContainer(globals)   // re-roots `@Query` for this subtree
  }
}

private struct PickerContent: View {
  @Binding var participantIDs: [UUID]
  @Environment(\.modelContext) private var globalsContext // == globals.mainContext here
  @Query(sort: \Person.name) private var allPeople: [Person]
  // body, inline `+ Add person` sheet presenting PersonEditor — all writes
  // go to `globalsContext`, never to tripsLocal.
}
```

The picker subtree therefore reads via `@Query` and writes via the globals `modelContext`, reactively. `@Query` in `PickerContent` binds to globals because the immediately-enclosing `.modelContainer` modifier wins for the subtree — iOS 26 SwiftUI honours the innermost container declaration, and nesting `.modelContainer(globals)` inside an outer `.modelContainer(tripsLocal)` is the supported pattern for cross-container reads inside a re-rooted child view. The parent `TripEditorView` stays on tripsLocal for trip-attribute reads and the final `TripPersistence.apply` save. The inline `PersonEditor` sheet presented from the picker inherits the picker's `.modelContainer(globals)` so its `@Environment(\.modelContext)` resolves to globals — no separate context plumbing needed.

`TripEditorView`'s existing Person-delete line (`Features/Trips/TripEditorView.swift:309`) moves into `PickerContent`: it deletes the `Person` from the globals context via the picker's `modelContext`. The audit-table row that left this site on a direct save is updated accordingly: the save is still direct (globals doesn't need the chokepoint), but the call site moves out of `TripEditorView` and the contract-test scan picks it up correctly in its new location (still allowed because the receiver is globals, not tripsLocal).

### `ZoneMigrationCoordinator` (changed)

`startOrResume(_ journal:)` becomes:

```
1.  tripID := journal.tripID
2.  if journal.state == .completed { return }    // terminal no-op
3.  zoneID := canonical zone ID for tripID
4.  tripInTripsLocal := fetch(Trip, tripID, in: tripsLocalContext)
5.  tripInGlobals := fetch(Trip, tripID, in: globalsContext)
6.  switch (tripInTripsLocal, tripInGlobals) {
      case (some, some):     // insert step done, delete step pending
        deleteFromGlobals(tripID)
        fallthrough to step 8
      case (some, none):     // relocation complete; continue with upload
        fallthrough to step 8
      case (none, some):     // not yet relocated
        try relocateToTripsLocal(tripID)
        deleteFromGlobals(tripID)
        fallthrough to step 8
      case (none, none):     // trip vanished
        mark journal .failed("Trip not found"); return
    }
7.
8.  ensureZoneState(tripID, zoneID)
9.  expectedNames := computeExpected(tripInTripsLocal)
10. clear journal.sentRecordNames and journal.zoneSaved   // reset stale sub-state per concurrency contract
11. mark journal .stageBInProgress with expectedNames
12. dirty-flag every expectedName in TripZoneState.pendingUploadFlags
13. retroactively dirty-flag any existing TripPersonSnapshot rows for the trip (Req 4.9)
14. tripsLocalContext.save() ; globalsContext.save()      // sequential @MainActor, no engine event can interleave
15. driver.saveZone(zoneID) ; driver.saveRecords(recordIDs)
```

The cross-container relocation (`relocateToTripsLocal`) reads from globals, constructs equivalent rows in tripsLocal preserving all persisted fields (Req [4.2](requirements.md#4.2)), commits tripsLocal, and only then deletes from globals (Req [4.3](requirements.md#4.3)). The split commit + existence-as-journal makes Req [4.5](requirements.md#4.5)'s per-state branching fall out from step 6 above.

Per-container `ModelContext.save()` is atomic in isolation; the cross-container operation derives its correctness from committing `tripsLocal` before `globals`. The resume invariant lives in container contents, not in a journal field — any contributor changing the relocation order must update both the step order in step 14 and the branch logic in step 6 together.

Step 10's `journal.sentRecordNames` / `journal.zoneSaved` clear is a mutation on the `MigrationJournalEntry` row in `globals`, durable only after step 14's `globalsContext.save()` returns. A crash between steps 10 and 14 leaves the journal at its prior on-disk state — which is the desired resume-from-zero behaviour because the on-disk `sentRecordNames` still describe the prior aborted run, and the next call to `startOrResume` will run step 10 again before re-marking `.stageBInProgress`. The clear is therefore both safe-on-crash and necessary on the happy path.

`enqueueAll()` (current implementation fetches trips from `tripsLocalContext`) now fetches from both stores to discover trips that still live in globals — these need journals. Existing trips with `TripZoneState` in tripsLocal are still treated as already-migrated.

### `TripSyncEventBus` (new)

```swift
@MainActor
final class TripSyncEventBus {
  init(events: AsyncStream<SyncEngineEvent>)

  func subscribeOrchestrator(_ orchestrator: RulesEngineTriggerOrchestrator)
  func subscribeCoordinator(_ coordinator: ZoneMigrationCoordinator)
  func start()
}
```

`start()` launches a single `Task` that iterates `events` and dispatches to every registered subscriber. `ScrambleApp.prepareLaunch` registers both subscribers before calling `start()`; the engine's `start()` is called only after `bus.start()` returns.

**Lifecycle contracts:**
- **Registration before `start()`.** Both `subscribe*` methods record their handler. Calling either after `start()` in a non-DEBUG build logs `modelLogger.fault` and returns (the late subscriber is silently rejected); in DEBUG builds it traps via `assertionFailure` so previews and tests can never silently miss events. Production has only two known subscribers (orchestrator + coordinator), both registered in `ScrambleApp.init` — late registration is not expected to occur.
- **No buffering.** The bus does not retain events across `start()`. The engine's `events` stream is empty at the moment `start()` returns because the engine hasn't been started yet; events begin flowing only after `syncEngine.start()` (which runs after `bus.start()`). This ordering eliminates the "events emitted before subscribers attached" problem at the cost of preventing late subscribers (acceptable per above).
- **Subscriber-failure isolation.** Each dispatch is wrapped: `do { handler(event) } catch { modelLogger.error(…) }`. A throwing or trapping handler logs and the bus iteration continues; the other subscriber still receives the event. (Handlers are synchronous main-actor calls; they do not `await`. Long-running work inside a handler must be dispatched to its own `Task` by the subscriber, not awaited inside the dispatch.)
- **Cancellation.** The bus's iteration task is cancelled when `ScrambleApp` deinits (effectively never in production). Tests cancel explicitly via a `stop()` test-only method.

Coordinator dispatch (event-name sketches; actual case names live in `TripSyncEngine.SyncEngineEvent`):
- `.zoneSaved(zoneID)` → `coordinator.handleZoneSaved(zoneID)`
- `.recordsSaved(recordIDs)` → `coordinator.handleRecordsSaved(recordIDs)`
- `.recordsFailed(recordIDs, error)` → `coordinator.handleRecordsFailed(recordIDs, error: error)`

### `TripPersistence` (changed)

```swift
@MainActor enum TripPersistence {
  static func create(from draft: TripDraft, in tripsLocal: ModelContext, globals: ModelContext) -> (Trip, [UUID])
  static func apply(_ draft: TripDraft, to trip: Trip, in tripsLocal: ModelContext, globals: ModelContext) -> [UUID]
}
```

Both functions:
1. Resolve `draft.participantIDs` against the `globals` context to obtain name + colourKey per ID. IDs that don't resolve are returned as orphan IDs (existing semantics).
2. Diff the resolved IDs against `trip.participantSnapshots` (current state on the trip):
   - new IDs → insert `TripPersonSnapshot(personID:..., name:..., colourID:..., initialSource:"name", isRosterMember:true, trip:trip)`
   - removed IDs → call `SnapshotMaintenance.handleRosterRemoval(tripID:personID:in:tripsLocal)` (the routine handles the "delete if no referrers, else flip isRosterMember=false" rule)
   - kept IDs → update name + colourID on the existing snapshot in place
3. Leave `trip.participants` empty; do not write to it.

`create` additionally creates the `TripZoneState` row for the new trip (Req [1.5](requirements.md#1.5)) before the caller calls `LocalWriteHook.commit(_:)` — the hook would create one too, but doing it up-front keeps the `TripZoneState` initialised before any other field is touched, simplifying the test for "TripZoneState exists after new-trip commit returns."

The orphan-ID return value (Req from Phase 5 Decision 15) is preserved; the toast already exists in the caller views.

### `CloudKitSharingService.createShare` (changed)

```swift
func createShare(forTrip tripID: UUID) async throws -> CKShare {
  guard try await iCloudAvailable() else {
    throw SharingError.networkUnavailable
  }
  // existing share-creation path
}
```

`SharingError.networkUnavailable` is a new case; `ShareToolbarButton` catches it and renders the toast "Network required to share". Existing `SharingError` cases retain their semantics.

`iCloudAvailable()` checks `CKContainer.accountStatus()` first and the `NWPathMonitor` second; both must be available. The check is fast (cached account status, single network probe) and not a long-poll.

### Cross-container Person lookup helper (new)

`Features/Trips/PersonLookup.swift`:

```swift
@MainActor
enum PersonLookup {
  static func person(for id: UUID, in globals: ModelContext) -> Person?
}
```

Used by `TripEditorView`'s people picker and any future site that needs the live `Person` row. Views that just need name/colour read from `TripPersonSnapshot`; this helper exists only for the picker (which still selects from the live Person registry) and for unit tests.

`SnapshotMaintenance` routines invoked during a save handler (TripEditorView roster removal, PersonEditor save → `propagatePersonEdit`) run synchronously on the main actor before `LocalWriteHook.commit(_:)` returns. The editor's subsequent reads from `TripPersonSnapshot` therefore see consistent post-mutation state — no in-flight inconsistency is observable from the people picker.

### `SignInResumeCoordinator` (new)

`App/SignInResumeCoordinator.swift`. Owned by `ScrambleApp` for the app's lifetime. Constructed and registered in `ScrambleApp.init` before `MigrationGate.prepare` is awaited so an account-becomes-available transition during the splash is observed.

```swift
@MainActor
final class SignInResumeCoordinator {
  init(migrationCoordinator: ZoneMigrationCoordinator, container: CKContainer)

  /// Register notification observers and perform an immediate
  /// `accountStatus()` re-check (handles "account became available
  /// before observer installed"). Idempotent.
  func start()

  /// Used by tests to drive the resume path without real notifications.
  func runResumeIfNeeded() async
}
```

Observed signals (any one fires `runResumeIfNeeded`):
- `NSNotification.Name.CKAccountChanged` (the primary signal).
- `UIScene.didActivateNotification` (fallback for the documented case where `CKAccountChanged` is coalesced or missed during a background → foreground transition).

`runResumeIfNeeded` is serialised via a single in-flight `Task` reference — if a run is already underway, the next signal sets a pending-bit; the in-flight run loops once more when it finishes. This collapses storm-fire scenarios (e.g., flaky network during account flip) to at most one trailing replay.

Inside the run: `if migrationCoordinator.isCloudAvailable() { try migrationCoordinator.enqueueAll(); try migrationCoordinator.runStageB() }`. The coordinator's existing journal-state-machine handles per-trip idempotence; `.completed` entries short-circuit.

Race with `MigrationGate.prepare`: both paths invoke the same `SignInResumeCoordinator.runResumeIfNeeded` rather than calling `migrationCoordinator.enqueueAll() + runStageB()` directly. `MigrationGate.prepare` awaits the coordinator's `runResumeIfNeeded()`; subsequent `CKAccountChanged` / `UIScene.didActivateNotification` signals route through the same method. The coordinator owns a single `inFlight: Task<Void, Never>?` plus a `pendingReplay: Bool` flag (both `@MainActor`). New invocations either start the task (when nil) or set `pendingReplay = true` (when non-nil); the in-flight task checks and consumes the flag in a tail loop before clearing `inFlight`. This collapses gate-startup, account-changed, and scene-activated triggers into one serial pipeline with at most one trailing replay — no `@MainActor`-reentrancy hand-wave required.

## Data Models

No schema changes. The V2-era relationships `Trip.participants → Person` and `TripPackingItem.person → Person` persist in `SchemaV3` but become latent (constraint [C3](requirements.md#C3)). The persistence note's existing warning ("must maintain both sides on writes") becomes moot because we stop writing to them.

`MigrationJournalEntry` is unchanged. Resume branching uses existence-in-store as the journal signal (see `ZoneMigrationCoordinator` above), keeping the journal contract identical to Phase 5. Entries accumulate over time (each migration leaves one `.completed` row in `globals`); cleanup of historical journal entries is acknowledged as a known non-goal for Phase 5.1. Back-stop: if any installed device's journal row count exceeds 100 (well above any plausible legitimate count), a follow-up issue SHALL be filed; the threshold is tracked manually until steady-state is observed. A logged warning in `MigrationGate.prepare()` surfaces the count when it crosses the threshold so the back-stop is observable without instrumentation.

## Error Handling

| Failure | Current behaviour | Phase 5.1 behaviour |
|---|---|---|
| `LocalWriteHook.commit` throws | propagated to caller; SwiftUI shows toast or rolls back | unchanged |
| `LocalWriteHook.commitDeletion` throws | n/a (new) | TripDeletion propagates; caller shows toast and does not request zone deletion |
| Relocation: `tripsLocal.save` throws | n/a | rollback tripsLocal, leave journal `.pending`, log; retry on next launch |
| Relocation: `globals.save` (delete step) throws | n/a | journal stays `.stageBInProgress` (tripsLocal has the row, globals still has it); resume on next launch deletes from globals only |
| `globals` orphan record after relocation kill | unlikely | resume re-runs the delete; idempotent (delete-missing is no-op) |
| CloudKit zone deletion fails after local delete | currently swallowed in `TripDetailView.deleteTrip` catch | banner per Req [5.5](requirements.md#5.5), retry on next `CKSyncEngine` cycle |
| Account-not-available during `createShare` | silent failure | `SharingError.networkUnavailable` → toast (Req [8](requirements.md#8-sharing-surfaces-fail-visibly-when-offline)) |
| Sign-in transition during running app | not observed | re-run Stage B for backlog (Req [4.8](requirements.md#4.8)) |
| Engine event arrives while coordinator handling its own save | possible race | impossible by sequencing: step 14's saves are synchronous `@MainActor` calls with no `await`; step 15 enqueues to driver only after both saves return; engine event handlers run on the same actor and queue after step 15 returns |
| Resumed Stage B observes engine events targeting records from a prior aborted run | new (cross-run contamination) | step 10 clears `journal.sentRecordNames` and `journal.zoneSaved` before the resume re-marks the journal `.stageBInProgress`; events that arrive after the reset are treated as canonical, events from the prior aborted run are no-ops because the records have been re-dirty-flagged and will be re-sent |
| `CKAccountChanged` not delivered (coalesced during launch / foreground transition) | new gap | `SignInResumeCoordinator` also observes `UIScene.didActivateNotification` as a fallback and performs an immediate `CKContainer.accountStatus()` re-check on `start()` |
| `CKAccountChanged` storm during a flaky network | new (sign-in resume observer) | `SignInResumeCoordinator` serialises invocations via a single in-flight Task; storm-fire collapses to at most one trailing replay; `isCloudAvailable()` guard inside the run absorbs no-ops |
| Participant-side `leaveShare` finds the shared zone already deleted on the server | new edge case | `CloudKitSharingService.leaveShare` ignores "zone not found" from `deleteRecordZone` and proceeds with local cleanup via `TripDeletion.delete(tripID:in:hook:zoneDeleter:nil)` so the participant's `tripsLocal` ends in the expected post-leave state regardless of remote state |
| MigrationJournalEntry orphan (trip vanished, journal points at nothing) | tolerated since Phase 5 | step 6 `(none, none)` branch marks the entry `.failed("Trip not found")`; banner surfaces it; orphan-cleanup automation is non-goaled |

## Testing Strategy

### Unit tests (`ScrambleTests`)

| Suite | Coverage |
|---|---|
| `LocalWriteHookTests` (extended) | `commitDeletion` skips flag update for `zoneIDsBeingDeleted` rows; notifier still receives deleted IDs; mixed-zone partition: a single context with (a) a deletion in a vanishing zone and (b) an edit in a surviving zone produces correct flags + notifier signals for both per the contract |
| `TripDeletionTests` (extended) | Routes through `LocalWriteHook.commitDeletion`; owner-scope calls zone deleter; participant-scope does not; idempotent against missing trip |
| `ZoneMigrationCoordinatorTests` (extended) | New cases per (tripsLocal, globals) existence quadrant; relocation preserves all persisted fields (Req [4.2](requirements.md#4.2)); Stage A snapshots get retroactively dirty-flagged on Stage B entry (Req [4.9](requirements.md#4.9)); sign-in trigger re-runs Stage B for deferred entries |
| `TripPersistenceTests` (new) | `create` and `apply` produce expected `TripPersonSnapshot` diffs (add/remove/update) and do not write `trip.participants`; orphan IDs returned for unresolved input |
| `TripSyncEventBusTests` (new) | Single iteration multicasts to both subscribers; orchestrator and coordinator each receive every event; subscriber failure (throw / trap caught) does not cancel the bus or starve the other subscriber; late-subscriber registration triggers `preconditionFailure` |
| `SignInResumeCoordinatorTests` (new) | `start()`'s immediate `accountStatus()` re-check triggers `runResumeIfNeeded` when account is available; `CKAccountChanged` notification triggers a run; `UIScene.didActivateNotification` fallback also triggers a run; concurrent triggers collapse to a single trailing replay; `isCloudAvailable() == false` short-circuits |
| `CloudKitSharingServiceTests` (extended) | `createShare` throws `SharingError.networkUnavailable` when account-status check fails |
| `SnapshotMaintenanceTests` (extended) | Each routine is now mutate-only; the test commits via `LocalWriteHook.commit` and asserts the notifier sees the expected dirty/deleted records; cross-container `propagatePersonEdit` from PersonEditor save handler updates snapshots in tripsLocal even though the editor's own writes go to globals |
| `TripPersistenceTests` (new) — extension | `apply` is the sole caller of `SnapshotMaintenance.handleRosterRemoval`; the test asserts a single commit per editor save by injecting a recording `PendingChangeNotifier` and counting notifications |
| `LocalWriteHookContractTest` (new) | Source-pattern scan of `Scramble/Scramble/**/*.swift` excluding `LocalWriteHook.swift`, `TripDeletion.swift`, and `ZoneMigrationCoordinator.swift`; fails on `modelContext.save()` or `context.save()` patterns; honours `// LocalWriteHookContract: allow` escape on the offending line (escape needed for `TripEditorPeoplePicker.swift` because its `modelContext` binds to globals, not tripsLocal) |
| `V2RelationshipUseTest` (new) | SwiftSyntax parse of the trip-domain file set; fails on `.participants` member access on a `Trip` receiver or `.person` on a `TripPackingItem` receiver; honours `// V2Relationship: allow` escape. Swift-syntax is added as a `swift-syntax` SwiftPM dependency on the test target only, pinned to `from: "601.0.0"` (the 6.x line that matches the Swift 6 toolchain shipped with Xcode 26). On toolchain bump, the package version is bumped in lockstep; the upgrade ritual is documented as a one-line `Package.swift` edit in the tasks document |

### Property-based tests

Two Phase 5.1 invariants are universal guarantees worth PBT coverage (idempotence is a special case of the first and not separated):

1. **Cross-store consistency boundary ([C2](requirements.md#C2)) and idempotence ([Req 4.6](requirements.md#4.6))**: for any sequence of relocation interruption points AND any number of subsequent `runStageB()` invocations, the terminal state is one of (a) the trip in globals only, (b) the trip in tripsLocal only — never both, never neither. Parameterise interruption-point ∈ {fresh, after-step-10-clear (new code path; most regression-prone), after-tripsLocal-save (step 14a), after-globals-delete (step 14b), after-completion} × resume-count ∈ {1, 2, 5}. The "after-completion" × N ≥ 1 case covers idempotence subsumed from the prior PBT property #2.

2. **`PendingUploadFlags` correctness under `commitDeletion` mixed-zone partition**: for any combination of `(zoneIDsBeingDeleted, recordsBeingDeleted_in_vanishing_zone, recordsBeingDeleted_in_surviving_zone, recordsBeingChanged_in_surviving_zone)`, the resulting flag state on surviving `TripZoneState` rows is exactly the dirty/deleted set computed from records mapped to surviving zones, and the notifier received the union of all deleted IDs across both vanishing and surviving zones. The case where a single context holds a vanishing-zone deletion plus a surviving-zone edit must produce notifier signals for both.

PBT framework: Swift Testing's built-in `arguments:` parameterisation (existing project pattern per `ZoneMigrationCoordinatorTests`); no external dependency.

### UI tests (`ScrambleUITests`)

| Suite | Coverage |
|---|---|
| `TripCRUDPropagationUITests` (new) | UITestSeed populates a trip in globals + master lists; launch the app; verify trip appears in Trip List; edit trip name; verify name persists across relaunch; verify a fake `SharingService` records the corresponding upload events |
| `TripDeletionUITests` (new) | Delete a trip from Trip Detail; verify it disappears from Trip List immediately; verify the fake `TripZoneDeleter` recorded the zone-delete request |
| `OfflineShareUITests` (new) | With network preflight stubbed to unavailable, tap Share; verify the "Network required to share" toast appears and no share is created |
| `MigrationGateUITests` (existing) | Adjust UITestSeed to seed pre-Phase-5.1 trips in globals; verify Stage A + Stage B + relocation completes and the trips appear in the Trip List interactable |

### Manual test plan

`specs/phase-5-cloudkit-sharing/manual-test-plan.md` is created as part of this phase (per Req [10.4 in the prior draft](decision_log.md#decision-5-documentation-and-deliverables-are-tracked-in-the-tasks-document-not-requirements), now tracked as a deliverable in tasks). The manual plan covers two-device share lifecycle, offline-share affordance, owner-delete-while-participant-online, and the iCloud-account-transition resume case — the cases real CloudKit infrastructure validates and the in-process test suites cannot.
