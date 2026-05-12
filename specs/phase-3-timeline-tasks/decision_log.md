# Decision Log: Phase 3 — Timeline + Tasks

## Decision 1: Spec name and scope

**Date**: 2026-05-12
**Status**: accepted

### Context

Phase 3 builds the Trip Detail timeline UI and tasks list per `docs/implementation-phases.md` §"Phase 3 — Timeline + Tasks". Naming must match the existing convention used by `specs/phase-1-foundation` and `specs/phase-2-rules-engine`.

### Decision

The spec is named `phase-3-timeline-tasks` and is scoped to: full `PhaseNode`, one-at-a-time accordion, task rows, manual one-off task creation, task editing/deletion, `WhyDisclosure`, `TripTask.assigneePersonID`, `TripTask.userDeletedOnThisTrip`, and short-trip phase compression for `duringTrip` only.

### Rationale

Matches the precedent set by phases 1 and 2. The "tasks" suffix differentiates from later phases that also touch the timeline (Phase 4 packing summary block, Phase 6 deep-link auto-expand).

### Alternatives Considered

- **`phase-3-timeline`**: Shorter — Rejected because "timeline" alone undersells the headline deliverable (the task UI surface).

### Consequences

**Positive:**
- Naming is self-describing and grep-friendly.

**Negative:**
- Slightly longer directory name.

---

## Decision 2: Short-trip phase compression rule (revised)

**Date**: 2026-05-12
**Status**: accepted (superseded prior draft after review)

### Context

UI design doc §"Engineering Decisions and Open Questions" item 2 flagged this as undecided. The original draft applied compression to any zero-duration phase, including packing phases. The review identified that this contradicts Req 2.6 ("packing phases are always expandable") because a 1-day trip would compress `dayBeforeReturn` and orphan the Phase 4 packing summary. The trip-date-to-phase-date mapping also needed an explicit definition.

### Decision

Compression applies only to the `duringTrip` phase, only when its duration per the canonical mapping is zero days. Packing phases (`departureDay`, `dayBeforeReturn`) are explicitly exempt and always remain expandable. The other 1-day phases (`dayBefore`, `returnDay`) cannot be zero-duration under the mapping, so they are not subject to compression. The canonical date-range mapping is defined in the requirements document.

### Rationale

Limiting compression to `duringTrip` resolves the contradiction with Req 2.6 (packing phases stay reachable for Phase 4). Defining the canonical mapping makes "zero-duration" testable. Other short-trip artefacts (e.g., `dayBefore` and `dayBeforeReturn` falling on the same calendar date in a 1-day trip) are visual coexistence concerns for the design phase, not compression concerns.

### Alternatives Considered

- **Compress any zero-duration phase, including packing**: Rejected because the Phase 4 packing summary on a 1-day trip would be unreachable from the timeline, contradicting Req 2.6.
- **Hide compressed phases entirely**: Rejected because removing nodes from the timeline breaks the seven-phase mental model.
- **Always render normally**: Rejected because short-trip timelines remain noisy.
- **Compress based on date range OR content**: Rejected because content-driven compression would hide existing tasks.

### Consequences

**Positive:**
- Resolves Phase 1 open question 2.
- Compatible with Phase 4's packing summary on the packing phases of short trips.
- Compression rule is deterministic from trip dates alone, trivially testable.

**Negative:**
- Tasks attached to a compressed `duringTrip` are invisible from the UI with no recovery affordance in Phase 3 (see Non-Goals). The rules engine is not modified to avoid attaching tasks to compressed phases — orphaning is an accepted limitation. Whether the engine should learn about compression is a deferred question for a later phase.

---

## Decision 3: Manual task creation flow

**Date**: 2026-05-12
**Status**: accepted

### Context

The "+ Add task" affordance is documented in the UI design doc but its form behaviour was unspecified.

### Decision

Activating "+ Add task" inside an expanded phase presents a form requiring a task name and offering an optional assignee picker (showing all `Person` records in `trip.participants`). Phase is derived from the currently expanded phase and is not user-editable. WHEN the trip has zero participants, the picker shows a "No participants yet" message and the form is still submittable with assignee unset.

### Rationale

The expanded phase is the natural anchor for "this task belongs here", and forcing assignee discovery upfront makes the picker visible to new users. Phase override would invite users to confuse "this trip's tasks" with the master list editing surface.

### Alternatives Considered

- **Name only, phase from context**: Simplest — Rejected because assignee discoverability suffers when the picker only appears in an after-create edit step.
- **Name + phase + assignee all editable**: Most flexible — Rejected because phase override on a per-trip manual task adds confusion without a clear use case.

### Consequences

