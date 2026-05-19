# Requirements: Phase 5.1 — Wire Trip CRUD through `tripsLocal`

## Introduction

Phase 5 landed every piece of the CloudKit sharing infrastructure (dual SwiftData containers, `TripSyncEngine`, translators, `LocalWriteHook`, `SnapshotMaintenance`, `TripDeletion`, `ZoneMigrationCoordinator`, `CloudKitSharingService`, and Stage A/B migration journals) but the SwiftUI view layer still reads and writes against the `globals` container. Phase 5.1 routes Trip-domain reads and writes through the `tripsLocal` container so the Phase 5 sync pipeline actually carries edits and shares to other devices. Sharing functionality is observably broken today — accepting a share never lists the trip, and owner edits never reach the trip zone — and these requirements describe the user-facing outcomes that must hold once the wiring is closed, alongside the persistence-layer invariants that make the wiring correct.

## Terminology

- **Trip-domain entity** — any of `Trip`, `TripTask`, `TripPackingItem`, `TripPersonSnapshot`, `TripZoneState`, `MigrationJournalEntry`.
- **Globals entity** — any of `Person`, `MasterTaskItem`, `MasterPackingItem`.
- **`tripsLocal`** / **`globals`** — the two SwiftData containers established in Phase 5 (see Phase 5 design § "Dual ModelContainer split"). Trip-domain entities live in `tripsLocal`; globals entities live in `globals`.
- **`LocalWriteHook`** — the single dirty-marking chokepoint for `tripsLocal` saves (see Phase 5 design § "Single dirty-marking chokepoint"). Inspects pending changes, ORs flags into the matching `TripZoneState.pendingUploadFlags`, saves the context, and notifies the engine.
- **Local commit** — a successful `LocalWriteHook.commit(_:)` against the `tripsLocal` context.
- **Cross-store consistency boundary** — the invariant that no UI query observes a single trip's records simultaneously present in both stores or partially present in neither.
- **Eventual consistency window** — the time between a local commit and the corresponding `CKSyncEngine` `sendChanges` completion event.

## Non-Goals

