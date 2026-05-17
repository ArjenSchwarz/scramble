---
references:
    - specs/phase-5.1-wire-trip-crud-tripslocal/requirements.md
    - specs/phase-5.1-wire-trip-crud-tripslocal/design.md
    - specs/phase-5.1-wire-trip-crud-tripslocal/decision_log.md
---
# Phase 5.1 — Wire Trip CRUD through tripsLocal

## Phase 1: Foundation — container topology and env keys

- [x] 1. [config] Add \.globalsContainer SwiftUI environment key <!-- id:ki2e5mt -->
  - File: Scramble/Scramble/Persistence/GlobalsContainerKey.swift
  - Mirror the existing TripsLocalContainerKey shape; default value ModelStore.containers.globals
  - Stream: 1
  - Requirements: [9.1](requirements.md#9.1), [9.2](requirements.md#9.2)
  - References: design.md § Cross-container Trip Editor people picker

- [x] 2. [config] Add \.localWriteHook SwiftUI environment key <!-- id:ki2e5mu -->
  - File: Scramble/Scramble/Persistence/LocalWriteHookEnvironmentKey.swift
  - Default value is a fatal-error stub for previews; production injection happens in ScrambleApp.rootContent()
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1)
  - References: design.md § Integration points

- [x] 3. [wire] Wire RootView to bind subtrees to their containers and switch cold-launch engine pass to tripsLocal <!-- id:ki2e5mv -->
  - File: Scramble/Scramble/Features/Root/RootView.swift
  - Wrap the Trips-tab subtree in .modelContainer(tripsLocal); wrap the Master-Lists-tab subtree in .modelContainer(globals)
  - Inject \.globalsContainer and \.localWriteHook in ScrambleApp.rootContent() so both flow through the entire tree
  - Cold-launch engine pass in ScrambleApp.runColdLaunchEnginePass switches its RulesEngineRunner context from ModelStore.shared.mainContext (globals) to ModelStore.containers.tripsLocal.mainContext
  - Stream: 1
  - Requirements: [1.5](requirements.md#1.5)
  - References: design.md § Container topology after Phase 5.1, Integration points

- [x] 4. [test] Write tests for PersonLookup.person(for:in:) helper <!-- id:ki2e5mw -->
  - File: ScrambleTests/Features/Trips/PersonLookupTests.swift
  - Cover: resolution against an in-memory globals container; nil for missing UUID; no side effects on the context
  - Stream: 1
  - Requirements: [10.1](requirements.md#10.1)
  - References: design.md § Cross-container Person lookup helper

- [x] 5. [impl] Implement Features/Trips/PersonLookup.swift <!-- id:ki2e5mx -->
  - File: Scramble/Scramble/Features/Trips/PersonLookup.swift
  - One-shot UUID lookup against a supplied globals ModelContext; main-actor; no observation
  - Blocked-by: ki2e5mw ([test] Write tests for PersonLookup.person(for:in:) helper)
  - Stream: 1
  - Requirements: [10.1](requirements.md#10.1)

## Phase 2: Chokepoint extension — LocalWriteHook + SnapshotMaintenance + TripDeletion

- [x] 6. [test] Extend LocalWriteHookTests for commitDeletion mixed-zone partition <!-- id:ki2e5my -->
  - File: ScrambleTests/Sharing/LocalWriteHookTests.swift
  - Cover per the design mixed-zone partition contract: (a) deletion in vanishing zone Z1 + edit in surviving zone Z2 produces notifier-deleted-from-Z1 and dirty-in-Z2; surviving zone state pendingUploadFlags carries Z2 dirty name only; (b) nil-mapping rows (e.g., TripZoneState in deletedModelsArray) are invisible to both flag update and notifier; (c) all records mapped to a vanishing zone produce notifier signals but no flag write
  - Stream: 1
  - Requirements: [2.4](requirements.md#2.4)
  - References: design.md § LocalWriteHook (changed), § Concurrency and ordering contracts

- [x] 7. [impl] Implement LocalWriteHook.commitDeletion(_:zoneIDsBeingDeleted:) <!-- id:ki2e5mz -->
  - File: Scramble/Scramble/Sharing/LocalWriteHook.swift
  - Partition mapped records by zoneIDsBeingDeleted set membership; surviving-zone records follow the existing commit path; vanishing-zone records skip flag update but still signal the notifier with deleted IDs
  - Blocked-by: ki2e5my ([test] Extend LocalWriteHookTests for commitDeletion mixed-zone partition)
  - Stream: 1
  - Requirements: [2.4](requirements.md#2.4)

- [x] 8. [test] Update SnapshotMaintenanceTests for mutate-only routines <!-- id:ki2e5n0 -->
  - File: ScrambleTests/Sharing/SnapshotMaintenanceTests.swift
  - Each test now drives the routine, then commits via LocalWriteHook.commit, and asserts the recording notifier observed the expected dirty/deleted record IDs; existing behavioural assertions (propagation fan-out, roster removal, packing-item cleanup, sweep) retained
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [2.3](requirements.md#2.3)
  - References: design.md § Save-path chokepoint topology, audit-table row for SnapshotMaintenance.swift

- [x] 9. [impl] Refactor SnapshotMaintenance routines to mutate-only <!-- id:ki2e5n1 -->
  - File: Scramble/Scramble/Sharing/SnapshotMaintenance.swift
  - Drop every context.save() call (lines 55, 59, 81, 98, 111); delete the manual flagDirty helper (LocalWriteHook now handles dirty marking); update docs to state caller is responsible for committing via LocalWriteHook.commit
  - Blocked-by: ki2e5mz ([impl] Implement LocalWriteHook.commitDeletion(_:zoneIDsBeingDeleted:)), ki2e5n0 ([test] Update SnapshotMaintenanceTests for mutate-only routines)
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)

- [x] 10. [test] Extend TripDeletionTests for commitDeletion routing <!-- id:ki2e5n2 -->
  - File: ScrambleTests/Sharing/TripDeletionTests.swift
  - Assert TripDeletion.delete invokes LocalWriteHook.commitDeletion once with the correct zoneIDsBeingDeleted set; owner-scope still enqueues deleteZone; participant-scope does not; idempotent against missing trip; the recording notifier observed the expected deleted record IDs
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3)
  - References: design.md § TripDeletion (changed)

- [x] 11. [impl] Refactor TripDeletion.delete to route through LocalWriteHook.commitDeletion <!-- id:ki2e5n3 -->
  - File: Scramble/Scramble/Sharing/TripDeletion.swift
  - New signature: delete(tripID:in:hook:zoneDeleter:); collect zoneIDsBeingDeleted from the fetched TripZoneState rows; stage the reverse-cascade deletions in the context; call hook.commitDeletion(context, zoneIDsBeingDeleted:); owner-scope post-commit enqueues deleteZone
  - Blocked-by: ki2e5mz ([impl] Implement LocalWriteHook.commitDeletion(_:zoneIDsBeingDeleted:)), ki2e5n2 ([test] Extend TripDeletionTests for commitDeletion routing)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [2.4](requirements.md#2.4)

## Phase 3: Read-path conversion — V2 reads → snapshots; people picker re-rooting

- [x] 12. [test] Write tests for assigneeSnapshot(for:) helper <!-- id:ki2e5n4 -->
  - File: ScrambleTests/Components/TaskRowAssigneeTests.swift (new)
  - Cover: returns the snapshot whose personID == task.assigneePersonID; nil when no match; nil when task.assigneePersonID is nil; nil when trip has no snapshots
  - Stream: 1
  - Requirements: [10.1](requirements.md#10.1)
  - References: design.md § Pattern-extension audit / Lookup patterns

- [x] 13. [impl] Add assigneeSnapshot(for:) helper in Components/TaskRow.swift and apply in Features/Trips/TaskForm.swift <!-- id:ki2e5n5 -->
  - Helper: func assigneeSnapshot(for task: TripTask) -> TripPersonSnapshot? doing the participantSnapshots.first { $0.personID == task.assigneePersonID } lookup
  - Replace task.trip?.participants ?? [] (TaskRow.swift:174) with the helper-driven avatar render
  - Replace mode.trip?.participants ?? [] (TaskForm.swift:58) with mode.trip?.participantSnapshots ?? []; the picker selects a personID and the form sets task.assigneePersonID
  - Blocked-by: ki2e5n4 ([test] Write tests for assigneeSnapshot(for:) helper)
  - Stream: 1
  - Requirements: [10.1](requirements.md#10.1)

- [x] 14. [test] Write tests for TripPersistence snapshot-diff behaviour <!-- id:ki2e5n6 -->
  - File: ScrambleTests/Features/Trips/TripPersistenceTests.swift (new)
  - Cover: create and apply produce expected TripPersonSnapshot insert/update/remove diffs against the trip current participantSnapshots; trip.participants is NOT written (asserted by reading the V2 relationship and confirming it is empty); orphan IDs (Person not found in globals) are returned in missingIDs; the call invokes SnapshotMaintenance.handleRosterRemoval exactly once per removed personID (sole-caller invariant); a single LocalWriteHook.commit after the call produces exactly one notifier call summarising the editor save
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.5](requirements.md#1.5), [2.1](requirements.md#2.1), [6.2](requirements.md#6.2)
  - References: design.md § TripPersistence (changed)

- [x] 15. [impl] Rewrite TripPersistence.create / apply to operate on TripPersonSnapshot <!-- id:ki2e5n7 -->
  - File: Scramble/Scramble/Features/Trips/TripPersistence.swift
  - New signatures: create(from:in:globals:) and apply(_:to:in:globals:); resolve draft.participantIDs against the globals context to obtain name + colourKey per ID; diff against trip.participantSnapshots and (a) insert new TripPersonSnapshot(personID:..., name:..., colourID:..., initialSource:name, isRosterMember:true, trip:trip) for new IDs, (b) call SnapshotMaintenance.handleRosterRemoval for removed IDs, (c) update existing snapshots in place for kept IDs whose name/colourID has changed
  - create also inserts the TripZoneState row for the new trip up-front (Req 1.5)
  - Leave trip.participants empty; do not write to it (constraint C3)
  - Blocked-by: ki2e5n1 ([impl] Refactor SnapshotMaintenance routines to mutate-only), ki2e5n6 ([test] Write tests for TripPersistence snapshot-diff behaviour)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.5](requirements.md#1.5), [6.2](requirements.md#6.2)

- [x] 16. [wire] Replace V2 trip.participants reads with trip.participantSnapshots across audit-table sites <!-- id:ki2e5n8 -->
  - Files: TripListView.swift:160, TripDetailView.swift:254 and 330, TripDraft.swift:57, PackingSheet.swift:60, PackingSummarySection.swift:50
  - For each site, switch the read to participantSnapshots; downstream consumers that previously held [Person] now hold [TripPersonSnapshot] (rename local bindings to reflect the type)
  - Stream: 1
  - Requirements: [10.1](requirements.md#10.1), [10.3](requirements.md#10.3)
  - References: design.md § Pattern-extension audit

- [x] 17. [test] Write UI test for cross-container picker reactivity <!-- id:ki2e5n9 -->
  - File: ScrambleUITests/TripEditorPickerReactivityUITests.swift (new)
  - Open Trip Editor — picker shows the People list from globals; tap + Add person — create one in the inline PersonEditor sheet; dismiss; assert the new Person appears in the picker without leaving Trip Editor (reactivity proves @Query is bound to globals)
  - Stream: 1
  - Requirements: [9.1](requirements.md#9.1), [10.1](requirements.md#10.1)
  - References: design.md § Cross-container Trip Editor people picker

- [x] 18. [impl] Extract TripEditorPeoplePicker as a child view re-rooted to .modelContainer(globals) <!-- id:ki2e5na -->
  - New file: Scramble/Scramble/Features/Trips/TripEditorPeoplePicker.swift containing the wrapper TripEditorPeoplePicker (applies .modelContainer(globals) to a PickerContent child) and PickerContent (uses @Query var allPeople: [Person] and @Environment(\.modelContext))
  - Move the Person-delete line (TripEditorView.swift:309) into PickerContent; annotate the resulting try modelContext.save() with // LocalWriteHookContract: allow — globals context, not tripsLocal
  - Move the inline + Add person sheet presentation (which mounts PersonEditor) inside PickerContent so the sheet inherits the picker container
  - TripEditorView now passes participantIDs: $draft.participantIDs to the picker and stays bound to the tripsLocal context for its trip-attribute reads
  - Blocked-by: ki2e5n9 ([test] Write UI test for cross-container picker reactivity)
  - Stream: 1
  - Requirements: [9.1](requirements.md#9.1), [10.1](requirements.md#10.1)

- [x] 19. [wire] Replace item.person reads with item.personSnapshot in PackingItemForm.swift <!-- id:ki2e5nb -->
  - The relationship already exists on the V3 schema; rename the read site and any local binding; the form write site (item.personSnapshot = ...) is preserved by the schema
  - Stream: 1
  - Requirements: [10.1](requirements.md#10.1)
  - References: design.md § Pattern-extension audit

## Phase 4: Write-path migration — direct saves → LocalWriteHook.commit

- [ ] 20. [test] Write tests for view-layer single-commit-per-action behaviour <!-- id:ki2e5nc -->
  - File: ScrambleTests/Features/Trips/ViewSaveCommitsTests.swift (new)
  - Cover with a recording PendingChangeNotifier: a packing-item add/edit/delete in PackingSheet produces exactly one notifier call; a task add/edit in TaskForm produces exactly one; a packing-item add/edit in PackingItemForm produces exactly one; orphan-snapshot cleanup on packing-item delete shows up in the same call (one commit, not two)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [6.3](requirements.md#6.3)
  - References: design.md § Save-path chokepoint topology

- [ ] 21. [impl] Route PackingSheet, TaskForm, PackingItemForm save sites through LocalWriteHook.commit <!-- id:ki2e5nd -->
  - Files: Features/Trips/PackingSheet.swift:310, Features/Trips/TaskForm.swift:145, Features/Trips/PackingItemForm.swift (both save sites)
  - Each view reads @Environment(\.localWriteHook) private var hook and replaces try modelContext.save() with try hook.commit(modelContext)
  - PackingSheet packing-item-delete handler additionally calls SnapshotMaintenance.handlePackingItemDeletion(_:in:) (mutate-only) before context.delete(item) and the single commit
  - Blocked-by: ki2e5n1 ([impl] Refactor SnapshotMaintenance routines to mutate-only), ki2e5nc ([test] Write tests for view-layer single-commit-per-action behaviour)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [6.3](requirements.md#6.3)

- [ ] 22. [test] Write tests for TripListView trip-create flow producing a TripZoneState before the upload notifier fires <!-- id:ki2e5ne -->
  - File: ScrambleTests/Features/Trips/TripListViewTests.swift (new or extended)
  - Cover: after the create commit returns, the trip TripZoneState exists in tripsLocal, the recording notifier saw a single call carrying the Trip record name as dirty, and the dirty flag is recorded against the new TripZoneState.pendingUploadFlags
  - Stream: 1
  - Requirements: [1.4](requirements.md#1.4), [1.5](requirements.md#1.5)
  - References: design.md § TripPersistence (changed)

- [ ] 23. [impl] Route TripListView and TripDetailView edit/create saves through LocalWriteHook.commit <!-- id:ki2e5nf -->
  - Both views read @Environment(\.localWriteHook) private var hook and replace try modelContext.save() with try hook.commit(modelContext)
  - TripListView create path uses the new TripPersistence.create(from:in:globals:) signature with \.globalsContainer resolved from the environment
  - TripDetailView edit path uses the new TripPersistence.apply(_:to:in:globals:) signature
  - Blocked-by: ki2e5n7 ([impl] Rewrite TripPersistence.create / apply to operate on TripPersonSnapshot), ki2e5ne ([test] Write tests for TripListView trip-create flow producing a TripZoneState before the upload notifier fires)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [2.1](requirements.md#2.1)

- [ ] 24. [test] Write tests for rules engine apply(plan:) routing through LocalWriteHook.commit <!-- id:ki2e5ng -->
  - File: ScrambleTests/RulesEngine/ApplyTests.swift (new or extended)
  - Cover: a plan with adds + flag changes produces a single notifier call carrying all affected record IDs; an apply that throws inside the commit propagates to the caller and context.rollback() clears partial inserts (rollback semantics preserved per design Apply.swift row)
  - Stream: 1
  - Requirements: [2.2](requirements.md#2.2)
  - References: design.md § Apply.swift audit-table row

- [ ] 25. [impl] Update RulesEngine/Apply.swift to call LocalWriteHook.commit <!-- id:ki2e5nh -->
  - Replace try context.save() with try hook.commit(context); the hook is passed in as a parameter on apply(plan:context:hook:) (the function gains a new parameter; RulesEngineRunner plumbs it through from its initializer)
  - RulesEngineRunner catch in runForAllNonPastTrips still calls context.rollback() on a per-trip failure
  - Blocked-by: ki2e5n1 ([impl] Refactor SnapshotMaintenance routines to mutate-only), ki2e5ng ([test] Write tests for rules engine apply(plan:) routing through LocalWriteHook.commit), routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through, routing, through
  - Stream: 1
  - Requirements: [2.2](requirements.md#2.2)

- [ ] 26. [test] Extend CloudKitSharingServiceTests for save-routing through LocalWriteHook <!-- id:ki2e5ni -->
  - File: ScrambleTests/Sharing/CloudKitSharingServiceTests.swift
  - Cover: createShare saves the shareID via LocalWriteHook.commit (notifier sees no record IDs because TripZoneState mappings return nil — confirms the save-only path works); fetchZoneState lazy insert path commits through the hook; the previously-private deleteOwnedTrip and cleanupLocalState are deleted (tests for them removed; the trip-deletion-via-CloudKitSharingService path is removed)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [5.1](requirements.md#5.1)
  - References: design.md § Pattern-extension audit CloudKitSharingService rows

- [ ] 27. [impl] Refactor Sharing/CloudKitSharingService.swift — route saves via hook; delete deleteOwnedTrip + cleanupLocalState; leaveShare tolerates zone-not-found and calls TripDeletion.delete <!-- id:ki2e5nj -->
  - Replace try context.save() at lines 46 and 297 with try hook.commit(context); inject the hook in the constructor
  - Delete deleteOwnedTrip and cleanupLocalState methods (their behaviour is now provided by TripDeletion.delete)
  - leaveShare (currently lines 122-127) calls container.sharedCloudDatabase.deleteRecordZone(withID:); tolerate zone-not-found (CKError.zoneNotFound or similar) as success; then call TripDeletion.delete(tripID:in:hook:zoneDeleter:nil) for the local cascade
  - Blocked-by: ki2e5mz ([impl] Implement LocalWriteHook.commitDeletion(_:zoneIDsBeingDeleted:)), ki2e5n3 ([impl] Refactor TripDeletion.delete to route through LocalWriteHook.commitDeletion), ki2e5ni ([test] Extend CloudKitSharingServiceTests for save-routing through LocalWriteHook)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [5.1](requirements.md#5.1), [9.3](requirements.md#9.3)
  - References: design.md § Error Handling leaveShare zone-not-found row

- [ ] 28. [wire] Switch TripDetailView.deleteTrip to call TripDeletion.delete <!-- id:ki2e5nk -->
  - File: Scramble/Scramble/Features/Trips/TripDetailView.swift
  - Replace the current modelContext.delete(trip) + modelContext.save() + sharingService.deleteOwnedTrip(...) sequence with a single try TripDeletion.delete(tripID:, in: modelContext, hook: hook, zoneDeleter: TripSyncEngineZoneDeleter(syncEngine:)) call
  - Preserve the existing toast-on-failure path and the dismiss() on success
  - Blocked-by: ki2e5n3 ([impl] Refactor TripDeletion.delete to route through LocalWriteHook.commitDeletion), ki2e5nj ([impl] Refactor Sharing/CloudKitSharingService.swift — route saves via hook; delete deleteOwnedTrip + cleanupLocalState; leaveShare tolerates zone-not-found and calls TripDeletion.delete)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4)

## Phase 5: Migration coordinator + engine event multicast + sign-in resume

- [ ] 29. [test] Extend ZoneMigrationCoordinatorTests for the 15-step relocation algorithm <!-- id:ki2e5nl -->
  - File: ScrambleTests/Persistence/ZoneMigrationCoordinatorTests.swift
  - Cover: .completed journal entries are terminal no-ops (step 2 short-circuit); the four-quadrant existence branch (both, tripsLocal-only, globals-only, neither) takes the right step 6 branch each time; step 10 clear of sentRecordNames and zoneSaved makes prior-aborted-run events no-ops on resume; Stage A TripPersonSnapshot rows are retroactively dirty-flagged on Stage B entry (Req 4.9); signed-out completes the local relocation but defers Stage B (Req 4.7); relocation preserves every persisted field per Req 4.2
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.7](requirements.md#4.7), [4.9](requirements.md#4.9), [4.10](requirements.md#4.10), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4)
  - References: design.md § ZoneMigrationCoordinator (changed), § Concurrency and ordering contracts

- [ ] 30. [impl] Implement ZoneMigrationCoordinator.relocateToTripsLocal(_:) helper <!-- id:ki2e5nm -->
  - File: Scramble/Scramble/Persistence/Migrations/ZoneMigrationCoordinator.swift
  - Reads the Trip + dependents (tasks, packingItems, participantSnapshots) from globalsContext and inserts equivalent rows into tripsLocalContext, preserving every persisted field per Req 4.2 (including id, masterItemID, currentlyMatchesRules, pinnedByUser, userDeletedOnThisTrip, state, isCompleted, assigneePersonID, name, ckRecordSystemFields, and all Codable-blob fields)
  - Commits tripsLocalContext first; only afterwards is the globals delete step run by the caller (per the per-container atomicity invariant)
  - Stream: 1
  - Requirements: [4.2](requirements.md#4.2)

- [ ] 31. [impl] Update ZoneMigrationCoordinator.enqueueAll to scan both containers <!-- id:ki2e5nn -->
  - Fetch existing journal entries from globals (unchanged); fetch existing TripZoneState rows from tripsLocal (unchanged); fetch Trip rows from BOTH containers; enqueue a journal for any trip not yet covered by a journal AND not yet in TripZoneState; idempotent on repeat
  - Blocked-by: ki2e5nm ([impl] Implement ZoneMigrationCoordinator.relocateToTripsLocal(_:) helper)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.6](requirements.md#4.6), [4.7](requirements.md#4.7)

- [ ] 32. [impl] Rewrite ZoneMigrationCoordinator.startOrResume per the 15-step algorithm <!-- id:ki2e5no -->
  - Steps 2 (.completed short-circuit), 6 (four-quadrant existence branch invoking relocateToTripsLocal and deleteFromGlobals as appropriate), 10 (clear sentRecordNames + zoneSaved before re-marking .stageBInProgress), 13 (retroactively dirty-flag Stage A snapshot rows), 14 (sequential tripsLocalContext.save() then globalsContext.save(), both @MainActor, no await between)
  - Blocked-by: ki2e5nl ([test] Extend ZoneMigrationCoordinatorTests for the 15-step relocation algorithm), ki2e5nm ([impl] Implement ZoneMigrationCoordinator.relocateToTripsLocal(_:) helper), ki2e5nn ([impl] Update ZoneMigrationCoordinator.enqueueAll to scan both containers)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.9](requirements.md#4.9), [4.10](requirements.md#4.10)

- [ ] 33. [test] Write parameterised PBT for cross-store consistency + idempotence <!-- id:ki2e5np -->
  - File: ScrambleTests/Persistence/ZoneMigrationCoordinatorPBT.swift (new)
  - Use Swift Testing @Test(arguments:) over the cross-product interruptionPoint in {fresh, after-step-10-clear, after-tripsLocal-save, after-globals-delete, after-completion} × resumeCount in {1, 2, 5}; assert terminal state is either tripsLocal-only or globals-only for the trip and that the journal converges to a terminal state
  - Blocked-by: ki2e5no ([impl] Rewrite ZoneMigrationCoordinator.startOrResume per the 15-step algorithm)
  - Stream: 1
  - Requirements: [4.5](requirements.md#4.5), [4.6](requirements.md#4.6)
  - References: design.md § Property-based tests property 1

- [ ] 34. [test] Write parameterised PBT for commitDeletion mixed-zone partition <!-- id:ki2e5nq -->
  - File: ScrambleTests/Sharing/LocalWriteHookPBT.swift (new)
  - Use Swift Testing @Test(arguments:) over generators of (zoneIDsBeingDeleted, deleted_in_vanishing_zone, deleted_in_surviving_zone, changed_in_surviving_zone); assert post-commit surviving-zone pendingUploadFlags equal the surviving-only set and the notifier received the union of all deleted IDs
  - Blocked-by: ki2e5mz ([impl] Implement LocalWriteHook.commitDeletion(_:zoneIDsBeingDeleted:))
  - Stream: 1
  - Requirements: [2.4](requirements.md#2.4)
  - References: design.md § Property-based tests property 2

- [ ] 35. [test] Write TripSyncEventBusTests <!-- id:ki2e5nr -->
  - File: ScrambleTests/Sharing/TripSyncEventBusTests.swift (new)
  - Cover: a single iteration multicasts every event to both registered subscribers; one subscriber throwing inside its handler is logged and does NOT cancel the bus or starve the other subscriber; late-subscribe-after-start in DEBUG triggers assertionFailure; test-only stop() cancels the iteration
  - Stream: 1
  - Requirements: [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3)
  - References: design.md § TripSyncEventBus (new)

- [ ] 36. [impl] Implement Sharing/TripSyncEventBus.swift <!-- id:ki2e5ns -->
  - Owns a single Task iterating the engine events stream; subscribers register their handler via subscribeOrchestrator / subscribeCoordinator (with the documented late-register precondition: assertionFailure in DEBUG, log+return in release); each dispatch is wrapped in do { handler(event) } catch { modelLogger.error(...) }
  - Test-only stop() cancels the task
  - Blocked-by: ki2e5nr ([test] Write TripSyncEventBusTests)
  - Stream: 1
  - Requirements: [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4)

- [ ] 37. [test] Write SignInResumeCoordinatorTests <!-- id:ki2e5nt -->
  - File: ScrambleTests/App/SignInResumeCoordinatorTests.swift (new)
  - Cover: start() immediately re-checks accountStatus() and runs when available; CKAccountChanged notification triggers a run; UIScene.didActivateNotification fallback also triggers a run; concurrent triggers collapse to a single trailing replay via the inFlight: Task? + pendingReplay: Bool mechanism; migrationCoordinator.isCloudAvailable() returning false short-circuits the run
  - Stream: 1
  - Requirements: [4.8](requirements.md#4.8)
  - References: design.md § SignInResumeCoordinator (new)

- [ ] 38. [impl] Implement App/SignInResumeCoordinator.swift <!-- id:ki2e5nu -->
  - @MainActor final class. Init takes migrationCoordinator: ZoneMigrationCoordinator and container: CKContainer. start() installs the two observers and performs the immediate accountStatus() re-check. runResumeIfNeeded() is the single entry point: checks isCloudAvailable(), runs enqueueAll + runStageB, and uses an inFlight: Task? + pendingReplay: Bool to collapse storm-fire to at most one trailing replay
  - Blocked-by: ki2e5nt ([test] Write SignInResumeCoordinatorTests)
  - Stream: 1
  - Requirements: [4.8](requirements.md#4.8)

- [ ] 39. [wire] Wire ScrambleApp to construct the EventBus, SignInResumeCoordinator, and route MigrationGate through them <!-- id:ki2e5nv -->
  - Files: Scramble/Scramble/ScrambleApp.swift, Scramble/Scramble/App/MigrationGate.swift
  - In ScrambleApp.init: construct TripSyncEventBus(events: engine.events); call bus.subscribeOrchestrator(triggerOrchestrator) and bus.subscribeCoordinator(migrationCoordinator) BEFORE bus.start(); construct SignInResumeCoordinator(migrationCoordinator:container:) and call start() after bus.start()
  - MigrationGate.prepare() awaits signInResumeCoordinator.runResumeIfNeeded() instead of calling enqueueAll/runStageB directly; the gate also logs a warning when the count of MigrationJournalEntry rows exceeds 100 (the journal accumulation back-stop)
  - Drop the old direct event-iteration loop (Task { for await event in engine.events { orchestrator.handle... } }) — the bus owns the iteration now
  - Blocked-by: ki2e5no ([impl] Rewrite ZoneMigrationCoordinator.startOrResume per the 15-step algorithm), ki2e5ns ([impl] Implement Sharing/TripSyncEventBus.swift), ki2e5nu ([impl] Implement App/SignInResumeCoordinator.swift)
  - Stream: 1
  - Requirements: [4.8](requirements.md#4.8), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4)

## Phase 6: Offline share + contract tests + UI tests

- [ ] 40. [test] Extend CloudKitSharingServiceTests for offline-share preflight <!-- id:ki2e5nw -->
  - File: ScrambleTests/Sharing/CloudKitSharingServiceTests.swift
  - Cover: createShare throws SharingError.networkUnavailable when the injected account-status / network-path probe reports unavailable; the trip is NOT marked as shared locally on throw; a subsequent createShare call after the probe flips to available proceeds normally without app restart
  - Stream: 1
  - Requirements: [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)

- [ ] 41. [impl] Add SharingError.networkUnavailable + iCloudAvailable() preflight in createShare <!-- id:ki2e5nx -->
  - File: Scramble/Scramble/Sharing/CloudKitSharingService.swift and Scramble/Scramble/Sharing/SharingService.swift (SharingError lives near the protocol)
  - Add the new error case; inject the probe (real production probe uses CKContainer.accountStatus() + NWPathMonitor; the test injects a stub)
  - Blocked-by: ki2e5nw ([test] Extend CloudKitSharingServiceTests for offline-share preflight)
  - Stream: 1
  - Requirements: [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)

- [ ] 42. [test] Write UI test OfflineShareUITests <!-- id:ki2e5ny -->
  - File: ScrambleUITests/OfflineShareUITests.swift (new)
  - With the iCloudAvailability probe stubbed to unavailable (via UITestSeed + a launch argument), tap Share on a trip; assert the toast Network required to share appears; assert no share is recorded by the fake SharingService
  - Stream: 1
  - Requirements: [8.1](requirements.md#8.1)
  - References: design.md § Testing Strategy — UI tests

- [ ] 43. [impl] ShareToolbarButton catches SharingError.networkUnavailable and shows toast <!-- id:ki2e5nz -->
  - File: Scramble/Scramble/Features/Trips/ShareToolbarButton.swift
  - Catch the typed error and emit a TransientToast with copy Network required to share; other errors keep the existing handling
  - Blocked-by: ki2e5nx ([impl] Add SharingError.networkUnavailable + iCloudAvailable() preflight in createShare), ki2e5ny ([test] Write UI test OfflineShareUITests)
  - Stream: 1
  - Requirements: [8.1](requirements.md#8.1)

- [ ] 44. [test] Write LocalWriteHookContractTest source-pattern scan <!-- id:ki2e5o0 -->
  - File: ScrambleTests/Contracts/LocalWriteHookContractTest.swift (new)
  - Walks .swift files under Scramble/Scramble/, excluding LocalWriteHook.swift, TripDeletion.swift, ZoneMigrationCoordinator.swift, and the Components/ directory globals-only files; flags any modelContext.save() or context.save() call site unless the line carries the marker // LocalWriteHookContract: allow (used by the picker file and the legacy PersonEditor delete site)
  - The test fails the build on stray saves and passes on the cleaned tree
  - Test asserts both: (a) clean tree passes, (b) a synthetic offending fixture string fails — guarding against the test becoming a no-op due to a regex bug
  - Stream: 1
  - Requirements: [2.5](requirements.md#2.5)
  - References: design.md § Testing Strategy — Unit tests

- [ ] 45. [test] Write V2RelationshipUseTest (SwiftSyntax-based) <!-- id:ki2e5o1 -->
  - File: ScrambleTests/Contracts/V2RelationshipUseTest.swift (new)
  - Parses every .swift file in the trip-domain file set (all files under Features/Trips/, Components/TaskListSection.swift, and any future file marked // trip-domain view); fails on .participants member access rooted in a value statically typed as Trip, or .person rooted in a value statically typed as TripPackingItem; honours // V2Relationship: allow escape
  - Asserts both clean-tree pass and a synthetic offending fixture failure, as for task 44
  - Stream: 1
  - Requirements: [10.3](requirements.md#10.3)
  - References: design.md § Testing Strategy — Unit tests

- [ ] 46. [impl] Add swift-syntax SPM dependency to ScrambleTests and finalise V2RelationshipUseTest <!-- id:ki2e5o2 -->
  - Add the dependency to Scramble.xcodeproj test target (pin from: 601.0.0); finalise the test implementation behind the dependency
  - Blocked-by: ki2e5o1 ([test] Write V2RelationshipUseTest (SwiftSyntax-based))
  - Stream: 1
  - Requirements: [10.3](requirements.md#10.3)

- [ ] 47. [impl] Update UITestSeed for per-fixture container choice and add tripCRUDPropagation fixture <!-- id:ki2e5o3 -->
  - File: Scramble/Scramble/Persistence/UITestSeed.swift
  - Legacy fixture phase5MigrationStates seeds Trip and its dependents into globalsContainer (simulates pre-Phase-5.1 state requiring relocation); all other fixtures seed Trip and its dependents into tripsLocalContainer; Person + MasterTaskItem + MasterPackingItem always seed into globalsContainer
  - Add a new fixture tripCRUDPropagation for the new UI test in task 48
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.5](requirements.md#4.5)

- [ ] 48. [test] Write TripCRUDPropagationUITests <!-- id:ki2e5o4 -->
  - File: ScrambleUITests/TripCRUDPropagationUITests.swift (new)
  - Launch with the tripCRUDPropagation fixture; create a trip — verify it appears in the Trip List; edit the trip name — relaunch — verify the name persists; verify a fake PendingChangeNotifier (test-only injection point) recorded the expected upload signals
  - Blocked-by: ki2e5nf ([impl] Route TripListView and TripDetailView edit/create saves through LocalWriteHook.commit), ki2e5o3 ([impl] Update UITestSeed for per-fixture container choice and add tripCRUDPropagation fixture)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.4](requirements.md#1.4)

- [ ] 49. [test] Write TripDeletionUITests <!-- id:ki2e5o5 -->
  - File: ScrambleUITests/TripDeletionUITests.swift (new)
  - Launch with a fixture trip; delete it from Trip Detail — verify it disappears from Trip List immediately; verify a fake TripZoneDeleter (test-only injection) recorded the zone-delete request
  - Blocked-by: ki2e5nk ([wire] Switch TripDetailView.deleteTrip to call TripDeletion.delete), ki2e5o3 ([impl] Update UITestSeed for per-fixture container choice and add tripCRUDPropagation fixture)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.4](requirements.md#5.4)

## Phase 7: Documentation deliverables (per Decision 5)

- [ ] 50. [impl] Create specs/phase-5-cloudkit-sharing/manual-test-plan.md <!-- id:ki2e5o6 -->
  - Cover the cases real CloudKit infrastructure validates and in-process tests cannot: two-device share lifecycle (owner creates share → invitee accepts → owner edits propagate → participant edit propagates back); offline share affordance (toggle airplane mode → tap Share → toast appears → reconnect → retry succeeds); owner-delete-while-participant-online (zone deletion observed on participant device); iCloud-account-transition resume (sign out → relocation completes locally → sign in → Stage B uploads backlog → Syncing badge clears)
  - Stream: 1

- [ ] 51. [impl] Update CLAUDE.md project-status sentence for Phase 5.1 <!-- id:ki2e5o7 -->
  - Append a one-sentence summary of Phase 5.1 observable outcome (cross-device sync now functions; previously broken share-acceptance and owner-edit propagation now work) to the existing project-status paragraph
  - Blocked-by: ki2e5nv ([wire] Wire ScrambleApp to construct the EventBus, SignInResumeCoordinator, and route MigrationGate through them)
  - Stream: 1
  - References: design.md § Overview

- [ ] 52. [impl] Update specs/phase-5-cloudkit-sharing/implementation.md Completeness Assessment <!-- id:ki2e5o8 -->
  - Flip the assessment rows for requirement clusters newly fulfilled by Phase 5.1 (Phase 5 Reqs 1.3, 4.1, 4.5, 6.2, 11.2) to fully implemented with a cross-reference to this spec
  - Blocked-by: ki2e5nv ([wire] Wire ScrambleApp to construct the EventBus, SignInResumeCoordinator, and route MigrationGate through them)
  - Stream: 1
  - References: implementation-phases.md § Phase 5.1