**Positive:**
- Assignee is set at creation time, not as an afterthought.
- Phase ambiguity eliminated.
- First-time user experience (zero participants) is non-blocking.

**Negative:**
- Adding a task to a phase other than the currently expanded one requires expanding that phase first. Acceptable trade-off.

---

## Decision 4: Accordion state on trip re-entry

**Date**: 2026-05-12
**Status**: accepted

### Context

When a user returns to a trip's detail screen, the accordion can either restore their last-expanded phase or default to the current phase.

### Decision

On every appearance of Trip Detail, the current phase auto-expands. User's previous expansion choice is not persisted across navigations. When the current phase is non-expandable (no tasks AND not a packing phase, or compressed), no phase auto-expands.

### Rationale

The "current phase" framing is the timeline's primary value. Persistence would surprise users returning after several days with an outdated expanded phase.

### Alternatives Considered

- **Persist last expanded phase per trip**: Honours user intent — Rejected because the value of the timeline is "where am I now".

### Consequences

**Positive:**
- Predictable behaviour anchored to "now".
- No persistence storage required.

**Negative:**
- A user who expanded an earlier phase will re-expand it on each visit.

---

## Decision 5: Unmatched task display and count semantics

**Date**: 2026-05-12
**Status**: accepted (superseded prior draft after review)

### Context

When `currentlyMatchesRules` flips to false (per Phase 2 rules engine), the task is not deleted but must be surfaced somehow. The original draft counted only matching-or-pinned tasks in the header subline while still rendering unmatched-non-pinned tasks in the list, causing a visible-rows-vs-count mismatch that reads as a bug.

### Decision

Unmatched non-pinned tasks render dimmed in-line at the bottom of the task list (no separate section header). The phase header subline uses the format `"{completed}/{total} tasks · +{N} inactive"` where `total` and `completed` cover matching-or-pinned tasks and `N` is the count of inactive (unmatched-non-pinned) rendered tasks. When `N == 0`, the `+{N} inactive` suffix is omitted.

### Rationale

Surfacing the inactive count alongside the active count resolves the count-vs-row-count discrepancy without dedicating a section header. Users see at a glance that the list has more rows than the active task count.

### Alternatives Considered

- **Collapsed under "Previously matched" disclosure**: Hides clutter — Rejected because the click cost obscures items the user may want to act on.
- **Hidden entirely unless pinned**: Cleanest UI — Rejected because users lose easy access to historical context.
- **Count over all rendered rows**: Simplest — Rejected because the inactive count contributes to "what's expected for this trip now" mental model only confusingly.

### Consequences

**Positive:**
- Header count and visible row count are reconciled by the explicit `+{N} inactive` clause.
- Inactive rows remain discoverable and interactive.

**Negative:**
- Subline becomes slightly longer; Dynamic Type at AX2 must still fit it (covered by Req 10.5).

---

## Decision 6: Task editing scope and triggers

**Date**: 2026-05-12
**Status**: accepted

### Context

Phase 3 needs to support task-level edits beyond completion toggling. Long-press is reserved for `WhyDisclosure`, so the edit trigger needs a different gesture.

### Decision

Edit and delete are exposed via a trailing swipe (revealing "Edit" and "Delete" actions, Delete in the destructive tint) on each task row, with a `contextMenu` mirroring the same actions. Phase is not editable post-creation. Renaming, assignee reassignment, and deletion are supported for both manual and rule-driven tasks. No undo is provided in Phase 3 (listed as a Non-Goal).

### Rationale

Trailing-swipe-for-actions is the standard iOS pattern (Mail, Messages, Reminders all expose Edit + Delete on the trailing edge). Putting Delete on the trailing edge keeps the destructive action on the conventional side. The `contextMenu` provides a non-gesture path, distinct from the body long-press which is reserved for `WhyDisclosure`. The leading swipe is left unused in Phase 3 and is available for a future primary action.

### Alternatives Considered

- **No rename**: Rejected because users will inevitably want to clarify a task name.
- **Tap-to-edit a row**: Rejected because it conflicts with potential row-tap-to-toggle-checkbox affordance and is unconventional on iOS.
- **Leading swipe for Edit + Delete**: Rejected because it inverts the iOS convention (trailing swipe is the documented home for `swipeActions(edge: .trailing)`) and puts Delete on the non-destructive edge.

### Consequences

**Positive:**
- Gesture inventory is clean: tap = toggle, long-press = WhyDisclosure, trailing swipe = edit/delete.
- VoiceOver rotor actions (Req 10.3) provide the same operations without gestures.

**Negative:**
- Two trigger paths to maintain (swipe + context menu); design phase decides the canonical surface per platform.

---

## Decision 7: Rule-driven deletion uses a per-trip flag, not record removal

