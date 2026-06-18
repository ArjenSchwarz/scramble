# Decision Log: Phase 5 — CloudKit Sharing

## Decision 1: Feature name and spec scoping

**Date**: 2026-05-15
**Status**: accepted

### Context

The implementation-phases plan calls Phase 5 "CloudKit Sharing". The team has been naming spec directories `phase-N-<short-slug>` (see `specs/phase-1-foundation/`, `specs/phase-4-packing-sheet/`). A consistent slug helps tie the spec to the plan and to the eventual feature branch.

### Decision

Use `phase-5-cloudkit-sharing` as the feature name and spec directory.

### Rationale

Matches existing convention exactly. Branch name and PR title follow the same slug, so links from `docs/implementation-phases.md` to the spec, branch, PR, and merged commit all resolve trivially.

### Alternatives Considered

- **`phase-5-sharing`**: Shorter, but loses the "this is the CloudKit story" signal; sharing in v2 might cover non-CloudKit transports and reusing the slug would then be ambiguous.
- **`cloudkit-sharing`** (no phase prefix): Drops the phase ordering hint that has been useful for a young codebase still working through the linear plan.

### Consequences

**Positive:**
- Consistent with prior phase specs.
- Branch and spec slugs are identical.

**Negative:**
- Locks future "sharing" specs into the `phase-N-cloudkit-sharing-extensions` shape if they want to refer to the same area.

---

## Decision 2: Master lists and `Person` registry remain per-user, not shared

**Date**: 2026-05-15
**Status**: accepted

### Context

CKShare scopes sharing per zone. The trip-owned records (`TripTask`, `TripPackingItem`) clearly belong in a per-trip zone so each trip can be shared independently. The harder question is what to do with `Person`, `MasterTaskItem`, and `MasterPackingItem`: they're referenced (directly or by `masterItemID`) from trip-owned records, so a naïve cross-zone reference would break either sharing or rules-engine explainability.

### Decision

Keep `Person`, `MasterTaskItem`, and `MasterPackingItem` strictly private to each member's iCloud account. The shared trip carries enough denormalised identity (person name, colour, initial; item name snapshot; `masterItemID` UUID) for participants to render the trip without needing access to the owner's globals. The exact data-model placement of the person snapshot is a Decision-7 concern.

### Rationale

