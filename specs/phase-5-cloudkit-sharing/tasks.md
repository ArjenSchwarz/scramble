---
references:
    - specs/phase-5-cloudkit-sharing/requirements.md
    - specs/phase-5-cloudkit-sharing/design.md
    - specs/phase-5-cloudkit-sharing/decision_log.md
---
# Phase 5 — CloudKit Sharing

## Validation gate

- [x] 1. Build CKSyncEngine validation harness <!-- id:vzlf7fp -->
  - Throwaway XCTest in ScrambleTests: create private CKSyncEngine, create custom zone, create CKShare(recordZoneID:), verify share record reaches CloudKit
  - Manual second-device step: accept share, verify shared CKSyncEngine fetches the records
  - Pass/fail decides whether Decision 13 stands or fallback to raw CKDatabase is needed
  - Lands as the first commit on the Phase 5 branch and gates merging anything else
  - Stream: 1
  - References: specs/phase-5-cloudkit-sharing/design.md

## Schema + Stage A migration

- [x] 2. Write SchemaV3 plan-shape tests <!-- id:vzlf7fq -->
  - SchemaV3MigrationTests asserts AppMigrationPlan.schemas includes V3, stages includes V2->V3, lightweight + custom stage typing
  - Mirrors SchemaV2MigrationTests pattern from docs/agent-notes/persistence.md
  - Blocked-by: vzlf7fp (Build CKSyncEngine validation harness)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 3. Implement SchemaV3 entities and additive fields <!-- id:vzlf7fr -->
  - In Models/Schema.swift add SchemaV3 with TripPersonSnapshot, TripZoneState, MigrationJournalEntry
  - Add new V3 fields with new names (additive; deprecated V2 fields kept until V4): Trip.participantSnapshots, Trip.tripZoneID, Trip.ckRecordSystemFields, TripTask.ckRecordSystemFields, TripPackingItem.personSnapshot, TripPackingItem.ckRecordSystemFields
  - Update typealias TripTask to point at V3 versions where needed
  - TripPersonSnapshot fields per design: id, personID, name, colourID, initialSource, isRosterMember, trip inverse, tripPackingItems inverse, ckRecordSystemFields
  - Blocked-by: vzlf7fq (Write SchemaV3 plan-shape tests)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.5](requirements.md#2.5)
  - References: specs/phase-5-cloudkit-sharing/design.md, docs/agent-notes/persistence.md

- [x] 4. Write Stage A custom migration tests <!-- id:vzlf7fs -->
  - SchemaV3MigrationStageTests seeds V2-shaped in-memory store with Trip + Person + TripPackingItem
  - Asserts TripPersonSnapshot inserted, Trip.participantSnapshots populated, TripPackingItem.personSnapshot set, deprecated V2 fields untouched
  - Idempotent on second run (no duplicate snapshots)
  - Blocked-by: vzlf7fr (Implement SchemaV3 entities and additive fields)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 5. Implement Stage A custom MigrationStage <!-- id:vzlf7ft -->
  - In Persistence/Migrations/SchemaV3MigrationStage.swift
  - Custom MigrationStage in AppMigrationPlan; seeds TripPersonSnapshot from existing Person references and rewires TripPackingItem.personSnapshot
  - Idempotent: skip if snapshot already exists for (trip, personID) pair
  - Offline-safe: no CloudKit calls; runs unconditionally even when signed out
  - Blocked-by: vzlf7fs (Write Stage A custom migration tests)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.4](requirements.md#2.4)
  - References: specs/phase-5-cloudkit-sharing/design.md

## Sync infrastructure

- [x] 6. Define SharingService protocol and DTOs <!-- id:vzlf7fu -->
  - In Sharing/SharingService.swift: protocol + AcceptedShareResult + ShareParticipant + OwnerIdentity
  - Interface-only task; tests come with implementations
  - Blocked-by: vzlf7ft (Implement Stage A custom MigrationStage)
  - Stream: 1
  - Requirements: [12.1](requirements.md#12.1)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 7. Wire ModelStore to provide globals + tripsLocal containers <!-- id:vzlf7fv -->
  - Extend Persistence/ModelStore.swift to construct two ModelContainers: globals (cloudKitDatabase: .private) and tripsLocal (cloudKitDatabase: .none)
  - Update EnvironmentProbe wiring so tests get in-memory variants of both
  - Both containers mounted at app start
  - Blocked-by: vzlf7fr (Implement SchemaV3 entities and additive fields)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.4](requirements.md#3.4)
  - References: specs/phase-5-cloudkit-sharing/design.md, docs/agent-notes/persistence.md

- [x] 8. Write CKRecord translator tests <!-- id:vzlf7fw -->
  - One test class per entity translator in Sharing/Translators/
  - Cover: UUID-relationship encoding (personSnapshot stored as personSnapshotID String); system-fields preservation across roundtrip; 256 KB Codable-blob size cap throws translator error; enum raw-string bridging; non-Optional default fill on absent record fields
  - Blocked-by: vzlf7fu (Define SharingService protocol and DTOs), vzlf7fv (Wire ModelStore to provide globals + tripsLocal containers)
  - Stream: 1
  - Requirements: [2.5](requirements.md#2.5), [3.5](requirements.md#3.5)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 9. Implement CKRecord translators <!-- id:vzlf7fx -->
  - In Sharing/Translators/: TripRecordTranslator, TripTaskRecordTranslator, TripPackingItemRecordTranslator, TripPersonSnapshotRecordTranslator, TripZoneStateRecordTranslator
  - All conform to RecordRepresentable with toRecord(existing:) and from(_:into:)
  - Relationships as UUID record fields, not CKRecord.Reference
  - Blocked-by: vzlf7fw (Write CKRecord translator tests)
  - Stream: 1
  - Requirements: [2.5](requirements.md#2.5), [3.2](requirements.md#3.2), [3.5](requirements.md#3.5), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 10. Write LocalWriteHook tests <!-- id:vzlf7fy -->
  - In Sharing/LocalWriteHookTests.swift
  - Insert/change/delete on tripsLocal models flips correct dirty bits in TripZoneState.pendingUploadFlags
  - Calls context.save once per commit
  - Notifies engine state with correct record IDs
  - Blocked-by: vzlf7fx (Implement CKRecord translators)
  - Stream: 1
  - Requirements: [8.5](requirements.md#8.5)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 11. Implement LocalWriteHook <!-- id:vzlf7fz -->
  - In Sharing/LocalWriteHook.swift
  - Single chokepoint: inspects context.insertedModels/changedModels/deletedModels, updates TripZoneState, calls save, notifies TripSyncEngine
  - All trip-data writes go through commit(_:); direct context.save outside the hook is forbidden
  - Blocked-by: vzlf7fy (Write LocalWriteHook tests)
  - Stream: 1
  - Requirements: [8.5](requirements.md#8.5)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 12. Write FakeSharingService tests <!-- id:vzlf7g0 -->
  - In Sharing/FakeSharingServiceTests.swift
  - Two-side bus delivers events from one endpoint to the other with controllable delay (bus.deliveryDelay)
  - Share creation + acceptance lifecycle observable from both sides
  - simulateOwnerWrite on side A propagates to side B fetched-event stream
  - Blocked-by: vzlf7fu (Define SharingService protocol and DTOs)
  - Stream: 1
  - Requirements: [12.1](requirements.md#12.1), [12.2](requirements.md#12.2), [12.3](requirements.md#12.3)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 13. Implement FakeSharingService with two-side bus <!-- id:vzlf7g1 -->
  - In Sharing/FakeSharingService.swift (test target ScrambleTests)
  - final class connecting two TripSyncEngine-shaped fake endpoints in-process
  - Imperative test hooks: simulateAcceptance, triggerZoneChange, simulateError, set deliveryDelay
  - Blocked-by: vzlf7g0 (Write FakeSharingService tests)
  - Stream: 1
  - Requirements: [12.1](requirements.md#12.1), [12.2](requirements.md#12.2)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 14. Write TripSyncEngine tests <!-- id:vzlf7g2 -->
  - nextRecordZoneChangeBatch builds CKRecords from dirty TripZoneState entries via translators
  - handleEvent translates fetched records into tripsLocal writes via translators
  - events stream emits zoneChanged with isSelfOriginated correctly populated for self-sent events
  - stateSerialization decode failure -> discard + full fetchChanges
  - Blocked-by: vzlf7g1 (Implement FakeSharingService with two-side bus)
  - Stream: 1
  - Requirements: [8.4](requirements.md#8.4), [9.1](requirements.md#9.1), [9.2](requirements.md#9.2)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 15. Implement TripSyncEngine <!-- id:vzlf7g3 -->
  - In Sharing/TripSyncEngine.swift
  - Wraps two CKSyncEngine instances (privateEngine on .private DB, sharedEngine on .shared DB) with delegate methods
  - events: AsyncStream<TripSyncEvent>
  - State persisted at ~/Library/Application Support/Scramble/CKSync/{private,shared}.state with isExcludedFromBackupKey
  - State corruption recovery: discard corrupt blob, construct engine with no prior state, request full fetchChanges
  - Blocked-by: vzlf7g2 (Write TripSyncEngine tests)
  - Stream: 1
  - Requirements: [9.1](requirements.md#9.1), [9.2](requirements.md#9.2), [9.3](requirements.md#9.3), [9.5](requirements.md#9.5)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 16. Write CloudKitSharingService share lifecycle tests <!-- id:vzlf7g4 -->
  - All tested via FakeSharingService
  - createShare uses CKShare(recordZoneID:); save submitted via CKSyncEngine.State.add(pendingRecordZoneChanges:) with record ID; resolves on sentRecordZoneChanges confirmation
  - acceptShare calls CKContainer.accept then sharedEngine.fetchChanges (no .saveZone)
  - leaveShare deletes zone in shared DB then runs local cleanup in correct order
  - participants returns CKShare.Participant list with display name fallback chain (display name -> email -> Invited participant)
  - ownerIdentity reads TripZoneState synchronously
  - Blocked-by: vzlf7g3 (Implement TripSyncEngine)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.5](requirements.md#1.5), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.5](requirements.md#5.5), [6.1](requirements.md#6.1), [6.5](requirements.md#6.5), [7.1](requirements.md#7.1), [7.8](requirements.md#7.8), [10.1](requirements.md#10.1), [10.4](requirements.md#10.4)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 17. Implement CloudKitSharingService <!-- id:vzlf7g5 -->
  - In Sharing/CloudKitSharingService.swift
  - Production impl wrapping CKContainer + UICloudSharingController + TripSyncEngine
  - Includes UICloudSharingControllerRepresentable in Sharing/UICloudSharingControllerRepresentable.swift (UIViewControllerRepresentable wrapper)
  - createShare uses CKShare(recordZoneID: zoneState.zoneID), publicPermission = .none, every invitee read-write
  - presentShareUI on already-shared trip routes to system manage-participants sheet
  - Blocked-by: vzlf7g4 (Write CloudKitSharingService share lifecycle tests)
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5), [7.5](requirements.md#7.5), [7.6](requirements.md#7.6), [9.4](requirements.md#9.4), [11.2](requirements.md#11.2), [11.4](requirements.md#11.4)
  - References: specs/phase-5-cloudkit-sharing/design.md

## Stage B + engine + lifecycle

- [x] 18. Write Stage B coordinator tests with PBT <!-- id:vzlf7g6 -->
  - In Persistence/Migrations/ZoneMigrationCoordinatorTests.swift against FakeSharingService
  - Happy path; resume after kill mid-migration; concurrent-device convergence (deterministic zone naming, CKSyncEngine handles record dedup); signed-out skip; failure + retry surfaces banner
  - PBT (Swift Testing parameterised) for: idempotence (run twice -> same end state), convergence (any partial-failure sequence reaches terminal), resume totality
  - Blocked-by: vzlf7g5 (Implement CloudKitSharingService)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.7](requirements.md#4.7), [4.8](requirements.md#4.8), [4.9](requirements.md#4.9), [11.3](requirements.md#11.3)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 19. Implement ZoneMigrationCoordinator <!-- id:vzlf7g7 -->
  - In Persistence/Migrations/ZoneMigrationCoordinator.swift
  - Per trip: insert MigrationJournalEntry(.stageBInProgress); compute deterministic zoneID trip-<uuid>; insert TripZoneState; instruct privateEngine.state.add to saveZone + add expected record IDs as pending changes; trigger sendChanges
  - Completion correlation: track expected record-ID set on journal; .completed when all expected IDs in cumulative savedRecords AND state.pendingRecordZoneChanges no longer contains any of them AND zone-save event succeeded
  - Resume: on launch, re-run from step 5 for .stageBInProgress entries (zone create idempotent; CKSyncEngine state retains pending changes)
  - Best-effort cleanup of orphaned default-zone records via CKDatabase.modifyRecords post-completion (failures logged, non-blocking)
  - Blocked-by: vzlf7g6 (Write Stage B coordinator tests with PBT)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.7](requirements.md#4.7), [4.9](requirements.md#4.9)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 20. Write engine ownership gate + echo suppression tests <!-- id:vzlf7g8 -->
  - In Engine/RulesEngineOwnershipGateTests.swift
  - Engine no-op for non-owned trips on every existing trigger (trip created, attribute edited, master item edited, app launch)
  - Master-item edit fan-out filtered to owner-owned trips only
  - Engine runs for owner trips on each trigger
  - Engine ignores zoneChanged events where isSelfOriginated == true
  - Engine runs on zoneChanged where isSelfOriginated == false (the new CloudKit-received-change trigger)
  - Blocked-by: vzlf7g3 (Implement TripSyncEngine)
  - Stream: 1
  - Requirements: [8.3](requirements.md#8.3), [8.4](requirements.md#8.4), [8.5](requirements.md#8.5), [8.6](requirements.md#8.6)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 21. Implement engine ownership gate + new CloudKit-received-change trigger <!-- id:vzlf7g9 -->
  - Add ownership guard at rules engine entry point: guard sharingService.ownerIdentity(for: trip.id) == .currentUser else { return }
  - Subscribe rules engine trigger orchestrator to TripSyncEngine.events; filter isSelfOriginated; route .zoneChanged for owner-owned trips to engine
  - Master-item edit fan-out filters by ownership before scheduling work
  - App launch trigger source: Scene.onChange(of: scenePhase) { _, new in if new == .active }
  - Blocked-by: vzlf7g8 (Write engine ownership gate + echo suppression tests)
  - Stream: 1
  - Requirements: [8.3](requirements.md#8.3), [8.4](requirements.md#8.4), [8.5](requirements.md#8.5), [8.6](requirements.md#8.6)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 22. Write snapshot maintenance tests <!-- id:vzlf7ga -->
  - In Sharing/SnapshotMaintenanceTests.swift
  - Person edit on owner device propagates to TripPersonSnapshot across all owned trips with that person; all dirty-flagged for upload
  - Roster removal cleanup: remove Person from trip.participantSnapshots; if no TripPackingItem references the snapshot, snapshot deleted in same transaction
  - Packing-item delete cleanup: when last referring item is deleted AND snapshot.isRosterMember == false, snapshot deleted
  - Periodic sweep: orphan snapshots cleared after engine run
  - Blocked-by: vzlf7fz (Implement LocalWriteHook)
  - Stream: 1
  - Requirements: [2.3](requirements.md#2.3), [2.4](requirements.md#2.4)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 23. Implement SnapshotMaintenance <!-- id:vzlf7gb -->
  - In Sharing/SnapshotMaintenance.swift
  - Person->snapshot propagation: triggered on Person changes in globals; updates name/colourID/initialSource on each snapshot; flags for upload via LocalWriteHook
  - Three cleanup triggers: roster removal, packing-item deletion, post-engine-run sweep
  - Owner-only (gated by SharingService.ownerIdentity)
  - Blocked-by: vzlf7ga (Write snapshot maintenance tests)
  - Stream: 1
  - Requirements: [2.3](requirements.md#2.3), [2.4](requirements.md#2.4)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 24. Write trip-global flag sync + deletion ordering tests <!-- id:vzlf7gc -->
  - TripFlagSyncTests: pinnedByUser and userDeletedOnThisTrip toggles by any member propagate via fake events; engine respects them as trip-global
  - TripDeletionTests: owner-side trip deletion order is packing items -> tasks -> snapshots -> trip -> TripZoneState; no orphaned snapshots; one transaction
  - Blocked-by: vzlf7g3 (Implement TripSyncEngine)
  - Stream: 1
  - Requirements: [8.7](requirements.md#8.7)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 25. Implement trip-global flag handling + deletion path <!-- id:vzlf7gd -->
  - Translator preserves flag values across roundtrip; LWW per attribute via translator
  - Trip-deletion routine in Trip CRUD follows documented reverse-cascade order in one transaction
  - Owner-deletion deletes the CKRecordZone via privateEngine.state.add(pendingDatabaseChanges: [.deleteZone(zoneID)])
  - Blocked-by: vzlf7gc (Write trip-global flag sync + deletion ordering tests)
  - Stream: 1
  - Requirements: [1.4](requirements.md#1.4), [8.7](requirements.md#8.7)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 26. Write remote-notification routing tests <!-- id:vzlf7ge -->
  - In App/RemoteNotificationRoutingTests.swift
  - CKNotification with .private databaseScope routes to privateEngine.fetchChanges()
  - .shared databaseScope routes to sharedEngine.fetchChanges()
  - Completion handler invoked once relevant engine signals fetch completion
  - Blocked-by: vzlf7g3 (Implement TripSyncEngine)
  - Stream: 1
  - Requirements: [9.1](requirements.md#9.1), [9.3](requirements.md#9.3)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 27. Implement AppDelegate (UIApplicationDelegateAdaptor) <!-- id:vzlf7gf -->
  - In App/AppDelegate.swift
  - application(_:userDidAcceptCloudKitShareWith:) routes metadata to SharingService.acceptShare
  - application(_:didReceiveRemoteNotification:fetchCompletionHandler:) branches on notification.databaseScope and calls fetchChanges() on the appropriate engine
  - Blocked-by: vzlf7ge (Write remote-notification routing tests), vzlf7g5 (Implement CloudKitSharingService)
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [9.1](requirements.md#9.1), [9.3](requirements.md#9.3)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 28. Implement MigrationGate root wrapper <!-- id:vzlf7gg -->
  - In App/MigrationGate.swift
  - Full-screen view that blocks UI while any MigrationJournalEntry.state == .pending (Stage A still pending for any trip)
  - Releases when Stage A complete for all trips; Stage B continues in background
  - Constructs TripSyncEngine after release (Stage A -> engine ordering)
  - Signed-out: skip Stage B entirely; show locally migrated trips in Phase 1 local-only fallback; hide Share affordance
  - Blocked-by: vzlf7g7 (Implement ZoneMigrationCoordinator), vzlf7gf (Implement AppDelegate (UIApplicationDelegateAdaptor))
  - Stream: 1
  - Requirements: [4.3](requirements.md#4.3), [4.8](requirements.md#4.8), [11.1](requirements.md#11.1), [11.3](requirements.md#11.3)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 29. Wire ScrambleApp to use AppDelegate + MigrationGate <!-- id:vzlf7gh -->
  - In App/ScrambleApp.swift
  - Add UIApplicationDelegateAdaptor
  - Wrap root scene in MigrationGate
  - App-launch engine trigger via Scene.onChange(of: scenePhase) { _, new in if new == .active }
  - Inject SharingService through Phase 1 EnvironmentProbe pattern (extend with sharing: slot)
  - Blocked-by: vzlf7gg (Implement MigrationGate root wrapper), vzlf7fv (Wire ModelStore to provide globals + tripsLocal containers)
  - Stream: 1
  - References: specs/phase-5-cloudkit-sharing/design.md

## UI + release-prep

- [x] 30. Write Share affordance + Participants section UI tests <!-- id:vzlf7gi -->
  - In ScrambleUITests
  - Share toolbar button visible only when current user is owner; hidden for participants
  - Participants section pending vs accepted distinction visible; display-name fallback chain (display name -> email -> Invited participant)
  - Participants section read-only for participants; tap on owner-side participant opens manage-participants sheet
  - Blocked-by: vzlf7g5 (Implement CloudKitSharingService)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [7.7](requirements.md#7.7), [7.8](requirements.md#7.8), [10.2](requirements.md#10.2), [10.3](requirements.md#10.3)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 31. Implement Share toolbar button + Participants section <!-- id:vzlf7gj -->
  - Views/TripDetail/ShareToolbarButton.swift: Trip Detail header trailing toolbar item; matches existing toolbar style
  - Views/TripDetail/ParticipantsSection.swift: between header and timeline; renders [ShareParticipant]; tap opens UICloudSharingControllerRepresentable for owners; static for participants
  - Pending-name placeholder updates without user interaction once name resolves
  - Visually and structurally separate from the Phase 1 trip people roster (Req 8.9)
  - Blocked-by: vzlf7gi (Write Share affordance + Participants section UI tests), vzlf7g5 (Implement CloudKitSharingService)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.6](requirements.md#5.6), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [7.7](requirements.md#7.7), [7.8](requirements.md#7.8), [8.9](requirements.md#8.9), [10.2](requirements.md#10.2), [10.3](requirements.md#10.3)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 32. Write tests for participant-side WhyDisclosure hide + Rules last evaluated subline <!-- id:vzlf7gk -->
  - WhyDisclosure: assert affordance not present in layout when masterItemID does not resolve in participant globals zone
  - Rules last evaluated: subline contains Rules last evaluated {relative-time} only when current user is participant on a shared trip; updates whenever owner-side engine run is observed via TripSyncEngine.events
  - Owner-viewed trips omit the line
  - Blocked-by: vzlf7g5 (Implement CloudKitSharingService), vzlf7gb (Implement SnapshotMaintenance)
  - Stream: 1
  - Requirements: [3.3](requirements.md#3.3), [8.8](requirements.md#8.8)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 33. Implement WhyDisclosure participant hide + Rules last evaluated subline <!-- id:vzlf7gl -->
  - Update Views/Common/WhyDisclosure.swift to hide affordance entirely (no view rendered) when masterItemID resolution fails
  - Append Rules last evaluated {relative-time} clause to existing Trip Detail header subline component for participant-viewed shared trips
  - Use Phase 1 RelativeDateFormatter; clause omitted on owner-viewed trips
  - Blocked-by: vzlf7gk (Write tests for participant-side WhyDisclosure hide + Rules last evaluated subline)
  - Stream: 1
  - Requirements: [3.3](requirements.md#3.3), [8.8](requirements.md#8.8)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 34. Write tests for MigrationRetryBanner + Trip List Syncing badge <!-- id:vzlf7gm -->
  - MigrationRetryBanner: one row per .failed MigrationJournalEntry; tap re-runs Stage B for that trip
  - Trip List Syncing badge shown for trips whose journal is .stageBInProgress; cleared on .completed
  - Blocked-by: vzlf7g7 (Implement ZoneMigrationCoordinator)
  - Stream: 1
  - Requirements: [4.4](requirements.md#4.4), [4.8](requirements.md#4.8)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 35. Implement MigrationRetryBanner + Trip List Syncing badge <!-- id:vzlf7gn -->
  - Views/TripList/MigrationRetryBanner.swift: inline banner above trip rows for .failed entries; tap retries Stage B (calls into ZoneMigrationCoordinator)
  - Add Syncing badge to existing TripRow for .stageBInProgress entries
  - Blocked-by: vzlf7gm (Write tests for MigrationRetryBanner + Trip List Syncing badge)
  - Stream: 1
  - Requirements: [4.4](requirements.md#4.4), [4.8](requirements.md#4.8)
  - References: specs/phase-5-cloudkit-sharing/design.md

- [x] 36. Add CloudKit production schema promotion checklist to release-prep <!-- id:vzlf7go -->
  - Append to docs/release-prep.md (or create the file) an explicit checklist item to promote new CloudKit record types and zone topology introduced by SchemaV3 from Development to Production via the CloudKit Dashboard
  - Item must be present in the release-prep checklist that runs before TestFlight or App Store releases
  - Blocked-by: vzlf7fr (Implement SchemaV3 entities and additive fields)
  - Stream: 1
  - Requirements: [13.1](requirements.md#13.1), [13.2](requirements.md#13.2)
  - References: specs/phase-5-cloudkit-sharing/design.md