**Date**: 2026-05-12
**Status**: accepted (added after review)

### Context

The review identified that "delete a rule-driven task" cannot mean record removal because the rules engine would re-create it on the next compute. A persistent indicator is required, and the storage mechanism was not specified in the original draft.

### Decision

Deleting a rule-driven task sets a new boolean field `TripTask.userDeletedOnThisTrip` to `true` on the existing `TripTask` record (the record is not removed). The rules engine treats records with this flag as already-handled: it neither re-creates them nor un-sets the flag during subsequent compute/apply runs. The flag is scoped to the single `TripTask` record, so it applies to one rule on one trip. CloudKit merge for this field uses the same last-writer-wins policy adopted in Phase 2 for `currentlyMatchesRules` and `pinnedByUser`.

Deletion of manual tasks (`source: .manual`) still removes the `TripTask` record entirely; there is no analogous flag because the engine does not re-create manual tasks.

CloudKit conflict resolution for `userDeletedOnThisTrip` is deferred to Phase 5 alongside the broader sharing semantics for `currentlyMatchesRules` and `pinnedByUser` (Phase 2 did not define field-level merge for these). Until Phase 5 lands, cross-device divergence on this flag is an accepted limitation, consistent with Phase 2's deferral of sync-arrival callbacks (Phase 2 Decision 4).

### Rationale

A boolean column on `TripTask` is the smallest mechanism that satisfies the requirement. Keeping the deletion soft (record retained, row hidden) preserves the rules engine's referenced-set logic in `Compute.swift`. Deferring conflict resolution to Phase 5 matches Phase 2's stance that sync semantics live with the sharing work.

### Alternatives Considered

- **Separate deletion-tombstone model**: A `DeletedRuleTask(tripID, masterID)` record — Rejected because it duplicates state that already has a natural home on `TripTask` and adds a CloudKit zone-management concern.
- **Hard-delete the `TripTask` and add a referenced-set exclusion**: Rejected because cross-device sync would need to communicate the exclusion, requiring the same flag-on-a-record we just avoided.
- **Drop rule-driven deletion (allow delete only on manual tasks)**: Considered as a smaller-scope alternative. Rejected because users would have no straightforward way to remove a rule-driven task they don't want on this trip without unsetting the triggering attribute.

### Consequences

**Positive:**
- Smallest possible schema change (one boolean).
- Inherits Phase 2's CloudKit conflict resolution.
- Compatible with existing `Compute.swift` referenced-set logic.

**Negative:**
- User has no UI to view or restore user-deleted rule-driven tasks within Phase 3 (listed as a Non-Goal). Mitigation: a future phase can add a "show deleted on this trip" affordance.
- A trip with many user-deleted rule tasks accumulates rows in the database that are never surfaced; storage cost is negligible but worth noting.

---

## Decision 8: Trip-date-to-phase-date mapping is now canonical

**Date**: 2026-05-12
**Status**: accepted (added after review)

### Context

The review identified that "phase duration" was used in the compression rule without ever being defined. The existing `TripDetailView.state(for:today:start:end:calendar)` (Phase 1) defines past/current/future per phase but does not define each phase's calendar date range.

### Decision

The requirements document includes a canonical "Trip-date-to-phase-date mapping" table that defines each phase's date range as a function of trip `startDate` and `endDate`. The mapping is the authoritative definition of phase duration for all of Phase 3, including the compression rule (Req 3).

### Rationale

Making the mapping explicit and reference-able from the compression rule means "zero-duration" is unambiguously testable. The mapping aligns with the existing past/current/future logic in `TripDetailView.state(for:...)`.

### Alternatives Considered

- **Leave the mapping implicit, derive it from `state(for:...)`**: Rejected because the existing helper conflates date-range mapping with relative-to-today state computation, and the design phase would have to re-derive the mapping from the source.
- **Define the mapping in the design phase only**: Rejected because the compression requirement is uninterpretable without it.

### Consequences

**Positive:**
- Compression rule has a single source of truth.
- Test cases for short trips can be enumerated directly from the mapping.

**Negative:**
- The mapping introduces overlapping phases for short trips (e.g., `dayBefore` and `dayBeforeReturn` on the same calendar day in a 1-day trip). The design phase must decide the visual treatment for overlap; it is not a compression concern.

---

## Decision 9: `TripTask.assigneePersonID` uses `UUID?`, not `@Relationship`

**Date**: 2026-05-12
**Status**: accepted (added after review)

### Context

`MasterPackingItem.person` uses a SwiftData `@Relationship` to `Person`. The review noted this convention but recommended `UUID?` for the new field on `TripTask`.

### Decision