- New user-facing UI surfaces beyond the offline-share affordance in Req [8](#8-sharing-surfaces-fail-visibly-when-offline). Phase 5.1's user-visible effect is that previously-broken cross-device sync now functions.
- Changes to the on-disk shape of `SchemaV3` or the introduction of `SchemaV4`. The V2-era `Trip.participants → Person` and `TripPackingItem.person → Person` relationships persist at the model level and are deliberately left in place; Phase 5.1 makes them unreachable from production read paths, leaving a latent landmine that a future `SchemaV4` cleanup is expected to remove. The risk is acknowledged in [decision_log.md Decision 2](decision_log.md).
- Changes to the contract or behaviour of `CKSyncEngine` event delivery, the translator layer, or the shape of `PendingUploadFlags`.
- Differential roles for participants, public-link sharing, sharing master lists, or any other capability already non-goaled in `phase-5-cloudkit-sharing/requirements.md`.
- Background sync triggers beyond what Phase 5 already wires (silent push, app launch, scene activation).
- Conflict-resolution UI for concurrent edits; CloudKit's last-writer-wins per attribute remains accepted.
- macOS UI work.
- A static lint rule preventing direct `context.save()` against `tripsLocal`. Enforcement is via the contract test described in Req [2.5](#2.5) instead. SwiftLint integration is a future improvement, not a Phase 5.1 deliverable.
- Cleanup of CloudKit zones orphaned by a successful local trip-deletion that failed to delete the remote zone. Req [5.5](#5.5) requires the failure to be surfaced; the cleanup retry is deferred to a future phase.

## Constraints / Invariants

These hold for the lifetime of Phase 5.1 and beyond. They are not event-driven and therefore not in EARS form.

- <a name="C1"></a>**C1** Trip-domain entities are persisted in `tripsLocal`; globals entities are persisted in `globals`. No Trip-domain entity is persisted in `globals` and no globals entity is persisted in `tripsLocal`, except transiently during the relocation step described in Req [4](#4-existing-trips-relocate-from-globals-to-tripslocal-on-first-phase-51-launch).
- <a name="C2"></a>**C2** No SwiftUI query SHALL observe a single trip's records simultaneously present in `globals` and `tripsLocal`, or partially absent from both. The cross-store consistency boundary is maintained by the relocation journal (Req [4.5](#4.5)) and by the in-transaction reverse-cascade ordering of the deletion path (Req [5.1](#5.1)).
- <a name="C3"></a>**C3** Trip-domain SwiftUI views SHALL NOT traverse the V2-era `Trip.participants → Person` or `TripPackingItem.person → Person` relationships from the `tripsLocal` context, because those traversals span containers and are unsupported. Identity for roster members and packing-item owners is read from `TripPersonSnapshot`.
- <a name="C4"></a>**C4** A trip-domain write that requires upload is uploaded if and only if the affected records are recorded as dirty in the trip's `TripZoneState.pendingUploadFlags`. Writes that bypass the dirty-marking step are silently lost to other devices; the contract test in Req [2.5](#2.5) prevents this regression.

## Requirements

### 1. Trip-domain edits made on one device become visible on every device that shares the trip

**User Story:** As an iCloud user, I want my trip edits to reach other devices that share the trip, so that planning stays in sync.

**Acceptance Criteria:**

1. <a name="1.1"></a>WHEN an owner edits a trip-domain entity from any SwiftUI surface, the system SHALL persist the change to `tripsLocal` and SHALL queue the affected records on the trip's `TripZoneState.pendingUploadFlags` so the sync engine uploads them within the eventual consistency window.  
2. <a name="1.2"></a>WHEN the upload in [1.1](#1.1) completes, every other device with access to the trip SHALL observe the edit on its next `CKSyncEngine` fetch event, without requiring an app restart on that device.  
3. <a name="1.3"></a>WHEN a participant edits a trip-domain entity from any SwiftUI surface on their device, the system SHALL persist the change to `tripsLocal`, queue the affected records for upload to the shared database, and the owner SHALL observe the edit on the owner's next `CKSyncEngine` fetch event, without requiring an app restart.  
4. <a name="1.4"></a>WHEN a user creates a new trip, the trip SHALL appear in the Trip List of the creating device within the same SwiftUI render cycle as the local commit and SHALL remain in the Trip List after the app is relaunched.  
5. <a name="1.5"></a>WHEN a user creates a new trip, the first subsequent edit to that trip SHALL upload to a CloudKit zone keyed to the trip and SHALL NOT be dropped on the floor; this implies the `TripZoneState` row required to record dirty flags has been created by the time the first edit's local commit returns.  
6. <a name="1.6"></a>WHEN a trip-domain write fails (validation, storage error, or `LocalWriteHook` rejection), the system SHALL leave the `tripsLocal` store in its pre-write state for that operation, SHALL NOT mutate `pendingUploadFlags` for that operation, and SHALL surface the failure to the originating SwiftUI surface via its existing error path.  

### 2. Trip-domain writes pass through the dirty-marking chokepoint

**User Story:** As a future contributor adding a new Trip-feature view, I want the persistence layer to reject any save path that would silently fail to propagate, so that I cannot re-introduce the Phase 5.1 bug.

**Acceptance Criteria:**

1. <a name="2.1"></a>WHEN any Trip-feature SwiftUI surface commits a change to `tripsLocal`, the commit SHALL pass through `LocalWriteHook.commit(_:)` so dirty-marking and the per-commit single-save invariant are honoured.  
2. <a name="2.2"></a>WHEN the rules engine writes Trip-domain records as part of a run, those writes SHALL pass through `LocalWriteHook.commit(_:)` so the engine's outputs propagate to other devices on the same terms as user writes.  
3. <a name="2.3"></a>WHEN `SnapshotMaintenance` updates or deletes `TripPersonSnapshot` rows, the writes SHALL pass through `LocalWriteHook.commit(_:)`.  
4. <a name="2.4"></a>WHEN `TripDeletion` removes a trip and its dependents, the removal SHALL pass through `LocalWriteHook.commit(_:)` (the hook handles the per-record deleted-flag marking).  
5. <a name="2.5"></a>A contract test SHALL exist in `ScrambleTests` that fails the build if any production source file under `Scramble/Scramble/` (excluding `LocalWriteHook.swift` itself) contains a `modelContext.save()` or `context.save()` call site on a context known by name to bind to `tripsLocal`. The test SHALL operate by source-pattern scanning the file set with a documented false-positive escape (an in-source `// LocalWriteHookContract: allow` marker on the offending line) for the rare case where a direct save is intentional and reviewed.  

### 3. Globals data remains private to each user

**User Story:** As a member of a shared trip, I want my own master lists and people to stay private, so that what I share with one trip does not leak into another person's app.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHEN a user creates, edits, or deletes a globals entity from any SwiftUI surface, the system SHALL persist the change to `globals` only and the change SHALL NOT become visible on any other iCloud user's device.  
2. <a name="3.2"></a>WHEN a user views the Master Lists tab or the People picker in the Trip Editor, the records shown SHALL be those of the current user's `globals` store.  
3. <a name="3.3"></a>WHEN a participant opens a shared trip whose `TripTask` or `TripPackingItem` carries a `masterItemID` for a master record absent from the participant's `globals` store, the system SHALL render the item normally (name, state, person snapshot) and the `WhyDisclosure` affordance SHALL be hidden for that item.  

### 4. Existing trips relocate from `globals` to `tripsLocal` on first Phase 5.1 launch

**User Story:** As an existing user upgrading to Phase 5.1, I want my pre-existing trips to keep working and become shareable, so that I don't lose data and don't have to recreate anything.

**Acceptance Criteria:**

1. <a name="4.1"></a>WHEN the app launches against an on-device store created by a pre-Phase-5.1 build, the system SHALL relocate each `Trip` together with its `TripTask`, `TripPackingItem`, and `TripPersonSnapshot` records from `globals` into `tripsLocal`.  
2. <a name="4.2"></a>The relocation SHALL preserve every persisted field on every relocated record exactly, including `id`, `masterItemID`, `currentlyMatchesRules`, `pinnedByUser`, `userDeletedOnThisTrip`, `state`, `isCompleted`, `assigneePersonID`, `name`, `ckRecordSystemFields`, and all Codable-blob fields. The relocation SHALL NOT alter the V2-era `Trip.participants` or `TripPackingItem.person` values; the persisted person identity that trip-domain views read is the corresponding `TripPersonSnapshot` (already created by Phase 5 Stage A).  
3. <a name="4.3"></a>The relocation for each trip SHALL be atomic within each store: every record for that trip SHALL be inserted into `tripsLocal` and committed before any record is deleted from `globals` for that trip, and the deletion SHALL be committed in a single `globals` save.  
4. <a name="4.4"></a>WHEN relocation is in progress for a trip, no SwiftUI query SHALL observe that trip's records in both `tripsLocal` and `globals` simultaneously or absent from both; in-progress trips SHALL be hidden from the Trip List until their relocation reaches a terminal state.  
5. <a name="4.5"></a>The relocation SHALL be resumable from the `MigrationJournalEntry` state:  
   - IF the `tripsLocal` insert-and-commit step (4.3 step 1) did not complete, the system SHALL roll back by removing any partial inserts from `tripsLocal` and SHALL re-attempt the relocation from the beginning.  
   - IF the `tripsLocal` insert-and-commit step completed but the `globals` delete-and-commit step (4.3 step 2) did not, the system SHALL resume by deleting the records from `globals`.  
   - IF both steps completed, the system SHALL treat the relocation as already done (per 4.6).  
   On completion of any branch, the trip SHALL satisfy [4.4](#4.4).  
6. <a name="4.6"></a>The relocation SHALL be idempotent: running it again after completion SHALL leave both stores unchanged for trips already relocated.  
7. <a name="4.7"></a>WHEN the app launches signed out of iCloud, the local relocation in [4.1](#4.1)–[4.6](#4.6) SHALL still complete and the relocated trips SHALL be interactable in the Trip List; CloudKit zone creation, share establishment, and Stage B upload (gated by Phase 5 Req 11.3) remain deferred until a launch with iCloud available.  
8. <a name="4.8"></a>WHEN the user subsequently signs in to iCloud after a signed-out relocation, the system SHALL drive Stage B (zone creation + record upload) for every relocated trip whose `MigrationJournalEntry` has not yet reached `.completed`, and the Trip List "Syncing" badge SHALL clear per Phase 5 Req 4.8 as each entry reaches a terminal state.  
9. <a name="4.9"></a>The `TripPersonSnapshot` rows that Phase 5 Stage A created in `tripsLocal` against the pre-Phase-5.1 (empty) production state SHALL be retroactively marked dirty in their trip's `TripZoneState.pendingUploadFlags` at the moment that trip enters Stage B, so the snapshots upload alongside the trip's first relocation pass.  
10. <a name="4.10"></a>WHEN relocation completes for a trip, the trip's `MigrationJournalEntry` SHALL transition per the journal contract in `phase-5-cloudkit-sharing/`. IF relocation fails, the entry SHALL transition to `.failed` with an error message and a retryable affordance SHALL be surfaced per Phase 5 Req 4.4.  

### 5. Owner-side trip deletion cleans up local and remote state

**User Story:** As a trip owner, I want deleting a trip to remove every trace of it locally and remotely, so that other devices stop showing the trip and nothing lingers in CloudKit.

**Acceptance Criteria:**

1. <a name="5.1"></a>WHEN an owner deletes a trip from any SwiftUI surface, the system SHALL remove that trip and every `TripTask`, `TripPackingItem`, `TripPersonSnapshot`, and `TripZoneState` belonging to the trip from `tripsLocal` in one local commit, following the reverse-cascade order documented in Phase 5 design § "Trip deletion ordering".  
2. <a name="5.2"></a>WHEN the local commit in [5.1](#5.1) succeeds, the system SHALL request deletion of the trip's CloudKit zone and revocation of its share via the `TripSyncEngine` pending-database-changes path.  
3. <a name="5.3"></a>WHEN the local commit in [5.1](#5.1) fails, the system SHALL leave `tripsLocal` in its pre-deletion state and SHALL NOT issue the CloudKit operation in [5.2](#5.2).  
4. <a name="5.4"></a>WHEN deletion succeeds locally, the trip SHALL disappear from the deleting user's Trip List within the same SwiftUI render cycle as the local commit.  
5. <a name="5.5"></a>WHEN the CloudKit operation in [5.2](#5.2) fails (network unreachable, quota, throttling), the system SHALL log the failure via `modelLogger.error`, SHALL NOT roll back the local deletion, and SHALL surface a "trip removed locally; cloud cleanup incomplete" status on the Trip List for the affected trip using the existing migration-banner affordance. The system SHALL retransmit the zone-deletion request on the next `CKSyncEngine` retry cycle until it succeeds or the user dismisses the banner; explicit orphan cleanup beyond this retry loop is non-goaled in Phase 5.1.  

### 6. Snapshot maintenance runs as a side effect of relevant user actions

**User Story:** As a participant on a shared trip, I want avatars, names, and person colours to stay current with the owner's edits, so that the trip reads correctly on my device.

**Acceptance Criteria:**

1. <a name="6.1"></a>WHEN an owner renames a `Person` or changes their colour, the system SHALL update the corresponding `TripPersonSnapshot` in every owned trip where that person participates and SHALL mark each updated snapshot dirty for upload (via [2.3](#2.3)).  
2. <a name="6.2"></a>WHEN an owner removes a `Person` from a trip's roster, the system SHALL remove the corresponding `TripPersonSnapshot` from that trip in the same local commit IF no `TripPackingItem` in that trip references it; otherwise the snapshot SHALL remain until the last referring `TripPackingItem` is removed, at which point the snapshot SHALL be removed.  
3. <a name="6.3"></a>WHEN an owner deletes the last `TripPackingItem` referencing a non-roster `TripPersonSnapshot`, the system SHALL remove that snapshot in the same local commit as the packing-item deletion.  
4. <a name="6.4"></a>WHEN the rules engine completes a run for an owned trip, the system SHALL sweep that trip's `TripPersonSnapshot` rows and remove any that are unreferenced by both the trip roster and any `TripPackingItem`, via [2.3](#2.3).  
5. <a name="6.5"></a>Snapshot maintenance in [6.1](#6.1)–[6.4](#6.4) SHALL run only for trips the current user owns. Participant-side trips SHALL leave snapshot rows unchanged on these triggers.  

### 7. Sync engine events drive migration-journal progress

**User Story:** As a user with a freshly migrated trip, I want the "Syncing" badge to disappear once the trip has actually finished uploading, so that the UI reflects real state.

**Acceptance Criteria:**

1. <a name="7.1"></a>WHEN the sync engine confirms the trip's CloudKit zone has been saved, the system SHALL advance the corresponding `MigrationJournalEntry` toward completion per the journal contract in `phase-5-cloudkit-sharing/`.  
2. <a name="7.2"></a>WHEN the sync engine confirms the records expected for a trip have been saved, the system SHALL advance that trip's journal entry toward completion per the journal contract.  
3. <a name="7.3"></a>WHEN the sync engine reports a failure for one or more records belonging to a trip in `.stageBInProgress`, the system SHALL transition that trip's journal entry to `.failed` with the failure message and SHALL surface the retryable affordance per Phase 5 Req 4.4.  
4. <a name="7.4"></a>WHEN a `.failed` journal entry is retried, the system SHALL re-run Stage B for that trip and the engine event handling in [7.1](#7.1)–[7.3](#7.3) SHALL apply to the retry attempt.  

### 8. Sharing surfaces fail visibly when offline

**User Story:** As a trip owner attempting to share, I want a clear "network required" message when offline, so that I don't think I have shared and watch nothing happen.

**Acceptance Criteria:**

1. <a name="8.1"></a>WHEN the user taps Share on a trip while the device cannot reach CloudKit, the system SHALL display a "network required to share" message and SHALL NOT mark the trip as shared locally.  
2. <a name="8.2"></a>WHEN network access becomes available and the user retries Share, the share creation SHALL proceed without requiring an app restart.  

### 9. Accepting a share lists the trip on the participant device

**User Story:** As a participant who has accepted a trip share, I want the trip to appear in my Trip List, so that I can open and edit it from my device.

**Acceptance Criteria:**

1. <a name="9.1"></a>WHEN a participant accepts a trip share and the share's zone has been fetched into local storage, the trip SHALL appear in that participant's Trip List with the same name, dates, attributes, tasks, packing items, and participants the owner sees, within the SwiftUI render cycle following the fetch completion event.  
2. <a name="9.2"></a>WHEN the owner subsequently edits the trip, the participant SHALL see the edits applied on their device on the next `CKSyncEngine` fetch event, without an app restart.  
3. <a name="9.3"></a>WHEN the owner revokes the share or the participant leaves the share, the system SHALL remove the trip from the participant's Trip List on the next zone-deletion notification or on next launch, whichever comes first; the participant's `tripsLocal` SHALL no longer contain the trip's records after this.  

### 10. Cross-container reads from trip-domain views render predictably

**User Story:** As a user browsing trips, I want every screen that displays person identity or master-item provenance to render correctly, so that shared and unshared trips both look right.

**Acceptance Criteria:**

1. <a name="10.1"></a>WHEN a trip-domain SwiftUI view needs the underlying `Person` record for a roster member, the system SHALL resolve it from `globals` by UUID; IF the lookup returns `nil`, the view SHALL render the avatar using the `TripPersonSnapshot`'s persisted name, initial, and colour without crash or visible glitch, and SHALL NOT block the rest of the view from rendering.  
2. <a name="10.2"></a>WHEN a trip-domain SwiftUI view needs the underlying `MasterTaskItem` or `MasterPackingItem` for an item carrying `masterItemID`, the system SHALL resolve it from `globals` by UUID; IF the lookup returns `nil`, the item SHALL render normally and the `WhyDisclosure` affordance SHALL be hidden per [3.3](#3.3), matching Phase 5 Req 3.3.  
3. <a name="10.3"></a>Per constraint [C3](#C3), trip-domain views do not traverse the V2-era `Trip.participants → Person` or `TripPackingItem.person → Person` relationships. A SwiftSyntax-based test in `ScrambleTests` SHALL parse every Swift source file in the trip-domain file set defined immediately below and SHALL fail the build if any file in that set contains a `MemberAccessExpr` matching `.participants` rooted in a value statically typed as `Trip`, or `.person` rooted in a value statically typed as `TripPackingItem`. The trip-domain file set is: every file under `Scramble/Scramble/Features/Trips/`, plus `Scramble/Scramble/Components/TaskListSection.swift` (the only trip-domain component today), plus any future file annotated with the marker comment `// trip-domain view`. The test uses SwiftSyntax type inference where available and falls back to receiver-type heuristics with a documented `// V2Relationship: allow` escape on the offending line.  
