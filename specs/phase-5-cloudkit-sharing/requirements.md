# Requirements: Phase 5 — CloudKit Sharing

## Introduction

Phase 5 activates Scramble's multi-device coordination story by making each trip independently shareable via CloudKit. The trip's owner can invite other iCloud users to participate from inside Trip Detail, accepted shares appear in each participant's Trip List, and all members can view and edit the trip's tasks, packing items, and attributes from their own devices. This phase performs the one-time data move deferred in Phase 1 Decision 9 (trip-owned records into per-trip custom zones), introduces `SchemaV3` to carry the denormalised person identity participants need, and lands the minimal CloudKit subscription scaffolding required for cross-device updates to be observable.

## Non-Goals

- Sharing master lists (`MasterTaskItem`, `MasterPackingItem`) or the `Person` registry across iCloud accounts — every member keeps their own.
- Read-only or otherwise differentiated participant roles; every participant is equally privileged per design doc §4.
- Multiple owners per trip (a `CKShare` always has one root-record owner).
- Public link-based sharing; invitations always target identified iCloud users via the system share sheet's options.
- Linking `Person` entries to iCloud users (deferred per design doc Future Improvements; remains so).
- A separate sharing surface outside Trip Detail (e.g., from Trip List or Settings).
- A "Shared with me" tab or any segregation of owned-vs-participating trips in the Trip List — they appear together.
- User-facing notifications announcing share events (acceptance, removal, revocation) — covered in Phase 6. Phase 5 ships the silent-push subscription plumbing only.
- A conflict-resolution UI for concurrent edits; CloudKit's last-writer-wins per attribute is accepted as-is.
- Family Sharing integration.
- macOS sharing surfaces.
- Promoting trip-level items to the master list as part of sharing.
- Cross-cutting iCloud account-lifecycle behaviour beyond what Phase 5 directly requires (account-change-between-launches handling, multi-account caches, account-status migration banners) — out of scope and noted for a future cross-cutting spec.

## Cross-phase preliminaries

### Roles

- **Owner** — the iCloud user whose device created the trip and who owns the trip's CloudKit zone and `CKShare`. There is exactly one owner per trip.
- **Participant** — an iCloud user who has accepted the trip's share. The owner is not a participant of their own trip.
- **Member** — either an owner or a participant. Used when a requirement applies to anyone with access.

### Zone vocabulary

