# Requirements: Phase 2 Rules Engine

## Introduction

Phase 2 turns the master-list data model from Phase 1 into a working rules engine and ships the Master Lists tab that edits its inputs. After Phase 2 the user can author master tasks and master packing items with attribute-based conditions, and trip-level `TripTask` / `TripPackingItem` records auto-populate, re-evaluate, and dim themselves when conditions stop matching — though no trip-detail UI consumes these records yet (that lands in Phases 3 and 4).

## Non-Goals

- Timeline accordion expansion, task rows, packing summary block, packing sheet — all deferred to Phases 3 and 4.
- Trip-level "Add manual item" UI; manual items are supported in the model but no editor ships in Phase 2.
- Pin / unpin UI; `pinnedByUser` is honoured by the engine but no toggle ships.
- `WhyDisclosure` UI and the "which clauses contributed to the match" introspection function; both arrive with Phase 3, which will extend `ItemConditions` with a parallel walk that returns the matched `.match(...)` clauses.
- Nested `.all` / `.any` condition groups in the editor; storage supports them but the v1 editor is a flat per-attribute table. Items already in those shapes are read-only with a reset-to-simple escape (AC 3.7).
- Promote-a-trip-item-to-master-list flow.
- Sample / demo content; seeding is deferred to a later phase and requires no Phase 2 prework (see decision log).
- CloudKit sync as a re-evaluation trigger; sync-driven recompute is deferred to the CKShare phase. The Phase 2 cold-launch and foreground-transition scans cover the single-device convergence story (AC 5.4, AC 5.7).
- Concurrency edits across devices for the same master item; standard last-write-wins is acceptable.
- Background-thread execution of the rules engine; family-scale bounds (AC 5.5) keep all work on the main actor.

## Requirements

### 1. Master Task CRUD

**User Story:** As a Scramble user, I want to author reusable master tasks tagged with a phase and attribute conditions, so that trips auto-populate the right tasks without me retyping them.

**Acceptance Criteria:**