This preserves the existing snapshot semantics on `TripTask`/`TripPackingItem` (`name` is already a copy, not a live reference) and extends the same logic to `Person` identity surfaces. It avoids the gnarly cross-zone-relationship problem that NSPersistentCloudKitContainer does not support, keeps each member's master lists genuinely private, and makes "leave the share" a clean operation. The `masterItemID` UUID stays meaningful only on the owner's device — for participants it becomes an opaque tag, and Req [3.3](requirements.md#3.3) handles that by hiding the WhyDisclosure affordance.

### Alternatives Considered

- **Dedicated globals zone shared with all participants**: Would require either a per-pair share (combinatorial) or a global "everyone I've ever shared with" share (privacy-hostile, implies revealing the whole master list). Rejected.
- **Promote master items into trip zones at share time**: Bloats every trip with the entire master list and creates merge headaches when the master list changes after sharing.
- **Cross-zone references via `CKReference`**: Not supported by NSPersistentCloudKitContainer. Even if hand-rolled, would require coordinated zone fetches that defeat the per-trip share boundary.

### Consequences

**Positive:**
- Each user's master lists stay genuinely private.
- `MasterTaskItem` and `MasterPackingItem` schemas need no sharing-specific changes.
- Leaving a share has no spillover into the participant's globals.

**Negative:**
- Participants see no `WhyDisclosure` content for rule-driven items.
- Person identity is denormalised onto the trip; renaming a person on the owner's device requires explicit propagation to the per-trip snapshot (handled by Req [2.3](requirements.md#2.3)).

### Impact

Drives the Phase 5 design's split between "owner-side rules engine" and "participant-side render-only" behaviour, and forces [Decision 7](#decision-7-schemav3-introduces-a-per-trip-person-snapshot) (the schema commitment).

---

## Decision 3: Rules engine runs only on the owner's device

**Date**: 2026-05-15
**Status**: accepted

### Context

The rules engine uses `compute → diff → apply` against the user's master lists. With master lists private per [Decision 2](#decision-2-master-lists-and-person-registry-remain-per-user-not-shared), each member would compute a different "should-exist" set if they ran it. If multiple devices ran the engine concurrently against different masters, the diff/apply step would thrash trip-owned records unpredictably.

### Decision

The rules engine `compute → diff → apply` step runs only on the owner's device. Participants render whatever the owner's engine has produced and may freely edit, complete, pin, exclude, or add items, but their devices do not run rule re-evaluation against shared trips.

### Rationale

Single source of truth for auto-population eliminates the "whose master list wins" ambiguity, keeps the deterministic diffing semantics intact, and matches the design doc's stated goal of consistent behaviour across devices. The cost — that participants see no rule-driven update until the owner's device runs the engine — is a known v1 staleness window addressed by Req [8.8](requirements.md#8.8).

### Alternatives Considered

- **Each device runs the engine against its own masters**: Produces non-deterministic outcomes; thrashes records on every sync.
- **Engine runs on the device of whoever last edited any input**: Solves "whose masters" only if we also share masters, which Decision 2 already rejected.
- **Engine runs on a CloudKit Function or server**: Out of scope for v1.

### Consequences

**Positive:**
- Deterministic, drift-free behaviour across devices.
- Participants have a clear mental model: "what I see is what the trip owner's app produced."

**Negative:**
- A trip whose owner stops using the app stops receiving rule-driven updates even if participants are active. Acceptable for v1 (no transfer-of-ownership story).
- Adds an ownership gate at every rules-engine trigger that wasn't needed in Phase 2.
- Creates a participant-visible staleness window when the owner is offline; Req [8.8](requirements.md#8.8) requires the design phase to specify a UI indication of that staleness.

### Impact

Affects Phase 2 rules-engine integration points: every existing trigger (trip created, trip attribute edited, master item edited, app launch) gains an ownership gate, and the engine invariant in Req [8.4](requirements.md#8.4) becomes a load-bearing contract participants rely on.

---

## Decision 4: Migration is per-trip atomic and idempotent

**Date**: 2026-05-15
**Status**: accepted (supersedes earlier "launch-blocking" wording)

### Context

Phase 1 Decision 9 deferred moving trip-owned records from the default zone into per-trip custom zones. Phase 5 has to perform that move on every existing device exactly once, on first launch of the Phase 5 build. Initial drafts of these requirements over-prescribed the user-visible modality (a launch-blocking spinner). Reviews flagged the wording conflict between "at most once per device per upgrade" and the simultaneous demand for retry + resume.

### Decision

Migration runs at app launch; is per-trip atomic; is idempotent (safe to re-invoke until every trip is in a terminal migrated-or-failed state); resumes from a persisted journal after kill-mid-migration; and presents a user-visible interlock that prevents observation of the same trip in two zones at once. The exact UI modality (full-screen blocking spinner vs. per-trip placeholder rows on the Trip List) is a design-phase choice.

### Rationale

Atomic-per-trip preserves the rest of the data when one trip's migration fails. Idempotence + journalled resume eliminates the "killed mid-write" duplicate-or-orphan trap that NSPersistentCloudKitContainer offers no built-in protection against. Leaving the modality to design lets the design pick the lower-friction option once the actual record counts and timing are measured.

### Alternatives Considered

- **Background migration**: Rejected — UI complexity (rendering trips that exist in two zones simultaneously) outweighs the wait-time savings.
- **Lazy migration on first share**: Rejected — couples a user-initiated action to a long-running data move that can fail; recovery UX is hard.
- **All-or-nothing migration**: Rejected — one corrupted trip would block all access.
- **"At most once per device per upgrade" as a hard ceiling** (the wording in the first draft): Rejected because it conflicts with retryable per-trip failure recovery. Replaced with "idempotent until every trip is in a terminal state."

### Consequences

**Positive:**
- Predictable post-migration state (every trip is in exactly one zone).
- Per-trip failure isolation.
- Existing UI surfaces need no permanent "in-progress migration" branches; only Trip List needs the per-trip placeholder until termination.

**Negative:**
- Need a migration journal in the local store (extra `SchemaV3` bookkeeping, or a sidecar file).
- "Resume from a consistent point" is a non-trivial implementation that may approach the size of a small transactional log.

---

## Decision 5: Every participant is read-write; no read-only role exposed

**Date**: 2026-05-15
**Status**: accepted

### Context

CloudKit's `CKShare.ParticipantPermission` supports both `.readOnly` and `.readWrite`. The design doc §4 states all participants can view and complete tasks, view and check off packing items for any person, and modify trip attributes — i.e., everyone is read-write. We could either expose the CK toggle in the UI or not.

### Decision

Every invitee is set to `.readWrite` at share creation. The UI does not expose a read-only toggle.

### Rationale

The design doc is unambiguous about participant capabilities. Adding a read-only mode would introduce a new permission state across many existing affordances for no design-doc-supported user need. If a future spec wants a "viewer" role it can be added then.

### Alternatives Considered

- **Expose the CK read-only toggle**: Rejected — adds breadth across the UI for a non-goal.
- **Default to read-write but allow promotion to "co-owner"**: CKShare doesn't support multiple owners.

### Consequences

**Positive:**
- Single permission path through every affordance; less branching.
- UI matches the design doc.

**Negative:**
- A future "viewer" requirement would need a permission-aware refactor.

---

## Decision 6: Adopt one `ModelContainer` per accessible trip zone (resolves Phase 1 Decision 9)

**Date**: 2026-05-15
**Status**: superseded by Decision 13

### Context

Phase 1 Decision 9 explicitly deferred the per-trip-custom-zone goal because `NSPersistentCloudKitContainer` does not expose a public per-record zone-routing API; everything mirrored through SwiftData lands in a single zone. Both reviewers (design-critic + Gemini/Codex via peer-review-validator) flagged this as the single biggest feasibility risk for Phase 5. The realistic alternatives were (a) drop SwiftData for trip-owned entities and use raw `CKRecord`, (b) instantiate one `ModelContainer` per trip zone, or (c) abandon the per-trip-zone goal.

### Decision

Adopt one `ModelContainer` per accessible trip zone. Each trip zone is backed by a distinct `ModelConfiguration` whose `cloudKitDatabase` is configured for that zone's database scope (private for owner-owned, shared for accepted shares). The globals zone is a separate `ModelConfiguration` in the private database. SwiftData remains the persistence layer throughout.

### Rationale

Keeps SwiftData's ergonomics (Schema/Model macros, query, observation, the existing `EnvironmentProbe` test path) for every entity in the model. Avoids a parallel raw-`CKRecord` implementation for trip-owned records, which would double the maintenance surface and force a re-implementation of what `SchemaV3` is already asked to migrate. The per-zone-container approach is the documented escape hatch for needing zone-level control, and zone count grows linearly with trip count (small N for this app's audience).

### Alternatives Considered

- **Drop SwiftData for `Trip`/`TripTask`/`TripPackingItem`, use raw `CKRecord`**: Rejected — would require parallel persistence code paths, parallel query/observation infrastructure, and would split the codebase between two storage idioms.
- **Abandon per-trip zones; use one shared zone for all trips**: Rejected — kills the per-trip share boundary that is the entire point of the Phase 5 design (a single shared zone shared with one participant would expose every trip in that zone, regardless of intent).
- **One-`ModelContainer`-per-zone but eager-load every zone at launch**: Acceptable but suboptimal. Decision is the strategy; eagerness is a design call.

### Consequences

**Positive:**
- SwiftData stays the single persistence framework.
- Per-trip share boundary is enforced at the storage layer, not just the application layer.
- Phase 1's `EnvironmentProbe` and `ModelStore` patterns extend naturally (one store-per-zone factory).

**Negative:**
- N containers means N `@MainActor` SwiftData contexts; cross-container queries are not free.
- The globals container and per-trip containers cannot share `@Model` instances; cross-container references must be carried as IDs (already true for `masterItemID`; Decision 7 makes it true for person identity).
- Container lifecycle (create on share-accept, dispose on share-leave or trip-delete) becomes design work.
- The per-trip container registry MUST be keyed by the current iCloud identity. On iCloud account change between launches, the registry SHALL be torn down and rebuilt to prevent containers from a previous account leaking into the new account's session.

### Residual risk

External review (Codex) flagged that `NSPersistentCloudKitContainer`'s mapping from `NSPersistentStore` to a specific `CKRecordZone.ID` is not a documented public binding; the strategy relies on per-store-per-zone behaviour that is observable but under-documented. The user has explicitly chosen to proceed without a feasibility spike. The fallback if Decision 6 proves unworkable in practice is to drop SwiftData for `Trip`/`TripTask`/`TripPackingItem`/`TripPersonSnapshot` and use raw `CKRecord` for trip-zone data while keeping SwiftData for the globals zone. The design phase MUST front-load a small validation step that confirms per-store-per-zone routing on iOS 26 / Xcode 26 before tasks are written; if the validation fails, this decision is reopened in favour of the raw-`CKRecord` fallback.

### Impact

Replaces Phase 1 Decision 9. `ModelStore` will have to grow into a registry of per-trip containers + the globals container. The Phase 5 design phase is the right place to specify the registry's API and lifecycle.

---

## Decision 7: `SchemaV3` introduces a per-trip person snapshot

**Date**: 2026-05-15
**Status**: accepted

### Context

[Decision 2](#decision-2-master-lists-and-person-registry-remain-per-user-not-shared) requires denormalised person identity inside each trip zone. Phase 1 Decision 10 elevated schema decisions to requirements-level commitments. The denormalisation can take two shapes: inline fields on `TripPackingItem` (and wherever else `Person` is referenced), or a dedicated `TripPersonSnapshot` entity per trip-person pair living in the trip zone.

### Decision

Introduce `SchemaV3`. Define a new `@Model` entity that lives inside each trip zone and carries the denormalised person identity (id, name, colour assignment, initial source). `Trip.participants` and `TripPackingItem.person` retarget from `Person` to this new entity. The owner's device keeps the new entity in sync with the owner's `Person` records (the propagation in Req [2.3](requirements.md#2.3)). Lightweight migration adds the new entity and rewrites the existing relationships; the `Person`-to-snapshot bridge runs as part of the per-trip zone migration in Req [4](requirements.md#4-one-time-zone-migration-for-existing-trips).

### Rationale

A dedicated entity keeps the data model normalised inside a single zone, lets a person change colour without touching every `TripPackingItem`, and preserves the inverse-pair relationship style established in `docs/agent-notes/persistence.md`. Inline fields on `TripPackingItem` would scale poorly (every renamed person would dirty every related packing item) and would force `Trip.participants` into a parallel inline form. The new entity is the per-trip zone counterpart of `Person` for rendering purposes only — it never owns master items.

### Alternatives Considered

- **Inline person identity fields on every `TripPackingItem` and on `Trip.participants`**: Rejected — denormalises N times, multiplies the write surface on rename, and complicates the `Trip.participants` data shape.
- **Reuse `Person` itself in the trip zone (clone Person records into trip zones)**: Rejected — `Person` owns master packing items, which must remain in globals; cloning the same `@Model` class into two zones with different roles is a recipe for confusion.
- **No schema change; participants render "Unknown" for any reference whose `Person` is not in their globals**: Rejected — design doc requires participants to see the same trip the owner sees.

### Consequences

**Positive:**
- The trip zone is genuinely self-contained for rendering.
- Per-trip share remains private to that trip's data (no leakage of master-list person identity).
- Rename and recolour cost is one write per affected trip zone, not one per affected packing item.

**Negative:**
- Adds an entity to the model and a propagation step (`Person` → snapshot) to the engine triggers on the owner's device.
- The migration step (Req [4](requirements.md#4-one-time-zone-migration-for-existing-trips)) now also has to seed the snapshot entity for each trip.

### Impact

`Schema.swift` gains a new entity inside `SchemaV3`. The rules engine and Trip CRUD on the owner's device gain a "sync person identity to snapshot" step. Reading code (Trip List avatars, Trip Detail header, Packing Sheet, WhyDisclosure header) all switch to read through the snapshot whenever the trip is in a trip zone (i.e., post-migration always).

---

## Decision 8: Land minimal silent-push subscription scaffolding in Phase 5

**Date**: 2026-05-15
**Status**: accepted (Phase 6 retains user-visible notifications)

### Context

The first draft of the requirements deferred all notification machinery to Phase 6 in line with `docs/implementation-phases.md`, but the eventual-consistency criteria in §5/§6/§7 ("on the next CloudKit notification") rest on subscriptions actually existing. Reviewer Gemini flagged this as a real Phase 5 blocker: without subscriptions, a participant edit only reaches the owner when the owner manually foregrounds the app, which means rule-driven updates would not appear for participants either.

### Decision

Phase 5 ships `CKRecordZoneSubscription` (or its equivalent) per trip zone for both owners (on trip creation) and participants (on share acceptance). The subscriptions are silent — they trigger CloudKit fetches but do not surface a user-visible notification. User-visible notifications remain a Phase 6 deliverable.

### Rationale

The subscription plumbing is what makes the eventual-consistency contract testable and observable. Phase 6's user-visible-notifications work depends on the same `CKDatabaseSubscription`/`CKRecordZoneSubscription` surface; landing the silent-push plumbing now lets Phase 6 layer copy + presentation on top instead of rebuilding the foundation. The cost is a marginal expansion of Phase 5's CloudKit surface area; the benefit is a sharing flow that actually behaves like a sharing flow.

### Alternatives Considered

- **Defer all subscription work to Phase 6**: Rejected — would force every Phase 5 sync trigger into "next foreground"; Reqs about "next CloudKit notification" become "next launch", which makes shared editing feel broken.
- **Land user-visible notifications too**: Rejected — those need copy, deep-link behaviour (Phase 6 open question 3), and a notification settings surface; out of scope for Phase 5.

### Consequences

**Positive:**
- Eventual-consistency requirements are realisable without Phase 6.
- Phase 6 inherits a working subscription layer.

**Negative:**
- Phase 5 grows in scope by one subscription module.
- Subscription failure handling (Req [9.5](requirements.md#9.5)) becomes Phase 5 work.

---

## Decision 9: `pinnedByUser` and `userDeletedOnThisTrip` are trip-global, not per-member

**Date**: 2026-05-15
**Status**: accepted

### Context

Two existing flags on trip-owned records — `pinnedByUser` (Phase 2) and `userDeletedOnThisTrip` (Phase 3 Decision 7) — were defined in a single-user context. With sharing, "the user" is ambiguous: is a pin made by one member visible to others, or only to the member who set it?

### Decision

Both flags are trip-global in v1: any member can toggle them, and the change is visible to all members on next sync. They are not per-member overrides.

### Rationale

The design doc treats a trip as a shared object whose state is intentionally synchronised between members. Per-member overrides would require a participant-keyed sub-schema (e.g., a `TripTaskPerMemberFlag` table) that the design doc never asks for. Trip-global also matches the simple mental model: "my friend pinned the passport task; now we both see it pinned" is more aligned with the collaborative use case than "my friend pinned it and I have no idea". The existing engine invariant (Req [8.4](requirements.md#8.4)) means trip-global pinning is safe — the engine on the owner's device will respect it just as it respects an owner-set pin.

### Alternatives Considered

- **Per-member flags via a side table**: Rejected — schema cost, UI clarity cost, no design-doc-supported need.
- **`pinnedByUser` trip-global but `userDeletedOnThisTrip` per-member**: Rejected — inconsistent semantics across two flags that already feel similar to users.

### Consequences

**Positive:**
- No new schema for per-member overrides.
- Behaviour matches a "shared notebook" mental model.

**Negative:**
- A participant who hides an item via `userDeletedOnThisTrip` hides it for everyone. Acceptable in v1; if user feedback demands per-member, a future spec can introduce overrides.

---

## Decision 10: Two-stage migration (custom Stage A + zone Stage B) with a single in-globals journal

**Date**: 2026-05-15
**Status**: accepted

### Context

`SchemaV3` has to do two things at first launch: (1) rewrite `Trip.participants` and `TripPackingItem.person` from `Person` to the new `TripPersonSnapshot`, and (2) move every existing trip's records out of the default zone into a per-trip zone. Both steps can fail. Both must be safe to resume after kill-mid-process. They have very different shapes (one is a SwiftData migration, the other is a CloudKit + cross-container data move) but they share the same end goal: post-migration state is one trip = one zone, fully snapshotted.

### Decision

Two stages run in order at launch. Stage A is a custom `MigrationStage` inside `AppMigrationPlan` that performs the V2→V3 relationship rewrite within the existing default-zone container. Stage B is a separate `ZoneMigrationCoordinator` that runs after the SwiftData migration plan has completed; it iterates through trips, drives the per-trip zone move, and tracks progress via `MigrationJournalEntry` rows in the globals container.

### Rationale

Splitting on the layer boundary keeps each stage testable in isolation: Stage A is exercisable with an in-memory ModelContainer and no CloudKit; Stage B is exercisable with `FakeSharingService` and two in-memory ModelContainers. Folding Stage B into the SwiftData migration plan would block the migration plan on CloudKit operations, which is both slow and risky (SwiftData's migration runs synchronously during container construction). Using the journal for Stage B (rather than checking persistent-history or comparing zones every launch) makes resume cheap: read N journal rows, act only on non-terminal ones.

### Alternatives Considered

- **Single combined stage in `AppMigrationPlan`**: Rejected — couples SwiftData container construction to CloudKit availability; offline launch would block forever.
- **No journal; reconcile by comparing source-zone counts to destination-zone counts each launch**: Rejected — every launch pays the cost; correctness depends on CloudKit having delivered all changes; resume after partial failure is not deterministic.
- **Per-trip journal stored inside each trip's destination zone**: Rejected — chicken-and-egg with zone creation; can't read the journal until the zone exists.

### Consequences

**Positive:**
- Each stage independently testable.
- Resume cost is O(N trips) and almost entirely terminal-state rows in steady state.
- The journal entity is a normal `@Model` in globals; uses existing persistence patterns.

**Negative:**
- One additional `@Model` (`MigrationJournalEntry`) lives forever in globals (terminal-state rows could be cleaned up but provide useful audit data).
- Stage B's coordinator needs a CloudKit-completion observer (`NSPersistentCloudKitContainer.eventChangedNotification`) before it can safely delete from source — a non-trivial async wait.

---

## Decision 11: Deterministic zone naming + claim record for concurrent-device migration

**Date**: 2026-05-15
**Status**: amended by Decision 13 — deterministic zone naming retained; claim record dropped (CKSyncEngine state machine handles dedup)

### Context

Req [4.9](requirements.md#4.9) demands that two of the owner's devices upgrading simultaneously do not duplicate the move. CloudKit zone creation is `IfServerRecordUnchanged`-aware but the data move itself isn't transactional. Without coordination, both devices would create separate zones (if zone names were random) or both would try to migrate the same records (if zone names matched) and produce duplicates.

### Decision

Zone names are deterministic: `"trip-\(trip.id.uuidString)"` with `ownerName: CKCurrentUserDefaultName`. Before any record move, the migrating device writes a marker record `(recordType: "ZoneMigrationClaim", recordID: "marker-\(trip.id)")` into the destination zone with the device's identifier and an `ifServerRecordUnchanged` save policy. If the marker exists with a different deviceID, this device defers and lets the other finish. On the next launch, the deferring device sees the destination already populated and runs only the source-cleanup step.

### Rationale

Deterministic zone names mean both devices target the same zone — there is no "lost zone" failure mode. The claim record is a CloudKit-native mutex with no extra infrastructure. Using `ifServerRecordUnchanged` makes the claim atomic from CloudKit's perspective. Marking deferred trips back as `.pending` (not `.failed`) means the resume logic naturally re-checks them; the second device doesn't need a special "I'm waiting for the other device" state.

### Alternatives Considered

- **Random zone names**: Rejected — both devices create distinct zones; duplicate data with no automatic reconciliation.
- **Server-side coordination (CloudKit Function)**: Out of scope for v1.
- **Optimistic concurrency on the source records (delete-with-`ifServerRecordUnchanged`)**: Insufficient — handles the delete race but not the duplicate-create race.

### Consequences

**Positive:**
- Two devices converge to one zone with the correct contents.
- No additional infrastructure beyond a one-record marker per zone.
- Claim record stays in the zone after migration (small permanent overhead) but documents which device performed the move.

**Negative:**
- If the marker write succeeds but the device crashes before any records are written, the second device will defer indefinitely (waits for the first device's records that never arrive). Mitigation: claim record carries `claimedAt`; after a 24-hour staleness window, the second device may overwrite and proceed. (24h is conservative; a real measurement may shrink this — design phase choice.)

---

## Decision 12: Stable subscription IDs derived from zone name

**Date**: 2026-05-15
**Status**: superseded by Decision 13 — `CKSyncEngine` manages subscription registration internally; manual subscription management is no longer in scope

### Context

CloudKit subscriptions are server-side resources; re-registering with the same ID is a no-op, while re-registering with a fresh random ID creates duplicates. Subscriptions for a trip zone may need to be (re-)registered after a network failure, an app reinstall, an iCloud account change, or a deferred Stage B migration completing.

### Decision

`subscriptionID = "zone-sub-\(zoneID.zoneName)"`. Identical across devices for the same trip zone in the same DB scope; safe to re-register at any time.

### Rationale

CloudKit subscription IDs are unique per database per user. Deriving them deterministically from the zone name makes registration idempotent and trivially debuggable. No need for a "have I already registered this?" check stored locally; the server is the source of truth and `CKModifySubscriptionsOperation` with the existing ID is a cheap no-op when the subscription already exists.

### Alternatives Considered

- **UUID-per-registration**: Rejected — duplicates on retry; needs local tracking to dedupe.
- **One database-wide subscription instead of per-zone**: Considered. Simpler but coarser — every change in any zone wakes the app. For a small N of trip zones the per-zone subscription is more targeted; for very large N (>100) a database subscription would scale better. Per-zone chosen as the v1 default; revisitable if the app grows trip counts.

### Consequences

**Positive:**
- Re-registration is safe at any time.
- Zero local state for subscription tracking (the registry caches IDs only as a render-time optimisation; the source of truth is the server).

**Negative:**
- Per-zone subscriptions don't scale to hundreds of trips per user; acceptable for the design-doc audience (personal/family use).

---

## Decision 13: Pivot from per-zone `ModelContainer`s to `CKSyncEngine` for trip-zone sync (supersedes Decision 6)

**Date**: 2026-05-15
**Status**: accepted (supersedes Decision 6; amends Decisions 11 and 12)

### Context

Decision 6 committed to one `ModelContainer` per accessible trip zone, with `cloudKitDatabase: .private` for owned zones and `cloudKitDatabase: .shared` for accepted shared zones. Codex's read of the iOS 26.4 SDK headers established that `ModelConfiguration.CloudKitDatabase` exposes only `.automatic`, `.private(String)`, and `.none` — there is no `.shared` case. Participants therefore cannot mount accepted shared zones through SwiftData using public API. Decision 6's front-loaded validation tested two `.private` configurations and would have passed while the actual participant path failed.

### Decision

Drop the per-trip `ModelContainer` strategy. Use one local SwiftData container (`tripsLocal`, `cloudKitDatabase: .none`) for all trip-zone entities (`Trip`, `TripTask`, `TripPackingItem`, `TripPersonSnapshot`, `TripZoneState`). Drive bidirectional sync of those records to per-trip CK zones via two `CKSyncEngine` instances (one private-DB, one shared-DB) wrapped behind a `TripSyncEngine` façade. Globals continues to use SwiftData's CloudKit mirror (`globals` container, `cloudKitDatabase: .private`) — globals is never shared.

### Rationale

`CKSyncEngine` (iOS 17+) is the public-API path for the exact pattern Phase 5 needs: caller owns the local store, the engine handles zones, subscriptions, conflict surfacing, retries, and the share-acceptance boundary. Both private and shared database scopes are first-class. SwiftData's `@Model` + `@Query` remain the UI layer, so Phase 1–4 view code does not need to change. Owners and participants share the same code path — no hybrid raw-`CKRecord`-for-participants split. Subscription and concurrent-device-migration coordination collapse into `CKSyncEngine`'s state machine, simplifying the design.

### Alternatives Considered

- **Hybrid: per-zone `ModelContainer`s for owners, raw `CKRecord` for participants**: Rejected — splits the codebase between SwiftData-backed and raw-CK-backed views; participants would need a parallel rendering path.
- **Drop SwiftData entirely; raw `CKRecord` for everything**: Rejected — rewrites the persistence layer of all four prior phases.
- **Wait for Apple to add `.shared` to `ModelConfiguration.CloudKitDatabase`**: Rejected — timeline unknown; not actionable for v1.
- **Use `NSPersistentCloudKitContainer` directly (skipping SwiftData) for trip-zone entities**: Rejected — same view-layer-rewrite cost as raw `CKRecord`, with all of Core Data's API surface to maintain.

### Consequences

**Positive:**
- Implementable on iOS 26 with public API only.
- One local SwiftData container for trip data; existing `@Query`-based UI code unchanged.
- `CKSyncEngine` handles subscriptions, retries, batch uploads, conflict surfacing, share-acceptance routing.
- Test seam collapses to one `TripSyncEngine` protocol with a fake implementation (in-process two-side transport).
- The owner-side echo-loop concern reduces to filtering events by `isSelfOriginated`, which `CKSyncEngine` exposes.

**Negative:**
- Two persistence layers: SwiftData (local cache) + `CKSyncEngine` (sync state). The sync state is opaque blob storage, not first-class to SwiftData.
- Manual `@Model ↔ CKRecord` translators (one per entity). Mechanical but non-trivial.
- Conflict resolution is application-side: `CKSyncEngine` surfaces conflicts; LWW per attribute is implemented in the translator.
- `ckRecordSystemFields: Data?` blob added to every entity that mirrors a CKRecord — required to preserve CKRecord system fields across writes.
- Migration from existing default-zone records to per-trip zones is now driven by `CKSyncEngine` state plus a separate cleanup of orphaned default-zone records, instead of in-place CKRecord moves.

### Impact

Replaces large parts of design.md: the container registry concept, the manual subscription management, the claim-record protocol from Decision 11, and the launch-blocking nature of Stage B. Decisions 11 and 12 are amended/superseded accordingly. The validation gate is rewritten to exercise the full owner-create + participant-accept lifecycle through `CKSyncEngine`, not just two private-scope `ModelConfiguration`s.

### Amendments (post-review)

Codex's iOS 26.4 SDK header reading clarified two points after the initial Decision 13 was written; both are reflected in the design document, recorded here for traceability:

- **Use `CKShare(recordZoneID:)` for trip shares**, not `CKShare(rootRecord:)`. Each trip already lives in its own zone, so a zone-wide share is the natural primitive and avoids the "save root-record + share atomically" complication.
- **`CKSyncEngine.State.add(pendingRecordZoneChanges:)` takes record IDs**, not `CKRecord`s; the delegate's `nextRecordZoneChangeBatch(_:syncEngine:)` supplies the actual records when the engine asks. Push-notification routing calls `engine.fetchChanges()` (not a non-existent `engine.handleEvent`).

---

## Decision 14: `TripPackingItem.personSnapshot` is a value reference, not a relationship

**Date**: 2026-06-18
**Status**: accepted (amends Decision 7 — the denormalised-snapshot concept stands; only the storage form on `TripPackingItem` changes)

### Context

`TripPackingItem.personSnapshot` shipped (Decision 7) as `@Relationship var personSnapshot: TripPersonSnapshot?` with no inverse — `TripPersonSnapshot` has no `[TripPackingItem]` collection, and the snapshot↔item inverse is exactly the nullify chain that panics SwiftData's cascade traversal on iOS 26.4. This passed every test and ran on the simulator, where containers use `cloudKitDatabase: .none`. On a real device with an iCloud account, the `globals` container (which mirrors the full model list to CloudKit via `.private`) failed to load: `NSCocoaErrorDomain Code=134060 ... CloudKit integration requires that all relationships have an inverse: TripPackingItem: personSnapshot`. The container fell back to local-only, silently disabling iCloud sync for `Person` and the master lists.

### Decision

Store the reference as `personSnapshotID: UUID?` (a value reference, matching `TripTask.assigneePersonID`, Decision 9). Expose the snapshot through a `personSnapshot` computed bridge that resolves the ID via `trip?.participantSnapshots` and falls back to a `modelContext` fetch. The CKRecord wire format is unchanged (`personSnapshotID: String`); decode stores the bare ID (dangling references tolerated).

### Rationale

CloudKit's "all relationships need an inverse" rule applies to every relationship in a mirrored schema. The two ways to satisfy it were (a) add the inverse collection on `TripPersonSnapshot`, or (b) drop the relationship for a value reference. Option (a) re-creates the iOS 26.4 cascade panic the team already worked around for `participantSnapshots`. Option (b) removes the relationship entirely, so there is nothing for CloudKit to validate, and aligns with the existing `assigneePersonID` precedent. Predicates gain a directly-queryable scalar (`$0.personSnapshotID == id`) instead of a finicky relationship key-path.

### Alternatives Considered

- **Add an inverse collection on `TripPersonSnapshot`**: Satisfies CloudKit - Rejected: reintroduces the iOS 26.4 snapshot↔item cascade-traversal panic.
- **Split `globals` into two `ModelConfiguration`s (CloudKit + local) to exclude trip-zone models from the mirror**: Conceptually matches Decision 13's ownership table - Rejected: the deprecated `Trip.participants → Person` / `Person.tripPackingItems` relationships cross between the two model subsets, and SwiftData relationships can't span configurations.

### Consequences

**Positive:**
- `globals` CloudKit mirror loads on-device; `Person`/master-list iCloud sync restored.
- No cascade-panic exposure; `personSnapshotID` is directly predicate-able.
- Consistent with `assigneePersonID`'s dangling-reference model.

**Negative:**
- Reads go through a computed bridge that may issue a fetch when `participantSnapshots` isn't wired (cheap; production reads hit the in-memory path).
- An existing on-disk store's old `personSnapshot` relationship column is not data-migrated to `personSnapshotID` (acceptable — no production store predates this; the app never launched successfully on-device before the fix).
- `specs/phase-5-cloudkit-sharing/design.md` (frozen historical spec) still depicts `personSnapshot` as a `@Relationship` with a `TripPersonSnapshot.tripPackingItems` inverse — the same inverse the "Alternatives Considered" above rejects, and which was in fact never shipped. This decision and `docs/agent-notes/persistence.md` are the authoritative current state; the design doc is not retro-edited.

---