- **Default zone** — the user's private database default zone where all v1 data currently lives.
- **Trip zone** — a custom CloudKit zone owned by the trip's owner that contains exactly one `Trip` record plus all of its `TripTask`, `TripPackingItem`, and per-trip identity-snapshot records.
- **Globals zone** — the zone (default zone or a dedicated custom zone, design's call) that holds per-user data not associated with any single trip: `Person` registry, `MasterTaskItem`, `MasterPackingItem`. Never participates in any `CKShare`.

### Trip ownership and visibility

A member sees a trip in their Trip List if and only if (a) they own that trip's zone, or (b) they have accepted the share for that zone. Master lists and the Person registry are private to each member and are never visible to other members.

### Person-identity terminology

This spec distinguishes three things that are easy to conflate:

- **`Person`** — a SwiftData entity in a member's globals zone. Owns master packing items. Private per member.
- **Person snapshot** — denormalised identity (name, colour, initial source) carried inside a trip zone so participants can render the trip without access to the owner's globals zone. Lives somewhere inside the trip zone (exact data-model placement is a design call constrained by Req [3.1](#3.1)).
- **Participant** — a CloudKit identity (CKShare.Participant). Identifies an iCloud user, not a packing-list owner. Surfaced in the trip's Participants section per Req [6](#6-participant-management-surface).

`Person` and Participant are distinct concepts and the UI keeps them visually separate (Req [6.7](#6.7)).

## Requirements

### 1. Per-trip share model

**User Story:** As a trip owner, I want each trip to be shared independently, so that I can invite different people to different trips.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL associate exactly one `CKShare` with each trip.  
2. <a name="1.2"></a>The system SHALL place each trip's `Trip` record, its `TripTask` records, its `TripPackingItem` records, and its person-snapshot records in a CloudKit zone dedicated to that trip and to no other trip.  
3. <a name="1.3"></a>WHEN a participant accepts a trip's share AND the trip's zone has been fetched into local storage, the trip SHALL appear in that participant's Trip List with the same name, dates, attributes, tasks, packing items, and participants the owner sees.  
4. <a name="1.4"></a>WHEN the owner deletes the trip, the system SHALL delete the trip's zone and revoke its share, and the trip SHALL disappear from each participant's Trip List on the next zone-deletion notification or on next launch, whichever comes first.  
5. <a name="1.5"></a>The app code SHALL NOT attempt to create a second `CKShare` for a trip that already has one; share-attempts on an already-shared trip route to manage-participants per Req [4.3](#4.3).  

### 2. Schema version `V3` and persisted person identity

**User Story:** As a member viewing a shared trip, I want every person, name, and colour on the trip to render correctly without access to the owner's master data, so that the trip is self-contained.

**Acceptance Criteria:**

1. <a name="2.1"></a>The system SHALL introduce `SchemaV3` (per the Phase 3 versioned-schema policy) and SHALL provide a lightweight migration stage from `SchemaV2` to `SchemaV3` in `AppMigrationPlan`.  
2. <a name="2.2"></a>`SchemaV3` SHALL persist enough denormalised person identity inside each trip zone for any participant to render that trip's avatars, names, person colours, and progress bars without consulting their globals zone.  
3. <a name="2.3"></a>WHEN the owner edits a `Person` (rename, colour change), the system SHALL update the corresponding person-snapshot inside every trip zone where that person participates, on the next applicable trigger; eventual consistency for participants is acceptable.  
4. <a name="2.4"></a>WHEN a `Person` is removed from a trip's `participants`, the corresponding person-snapshot SHALL be removed in the same transaction IF no `TripPackingItem` in that trip references it; otherwise it SHALL remain until the last referring `TripPackingItem` is removed, at which point it SHALL be cleaned up.  
5. <a name="2.5"></a>Reads of person identity from any UI surface (Trip List rows, Trip Detail header, Packing Sheet, WhyDisclosure header) SHALL resolve through the per-trip person-snapshot for shared trips and SHALL NOT cross zone boundaries.  

### 3. Globals-zone strategy

**User Story:** As a member of a shared trip, I want my own master lists and people to remain private, so that what I share with one trip does not leak into another person's app.

**Acceptance Criteria:**

1. <a name="3.1"></a>The system SHALL keep `Person`, `MasterTaskItem`, and `MasterPackingItem` records visible only to the iCloud user who created them; these records SHALL never be associated with any `CKShare`.  
2. <a name="3.2"></a>The system SHALL store `masterItemID` on shared `TripTask` and `TripPackingItem` records as plain UUIDs that do not require resolution against the receiving participant's globals zone.  
3. <a name="3.3"></a>WHEN a participant opens a shared trip whose `TripTask` or `TripPackingItem` records carry a `masterItemID` for a master record that does not exist in the participant's globals zone, the system SHALL render the item normally and the WhyDisclosure affordance SHALL be hidden for that item (not present in the layout).  
4. <a name="3.4"></a>The system SHALL NOT propagate edits made to a member's master lists to any other member.  
5. <a name="3.5"></a>The system SHALL NOT propagate `Person` registry edits made by one member to any other member's globals zone, except through the trip-scoped person-snapshot mechanism in Req [2.3](#2.3).  

### 4. One-time zone migration for existing trips

**User Story:** As an existing user upgrading to Phase 5, I want my trips to keep working with no data loss, so that I do not have to recreate anything.

**Acceptance Criteria:**

1. <a name="4.1"></a>WHEN the app launches with an on-device store created by a pre-Phase-5 build, the system SHALL move each trip and its trip-owned records (`TripTask`, `TripPackingItem`, plus any `SchemaV3` person-snapshot data introduced for that trip) from the default zone into a newly created trip zone.  
2. <a name="4.2"></a>The migration SHALL be atomic per trip: a trip's records SHALL either all complete the move into its trip zone or all remain in their pre-migration state for that trip; no trip SHALL ever exist with records partially split across zones.  
3. <a name="4.3"></a>The migration SHALL complete (success or per-trip failure) before any trip is interactable from the Trip List; trips already in trip zones SHALL be interactable as soon as their per-trip migration step terminates.  
4. <a name="4.4"></a>IF migration fails for any trip, the system SHALL log the failure with `modelLogger.error`, leave that trip in its pre-migration state, allow successfully migrated trips to be used, and surface a retryable error banner on the Trip List for the affected trips.  
5. <a name="4.5"></a>The migration SHALL preserve every field on every migrated record exactly, including (but not limited to) `masterItemID`, `currentlyMatchesRules`, `pinnedByUser`, `userDeletedOnThisTrip`, `state`, `isCompleted`, `assigneePersonID`, and `name`. As the one explicit transformation (not a preservation), the migration SHALL also rewrite `Trip.participants` and `TripPackingItem.person` from direct `Person` references to the `SchemaV3` person-snapshot entity per Reqs [2.2](#2.2) and [2.5](#2.5), seeding snapshot rows from the corresponding owner-side `Person` records.  
6. <a name="4.6"></a>The migration SHALL be idempotent: it SHALL be safe to invoke any number of times, and it SHALL terminate when every trip is in either the migrated or the failed-and-flagged terminal state.  
7. <a name="4.7"></a>WHEN the app is killed mid-migration, the system SHALL resume migration on next launch from a persisted journal of in-progress trips and SHALL converge to the same end state as a single uninterrupted run; no record SHALL be lost or duplicated.  
8. <a name="4.8"></a>The user-visible modality of the in-progress migration is a design choice (e.g., launch-blocking spinner vs. per-trip placeholder rows); the requirement is that the user SHALL NOT observe a trip in two zones simultaneously and SHALL NOT be able to edit a trip whose own per-trip migration step has not terminated.  
9. <a name="4.9"></a>WHEN two of the owner's devices race the migration of the same trip, the resulting trip zone SHALL be deterministically identified (zone name derived from `Trip.id`) and the migration SHALL converge to a single end state with no duplicated records and no parallel zone; the coordination mechanism (e.g., CloudKit-visible claim record, CKSyncEngine state, or other) is a design choice constrained only by this convergence guarantee.  

### 5. Share invitation flow

**User Story:** As a trip owner, I want to invite people from inside the trip, so that adding collaborators feels like part of trip setup.

**Acceptance Criteria:**

1. <a name="5.1"></a>The Trip Detail header SHALL display a Share affordance only WHEN the current user is the trip's owner.  
2. <a name="5.2"></a>WHEN the owner taps Share on a trip that has never been shared, the system SHALL create the trip's `CKShare` with read-write permissions for all invitees and present the system share-invite sheet.  
3. <a name="5.3"></a>WHEN the owner taps Share on a trip that already has a share, the system SHALL present the system manage-participants sheet for the existing share without creating a new one.  
4. <a name="5.4"></a>The system SHALL present the unmodified system share sheet, neither adding nor removing options.  
5. <a name="5.5"></a>The system SHALL cancel share creation cleanly IF the owner dismisses the share sheet without sending an invite, leaving the trip's zone in its pre-share state.  
6. <a name="5.6"></a>The system SHALL NOT block the owner from continuing to edit the trip while the share sheet is open.  

### 6. Share acceptance flow

**User Story:** As an invitee, I want accepting a trip share to drop the trip into my Trip List, so that I do not have to do anything else to start collaborating.

**Acceptance Criteria:**

1. <a name="6.1"></a>The system SHALL handle inbound `CKShare.Metadata` delivered through the standard scene share-acceptance entry point.  
2. <a name="6.2"></a>WHEN acceptance succeeds, the system SHALL accept the share, fetch the trip's zone contents, and insert the trip into the recipient's Trip List ordered per Phase 1 trip-list rules.  
3. <a name="6.3"></a>WHEN acceptance fails (network unavailable, share revoked, recipient signed out of iCloud), the system SHALL surface a non-blocking error alert with the underlying reason and SHALL NOT retain partial trip data.  
4. <a name="6.4"></a>WHEN the same share is accepted twice (e.g., from two devices, or after re-acceptance following a removal), the recipient's Trip List SHALL contain at most one row for that trip.  
5. <a name="6.5"></a>The recipient SHALL be able to leave the share from Trip Detail, after which the trip SHALL be removed from the recipient's local store on the next zone-removed notification or on next launch and the owner SHALL retain all trip data.  

### 7. Participant management surface

**User Story:** As a trip owner, I want to see and manage who is on the trip, so that I can revoke access when someone no longer needs it.

**Acceptance Criteria:**

1. <a name="7.1"></a>The Trip Detail screen SHALL display a Participants section listing every member of the trip's `CKShare`, identified by their iCloud display name when available, by their email if no display name is set, or by the literal string "Invited participant" if neither is yet known.  
2. <a name="7.2"></a>The Participants section SHALL distinguish pending invitees from accepted participants with a visible label.  
3. <a name="7.3"></a>WHEN the current user is the owner, tapping a participant or pending invitee SHALL open the system manage-participants sheet pre-focused on that entry, exposing the standard remove and re-invite affordances.  
4. <a name="7.4"></a>WHEN the current user is a participant, the Participants section SHALL be read-only and SHALL NOT expose remove or re-invite affordances for any member.  
5. <a name="7.5"></a>WHEN a participant is removed by the owner, the trip SHALL disappear from the removed participant's Trip List on the next CloudKit notification or on next launch, and the owner SHALL retain all trip data unchanged.  
6. <a name="7.6"></a>The Participants section SHALL refresh its membership list when the share metadata changes; the trigger is design's call (notification, fetch on view appear, or both).  
7. <a name="7.7"></a>Participants are CloudKit identities and SHALL NOT be conflated with `Person` entities used for packing-list ownership; the Participants section SHALL be presented as a distinct UI region from any `Person`-related affordance on Trip Detail.  
8. <a name="7.8"></a>WHILE a participant's CloudKit display name is still being fetched, the row SHALL render a placeholder (e.g., "Loading…") rather than an empty string or a misleading email-shaped string; once the name resolves, the row SHALL update without user interaction.  

### 8. Cross-device race handling and engine ownership

**User Story:** As a member of a shared trip, I want concurrent edits from other devices to land sensibly, so that I do not see broken or missing data.

**Acceptance Criteria:**

1. <a name="8.1"></a>WHEN two members concurrently toggle the same `TripTask.isCompleted` or `TripPackingItem.state`, the system SHALL accept CloudKit's last-writer-wins resolution and SHALL NOT surface a conflict prompt.  
2. <a name="8.2"></a>WHEN a member deletes a `Person` who is referenced by a shared trip's records on another member's device, the system SHALL apply the existing dangling-reference rule (consistent with Phase 1 Decisions 15 and 16): items remain visible and dimmed; no crash; no automatic deletion. The trip-zone person-snapshot satisfies the read path; the local-globals `Person` is not required for rendering.  
3. <a name="8.3"></a>The rules engine `compute → diff → apply` step SHALL run only on the device whose user owns the trip's zone; it SHALL be a no-op for trips owned by another iCloud user.  
4. <a name="8.4"></a>The rules engine SHALL NEVER mutate a record where `pinnedByUser == true`, where `userDeletedOnThisTrip == true`, or where `source == .manual`. This invariant holds in all sync scenarios and is the contract participants rely on when editing trip-owned records.  
5. <a name="8.5"></a>Participants SHALL be able to add, edit, complete, pack, repack, exclude, pin/unpin, and `userDeletedOnThisTrip`-mark any trip-owned record per the existing UI affordances; only the engine's auto-population step is owner-only.  
6. <a name="8.6"></a>WHEN a participant edits a trip attribute, the system SHALL accept and propagate the edit. The Phase 2 engine-trigger list (trip created, trip attributes edited, master item edited, app launch) SHALL be extended in `SchemaV3` with a new trigger: "CloudKit-received change to a trip-owned record on the owner's device". The owner's device SHALL re-run the engine on the next applicable trigger after receiving the change.  
7. <a name="8.7"></a>`pinnedByUser` and `userDeletedOnThisTrip` SHALL be trip-global in v1 (toggled by any member, visible to all members on next sync). They are not per-member flags. The rationale is that a trip is a shared object; per-member overrides would require a participant-keyed sub-schema not justified by the design doc.  
8. <a name="8.8"></a>Trip Detail SHALL render a "Rules last evaluated {relative-time}" line in the trip header subline whenever the current user is a participant (not the owner); the line SHALL update whenever the owner's device emits a new engine run, and the relative-time format SHALL match Phase 1's existing date-formatting conventions. For owner-viewed trips, the line SHALL be omitted.  
9. <a name="8.9"></a>Participants SHALL NOT add, remove, or edit `Person` entities on a shared trip; the trip's people roster is managed only by the owner via the Phase 1 trip editor. The CloudKit Participants surface (Req [7](#7-participant-management-surface)) is distinct from the trip's people roster and SHALL NOT be conflated with it.  

### 9. CloudKit subscriptions for shared trips

**User Story:** As a member of a shared trip, I want changes from other devices to appear without me having to reopen the app, so that the trip stays in sync.

**Acceptance Criteria:**

1. <a name="9.1"></a>WHEN a participant accepts a share, the system SHALL register a CloudKit subscription for that trip's zone in the shared database.  
2. <a name="9.2"></a>WHEN an owner creates a new trip's zone, the system SHALL register a CloudKit subscription for that zone in the private database.  
3. <a name="9.3"></a>The subscriptions SHALL be silent (no user-visible notification) and SHALL trigger a CloudKit fetch that updates local state on receipt; user-visible notifications are deferred to Phase 6.  
4. <a name="9.4"></a>WHEN a participant leaves a share or is removed, the system SHALL unregister that trip's subscription on the next opportunity; an orphaned subscription that is unable to be unregistered SHALL NOT block normal app operation.  
5. <a name="9.5"></a>Subscription registration failures SHALL be logged and SHALL NOT block the share-acceptance or trip-creation flow; the trip remains functional, falling back to fetch-on-foreground semantics until the next subscription-registration attempt succeeds.  

### 10. Trip ownership identification

**User Story:** As any member, I want the app to know whether I own or merely participate in each trip, so that owner-only and participant-only behaviours apply correctly.

**Acceptance Criteria:**

1. <a name="10.1"></a>The system SHALL identify the owner of a trip as the iCloud user who owns the trip's CloudKit zone.  
2. <a name="10.2"></a>WHEN the current user is the owner, the Share affordance, manage-participants control, and rules-engine triggers SHALL be enabled per Reqs [5](#5-share-invitation-flow), [7](#7-participant-management-surface), and [8](#8-cross-device-race-handling-and-engine-ownership).  
3. <a name="10.3"></a>WHEN the current user is a participant, the Share affordance and manage-participants control SHALL be hidden and the rules engine SHALL be a no-op for that trip.  
4. <a name="10.4"></a>Ownership checks SHALL be synchronous and SHALL perform no I/O; they SHALL be safe to invoke per UI render and per engine trigger.  

### 11. Failure and offline behaviour

**User Story:** As a member, I want the app to keep working when CloudKit is unavailable, so that I can still see and edit trips offline.

**Acceptance Criteria:**

1. <a name="11.1"></a>WHEN CloudKit is unreachable, the app SHALL allow members to view and edit trips that are already cached locally; changes SHALL queue and sync when connectivity returns.  
2. <a name="11.2"></a>WHEN the owner attempts to share a trip while offline, the system SHALL surface a "Network required to share" message and SHALL NOT modify the trip or its share state.  
3. <a name="11.3"></a>WHEN the iCloud account is signed out at app launch, the app SHALL fall back to the existing local-only `ModelStore` fallback from Phase 1, SHALL hide the Share affordance entirely, and SHALL NOT attempt the Phase 5 zone migration.  
4. <a name="11.4"></a>WHEN a CloudKit operation returns a `CKError` that CloudKit's standard guidance classifies as transient, quota-related, or conflict-related, the system SHALL log via `modelLogger.error` and SHALL surface a user-visible error only WHEN the failure blocks a user-initiated action (share, accept, leave); background sync errors SHALL be retried per CloudKit's standard backoff and SHALL NOT surface UI noise. The exact `CKError` cases mapped to each category are a design-phase choice; this requirement constrains only the surfacing policy.  

### 12. Testability of CloudKit-dependent behaviour

**User Story:** As a developer, I want the sharing flow to be testable in CI, so that regressions are caught before TestFlight.

**Acceptance Criteria:**

1. <a name="12.1"></a>The system SHALL expose CloudKit-sharing operations (share creation, acceptance, participant fetch, subscription registration, ownership lookup, zone migration) through an injectable seam that production code wires to CloudKit and that tests wire to a controllable fake.  
2. <a name="12.2"></a>The acceptance criteria in this spec that reference "the next CloudKit fetch / notification / sync" SHALL be considered satisfied by the corresponding test-seam event being delivered to the receiver under test; CI tests SHALL NOT depend on real CloudKit reachability.  
3. <a name="12.3"></a>Phase 1's existing test-environment branches in `EnvironmentProbe` SHALL continue to route tests to in-memory storage; the Phase 5 seam SHALL be wired such that tests get the fake even when other branches (`isPreview`, `isUITestHost`, `isTest`) would also apply.  

### 13. CloudKit production schema deployment

**User Story:** As a release engineer, I want the production CloudKit schema to be promoted before the Phase 5 build ships, so that real users do not hit "schema not deployed" errors on first launch.

**Acceptance Criteria:**

1. <a name="13.1"></a>Before the Phase 5 build is released to TestFlight or the App Store, the new CloudKit record types and zone topology introduced by `SchemaV3` SHALL be promoted from the Development environment to the Production environment via the CloudKit Dashboard.  
2. <a name="13.2"></a>The release-prep checklist (or its equivalent in this repo) SHALL include this promotion step explicitly so it is not skipped.  