1. <a name="1.1"></a>The Master Lists "Tasks" segment SHALL list every `MasterTaskItem`, grouped by `Phase` in the canonical phase order, with empty groups omitted.  
2. <a name="1.2"></a>The Master Lists "Tasks" segment SHALL provide a "+ Add task" affordance that opens an editor for a new `MasterTaskItem` with name, phase, and conditions.  
3. <a name="1.3"></a>Tapping an existing task row SHALL open the same editor in edit mode for that `MasterTaskItem`.  
4. <a name="1.4"></a>The master task editor SHALL persist a non-empty name, a selected phase, and the conditions value on save, and SHALL discard changes on cancel.  
5. <a name="1.5"></a>The master task editor SHALL block save and surface an inline validation message when the name is empty.  
6. <a name="1.6"></a>The master task editor SHALL expose a delete affordance that, after a confirmation dialog matching the destructive-confirmation pattern used for Trip deletion (Phase 1 [AC 6.6](../phase-1-foundation/requirements.md#6.6)), removes the `MasterTaskItem`. Trip-level `TripTask` records referencing the deleted master via `masterItemID` SHALL retain their snapshot `name`, retain their `masterItemID` (never nulled), and SHALL be flagged per [6.5](#6.5).

### 2. Master Packing CRUD

**User Story:** As a Scramble user, I want to author reusable master packing items per person with attribute conditions, so that each person's packing list auto-populates per trip.

**Acceptance Criteria:**

1. <a name="2.1"></a>The Master Lists "Packing Items" segment SHALL list every `MasterPackingItem`, grouped by `Person` in `Person.name` ascending order, with people who own no items omitted. Each per-person group header SHALL show the count of items owned by that person.  
2. <a name="2.2"></a>The Master Lists "Packing Items" segment SHALL provide a "+ Add item" affordance that opens an editor for a new `MasterPackingItem` with name, owning person, and conditions.  
3. <a name="2.3"></a>Tapping an existing packing item row SHALL open the same editor in edit mode for that `MasterPackingItem`.  
4. <a name="2.4"></a>The master packing editor SHALL persist a non-empty name, a selected `Person`, and the conditions value on save, and SHALL discard changes on cancel.  
5. <a name="2.5"></a>The master packing editor SHALL block save and surface an inline validation message when the name is empty or no person is selected.  
6. <a name="2.6"></a>The master packing editor SHALL expose a delete affordance with the same confirmation pattern as [1.6](#1.6). Trip-level `TripPackingItem` records referencing the deleted master via `masterItemID` SHALL retain their snapshot `name`, retain their `masterItemID` (never nulled), and SHALL be flagged per [6.5](#6.5).  
7. <a name="2.7"></a>WHEN the Master Lists "Packing Items" segment is opened AND no `Person` records exist in the store, the empty state SHALL direct the user to create a person via the trip editor before authoring packing items.

### 3. Conditions Editor

**User Story:** As a Scramble user, I want to express conditions like "weather is rain or cold AND scope is international" using a simple per-attribute picker, so that I don't have to learn a query syntax.

**Acceptance Criteria:**

1. <a name="3.1"></a>The conditions editor SHALL present every `TripAttribute` (Duration, Transport, Scope, Weather, Purpose) as a row in a flat list, in `TripAttribute` declaration order.  
2. <a name="3.2"></a>Each attribute row SHALL present that attribute's full value set as multi-select chips; selected chips within a single attribute combine as OR; selections across different attributes combine as AND.  
3. <a name="3.3"></a>An attribute row with zero selected chips SHALL be omitted from the persisted condition (the attribute imposes no constraint).  
4. <a name="3.4"></a>WHEN every attribute row has zero selected chips, the persisted condition SHALL be `ItemConditions.always` (matches every trip).  
5. <a name="3.5"></a>WHEN at least one attribute row has selected chips, the persisted condition SHALL be `ItemConditions.all([…])` whose children are `ItemConditions.match(attribute:, anyOf:)` entries — one per attribute that has selected chips, in `TripAttribute` declaration order. `TripAttribute` declaration order is append-only; new cases are appended at the end so persisted-condition Equatable comparisons remain stable across versions.  
6. <a name="3.6"></a>The conditions editor SHALL round-trip: opening an item that was saved with `.always` or with `.all([.match…])` in the v1 shape SHALL reconstruct the corresponding chip selections, including the zero-selection state for `.always`.  
7. <a name="3.7"></a>WHEN an item's stored conditions are not representable in the v1 shape (nested `.all` / `.any`, or `.any` at the top level, or `.match` whose `anyOf` contains values outside the attribute's current value domain), the editor SHALL (a) display a read-only "Advanced condition" placeholder that prints a textual rendering of the condition tree, (b) disable conditions editing while still allowing name / phase / person edits, and (c) expose a "Reset to simple" affordance that, after confirmation, replaces the stored condition with `.always` so the user can re-author with the chip editor. The confirmation dialog SHALL warn the user that the item will match every non-past trip on the next re-evaluation until new conditions are saved.  
8. <a name="3.8"></a>On save, the editor SHALL validate that every value inside every `.match(anyOf: [...])` is a current member of that attribute's value domain; values outside the domain SHALL be rejected with an inline validation message.

### 4. Rules Engine — Compute and Diff

**User Story:** As a Scramble user, I want trips to automatically gain the items that match their attributes, so that I don't manually copy items from master lists.

**Acceptance Criteria:**

1. <a name="4.1"></a>The rules engine SHALL expose a pure function `compute(trip: TripSnapshot, masterTasks: [MasterTaskSnapshot], masterPacking: [MasterPackingSnapshot]) -> Plan`. `Plan` SHALL expose four deterministically-ordered collections — `toAddTasks: [MasterTaskSnapshot]`, `toAddPacking: [MasterPackingSnapshot]`, `toFlagUnmatched: [TripItemRef]`, `toFlagMatched: [TripItemRef]` — where `TripItemRef` is a tagged value identifying the trip-level item's entity kind (task / packing) and `id`. `toAdd*` contains master items not yet present on the trip whose conditions evaluate true against `trip.attributes`; `toFlagUnmatched` contains existing trip-level items whose linked master conditions evaluate false; `toFlagMatched` contains existing trip-level items currently flagged unmatched whose linked master conditions now evaluate true again.  
2. <a name="4.2"></a>The rules engine SHALL NOT produce a `toRemove` set; matched-to-unmatched transitions are flag changes, never deletions.  
3. <a name="4.3"></a>The `apply(plan:context:)` step SHALL insert one `TripTask` per `MasterTaskSnapshot` in `toAdd` (with `source = .rule`, `currentlyMatchesRules = true`, `pinnedByUser = false`, `name` snapshotted from the master, `phase` copied from the master, `masterItemID` set, `isCompleted = false`).  
4. <a name="4.4"></a>`apply` SHALL insert one `TripPackingItem` per `MasterPackingSnapshot` in `toAdd` (with `source = .rule`, `currentlyMatchesRules = true`, `pinnedByUser = false`, `name` snapshotted, `person` resolved from `personID`, `masterItemID` set, `state = .unpacked`). If the referenced `Person` no longer resolves in the context, `apply` SHALL skip that insertion and log the skip — this is consistent with Phase 1's orphan-tolerance policy.  
5. <a name="4.5"></a>`apply` SHALL set `currentlyMatchesRules = false` on every trip-level item in `toFlagUnmatched` and `currentlyMatchesRules = true` on every trip-level item in `toFlagMatched`. No other property is mutated by `apply`. Trip-level items whose linked master conditions evaluate true and whose `currentlyMatchesRules` is already `true` SHALL NOT be written (no-op, no CloudKit push).  
6. <a name="4.6"></a>Trip-level items with `source = .manual` (no `masterItemID`) SHALL be ignored by the engine: never added, never flagged, never removed.  
7. <a name="4.7"></a>Trip-level items whose `masterItemID` references a master that has been deleted SHALL be classified as unmatched on the next re-evaluation (`toFlagUnmatched` if currently matched, no-op if already unmatched), subject to [6.1](#6.1)–[6.3](#6.3) exclusions. The dangling `masterItemID` SHALL be preserved.  
8. <a name="4.8"></a>`compute(...)` SHALL accept only value-type snapshot inputs (`TripSnapshot`, `MasterTaskSnapshot`, `MasterPackingSnapshot`) and SHALL NOT read from a `ModelContext`. `Plan` entries SHALL carry every field `apply` needs to insert or update without re-dereferencing `@Model` objects. `compute` SHALL therefore be unit-testable without constructing a `ModelContainer`. `ItemConditions.evaluate(against:)` SHALL likewise be a pure function over value-type inputs (the conditions value and a `TripAttributes` value) with no side effects, no `ModelContext` access, and no shared state — the engine's purity claim depends on this invariant.  
9. <a name="4.9"></a>`Plan` collections SHALL iterate in deterministic order — `toAdd` sorted by master `id` ascending; `toFlagUnmatched` and `toFlagMatched` sorted by trip-level item `id` ascending — so re-runs and snapshot tests produce stable output.

### 5. Re-evaluation Triggers

**User Story:** As a Scramble user, I want the rules engine to re-run whenever something it depends on changes, so that trip-level items stay consistent with my master lists and trip attributes.

**Acceptance Criteria:**

1. <a name="5.1"></a>WHEN a trip is created via the trip editor, the system SHALL run the rules engine against that trip exactly once before the editor dismisses.  
2. <a name="5.2"></a>WHEN a trip's attributes are saved via the trip editor in edit mode, the system SHALL run the rules engine against that trip exactly once on save commit, regardless of whether attributes actually changed.  
3. <a name="5.3"></a>WHEN a `MasterTaskItem` or `MasterPackingItem` is created, edited, or deleted via the master list editor, the system SHALL run the rules engine against every non-past `Trip` (a `Trip` whose `endDate ≥ today` in `Calendar.current` on the device, calendar-day granularity) exactly once after the save commits.  
4. <a name="5.4"></a>WHEN the app cold-launches (first scene attach after process create), the system SHALL run the rules engine against every non-past `Trip` per [5.3](#5.3)'s definition exactly once, after the model container is constructed and before any list is interactive.  
5. <a name="5.5"></a>Re-evaluation triggered by [5.1](#5.1)–[5.7](#5.7) SHALL run on the main actor and SHALL complete within 250ms wall-clock — measured from the start of snapshot capture through the end of `apply`'s `ModelContext.save()` — for the bounded dataset (≤20 non-past trips, ≤500 trip-level items per trip, ≤200 master items total).  
6. <a name="5.6"></a>Re-evaluation SHALL be idempotent: running the engine twice in succession against the same inputs SHALL produce no further `apply`-time mutations on the second run.  
7. <a name="5.7"></a>WHEN the app's `scenePhase` transitions from `.background` to `.active`, the system SHALL run the rules engine against every non-past `Trip` per [5.3](#5.3)'s definition exactly once. This trigger fires regardless of how long the app was backgrounded and regardless of whether CloudKit sync has produced changes. This trigger SHALL NOT fire on the cold-launch transition (`nil → .inactive → .active`) — that path is covered by [5.4](#5.4).

### 6. Pinned, Completed, Packed, Excluded, and Orphaned Items

**User Story:** As a Scramble user, I want the engine to respect items I have already engaged with, so that completing a task, packing an item, or excluding an item never causes it to disappear when conditions later change.

**Acceptance Criteria:**

1. <a name="6.1"></a>Trip-level items with `pinnedByUser == true` SHALL be excluded from `toFlagUnmatched` regardless of condition evaluation; `currentlyMatchesRules` SHALL remain at whatever value it had before the re-evaluation. Pinning does NOT exclude an item from `toFlagMatched` — a pinned, currently-unmatched item whose conditions match again SHALL have `currentlyMatchesRules` set to `true`. Pinning protects against demotion, not against re-matching.  
2. <a name="6.2"></a>Trip-level `TripTask` items with `isCompleted == true` SHALL be excluded from `toFlagUnmatched`; their `currentlyMatchesRules` is preserved. They remain eligible for `toFlagMatched`.  
3. <a name="6.3"></a>Trip-level `TripPackingItem` items in `state ∈ {.packed, .repacked, .excluded}` SHALL be excluded from `toFlagUnmatched`; their `currentlyMatchesRules` is preserved. They remain eligible for `toFlagMatched`. `.excluded` is included alongside `.packed` and `.repacked` because the user has explicitly engaged with the item.  
4. <a name="6.4"></a>`toAdd` SHALL NOT re-insert a master item whose `id` is already present on the trip as a `masterItemID` reference on at least one trip-level item, regardless of whether the existing trip-level item is currently flagged matched or unmatched. WHEN multiple trip-level items on the same trip reference the same `masterItemID` (e.g., a cross-device sync race), the engine SHALL treat the master as already present and SHALL NOT add a further trip-level item; the duplicates are tolerated and the engine SHALL NOT delete or merge them.  
5. <a name="6.5"></a>WHEN a master item is deleted, every trip-level item referencing it via `masterItemID` SHALL have `currentlyMatchesRules` set to `false` on the next re-evaluation that touches its trip, unless excluded by [6.1](#6.1)–[6.3](#6.3). The trip-level item SHALL retain its `name` snapshot, its `phase` / `person`, its state, and its `masterItemID` (never nulled). Phase 3 will render the dangling reference via `WhyDisclosure` placeholder copy.

### 7. Master Item — Cross-Trip Effects

**User Story:** As a Scramble user, I want master-list edits to affect future and active trips consistently, so that improving a master item updates the trips that haven't shipped yet.

**Acceptance Criteria:**

1. <a name="7.1"></a>WHEN a `MasterTaskItem` or `MasterPackingItem` is renamed, existing trip-level items referencing it via `masterItemID` SHALL retain their original `name` snapshot. The new name applies only to trip-level items created by subsequent re-evaluations.  
2. <a name="7.2"></a>WHEN a `MasterTaskItem`'s `phase` is changed, existing trip-level items referencing it via `masterItemID` SHALL retain their original `phase`. The new phase applies only to trip-level items created by subsequent re-evaluations.  
3. <a name="7.3"></a>WHEN a `MasterPackingItem`'s `person` is changed, existing trip-level items referencing it via `masterItemID` SHALL retain their original `person`. The new person applies only to trip-level items created by subsequent re-evaluations.  
4. <a name="7.4"></a>WHEN a `MasterTaskItem` or `MasterPackingItem`'s conditions are changed such that the item no longer matches some non-past trip's attributes, the re-evaluation per [5.3](#5.3) SHALL classify that trip's referencing trip-level item into `toFlagUnmatched` (subject to [6.1](#6.1)–[6.3](#6.3) exclusions).  
5. <a name="7.5"></a>Re-evaluation SHALL always read the current master item state, not a point-in-time copy captured at trip creation. Phase 3's `WhyDisclosure` is built on the same invariant: a rule-driven trip-level item's "why" reflects the master's conditions as they exist right now.

### 8. Person Deletion Guard

**User Story:** As a Scramble user, I want the app to prevent me from deleting a person who still owns master packing items, so that I don't silently break my master list.

**Acceptance Criteria:**

1. <a name="8.1"></a>The Master Lists "Packing Items" segment SHALL surface, per [2.1](#2.1), every `Person` who owns at least one `MasterPackingItem` and the count of their items.  
2. <a name="8.2"></a>WHEN the user attempts to delete a `Person` from any people-management surface AND that `Person` owns one or more `MasterPackingItem` records, the delete affordance SHALL be blocked with an alert listing the count of referencing master items, consistent with the Phase 1 trip-packing-item guard ([Phase 1 AC 9.7](../phase-1-foundation/requirements.md#9.7) and [Phase 1 Decision 16](../phase-1-foundation/decision_log.md)).

## Open Questions

None at requirements stage — see `decision_log.md` for resolved decisions.