`TripTask.assigneePersonID` is stored as `UUID?` (a value reference), not a `@Relationship`. The existing `MasterPackingItem.person` `@Relationship` is preserved on the packing side; this decision does not propagate.

### Rationale

Two reasons. First, Req 4.8 / Req 9.4 require dangling references to be tolerated (e.g., `Person` is removed from the trip or deleted, but the task should still render without crashing); SwiftData `@Relationship` with `.nullify` or `.deny` does not cleanly express "leave the reference dangling and render without an avatar". Second, CloudKit cross-zone `CKReference` semantics are fragile under per-trip custom zones (Phase 5), and a value-based `UUID?` sidesteps zone-membership concerns entirely.

### Alternatives Considered

- **`@Relationship` with `.nullify`**: Rejected because nullifying on Person deletion silently loses the original assignee identity, and the rules engine's audit trail would be weaker.
- **`@Relationship` with `.deny`**: Rejected because it would block Person deletion entirely, whereas the requirement is "Person can be removed from trip; tasks remain".

### Consequences

**Positive:**
- Dangling references are first-class and survive Person removal / trip un-share / CloudKit zone changes.
- No new relationship semantics to debug under Phase 5 sharing.

**Negative:**
- The packing-side `@Relationship` convention is not extended to tasks. The inconsistency is documented but unresolved; a Phase 5+ decision may consolidate the two.

---

## Decision 10: `MasterTaskItem` does not gain a "default assignee" field in Phase 3

**Date**: 2026-05-12
**Status**: accepted (added after review)

### Context

The original draft Req 9.3 said engine-created tasks initialize `assigneePersonID` from "the master item's default assignee if such a default exists". The review confirmed no such field exists on `MasterTaskItem`, and adding it would silently expand Phase 3 into a Phase 2 model change with master-list UI implications.

### Decision

Engine-created tasks initialize `assigneePersonID = nil`. The user assigns afterwards. `MasterTaskItem` is not modified in Phase 3.

### Rationale

Adding a default-assignee field to `MasterTaskItem` would require: a Master Lists UI picker, schema migration, CloudKit field mapping, and a person-deletion-cascade rule on the master side — none of which are scoped to Phase 3. Deferring keeps Phase 3 focused.

### Alternatives Considered

- **Add `MasterTaskItem.defaultAssigneePersonID` in Phase 3**: Rejected because it pulls Phase 2 master-list UI work into Phase 3 without a corresponding decision-log entry on the Phase 2 side.

### Consequences

**Positive:**
- Phase 3 scope stays bounded.
- Master List remains person-agnostic for tasks (consistent with the design doc's current stance).

**Negative:**
- A user with strong "this task always goes to Kelsey" semantics has to set the assignee after each rule-driven creation. A future phase can revisit if user feedback demands it.

---

## Decision 11: Adopt versioned schemas as policy starting with `SchemaV2`

**Date**: 2026-05-12
**Status**: accepted (added after review)

### Context

Phase 1 introduced an empty `AppMigrationPlan.stages = []` placeholder. Phase 3 adds two new properties (`assigneePersonID`, `userDeletedOnThisTrip`) to `TripTask`. The first revision treated `SchemaV2` as a one-off introduction; the second review observed that two nullable additions don't on their own justify the boilerplate, and that the deeper question is whether versioned schemas are the project's policy.

### Decision

Adopt versioned schemas as policy from this point forward. Phase 3 introduces `SchemaV2` containing the updated `TripTask` model, with a migration stage in `AppMigrationPlan` initializing `assigneePersonID = nil` and `userDeletedOnThisTrip = false` on existing records. Subsequent schema changes — additive or not — go through new `SchemaV<N>` versions and explicit migration stages, even when SwiftData would tolerate in-place additions.

### Rationale

A two-property additive change is not by itself a strong case for a new schema, but committing to versioned schemas as a policy is: it keeps the migration log inspectable, gives CloudKit a clear schema-version handle to migrate by, and means the first non-additive change later doesn't have to litigate the policy question retroactively. Phase 3 is the natural place to set the precedent because it's the first migration after the empty Phase 1 placeholder.

### Alternatives Considered

- **Edit `SchemaV1` in place for this change**: Rejected because subsequent migrations would lose the audit trail, and CloudKit schema bumps would be implicit. Accepting the policy means accepting the boilerplate for this change too.
- **Defer the policy decision; do this change in place and version later**: Rejected because the first non-additive change would then need to backfill the boilerplate for the additive history, which is harder than starting versioned.

### Consequences

**Positive:**
- Migration history is explicit and ready for future, larger schema changes.
- CloudKit schema bumps have a versioned handle.
- No future "should this be a new schema?" debate per change.

**Negative:**
- Small amount of boilerplate per schema change, including this one.
