# Decision Log: Copy Master Packing Items

## Decision 1: Copy at the master-list level, not the trip level

**Date**: 2026-06-20
**Status**: accepted

### Context

The request was to "copy packing items to another person … the requirements for items should stay the same … a complete copy." In the data model, the rules ("requirements/conditions") that decide when an item appears live on `MasterPackingItem`, which is per-person. `TripPackingItem` carries no conditions of its own — it snapshots a name and references a `masterItemID`, with explainability computed on demand from the referenced master.

### Decision

Implement copying from the Master Lists tab. Copying a master packing item creates new `MasterPackingItem` records for each target person; the rules engine then materialises trip-level items onto matching trips.

### Rationale

The only place "requirements" exist as first-class, editable data is the master item. A master-level copy is therefore the only interpretation where "the requirements stay the same" is literally true and where the copy is reusable across all of a person's trips — matching the stated motivation ("everyone needs underwear/shirts").

### Alternatives Considered

- **Trip-level copy (Packing Sheet)**: Copy a `TripPackingItem` to another person within one trip. Rejected — trip items have no conditions, so "requirements stay the same" would only work by pointing the copy at the source person's master, which is semantically muddled and limited to a single trip.
- **Both surfaces**: Support master-level and trip-level copy. Rejected for v1 — doubles the UI/test surface for a use case the master-level copy already covers.

### Consequences

**Positive:**
- "Complete copy" is exact: name + conditions carried verbatim onto an independent record.
- Copies are reusable across all of the target person's trips automatically.

**Negative:**
- No one-off "just this trip" copy; that would require the trip-level surface, deferred.

---

## Decision 2: Skip target people who already own a same-name item

**Date**: 2026-06-20
**Status**: accepted

### Context

A target person may already have a master packing item with the same name as the source. The copy must decide between skipping, overwriting the existing item's conditions, or creating a duplicate.

### Decision

Skip such people. They are marked ineligible in the target picker and cannot be selected; the copy step re-checks defensively and skips any target that became a same-name owner between picker presentation and confirmation. Duplicate detection is a case-insensitive comparison of trimmed names.

### Rationale

Skipping never destroys a condition the target deliberately customised and never produces duplicate rows. Overwriting risks silently clobbering intentional per-person rules; creating duplicates produces two identical items on the list and on trips.

### Alternatives Considered

- **Overwrite conditions**: Replace the target's existing item's conditions with the source's. Rejected — silently discards deliberate per-person customisation.
- **Create duplicate**: Always insert. Rejected — produces duplicate rows in the master list and duplicate trip items.

### Consequences

**Positive:**
- No data loss, no duplicates.
- Picker communicates eligibility up front; the post-copy confirmation reports who was skipped.

**Negative:**
- Propagating *updated* conditions to someone who already has the item is not possible through copy — the user must edit that person's item directly.

---

## Decision 3: One source item per copy action, multiple target people

**Date**: 2026-06-20
**Status**: accepted

### Context

The copy could operate on a single source item (copied to many people) or on many source items at once (a grid of items × people).

### Decision

A copy action operates on exactly one source item and may target multiple people.

### Rationale

The single-item flow is a per-row action with a person multi-select — minimal UI and it covers the stated use case ("copy underwear to everyone"). Multi-source copy needs a distinct list selection mode for marginal benefit.

### Alternatives Considered

- **Many items to many people**: Selection mode over the master list ticking several items and several people. Rejected for v1 — larger UI scope; repeating the per-row action covers the need.

### Consequences

**Positive:**
- Small, row-local affordance consistent with the existing per-row Edit action.

**Negative:**
- Copying several distinct items to the same group is N repetitions of the action.

---

## Decision 4: Feature name `copy-master-packing-items`

**Date**: 2026-06-20
**Status**: accepted

### Context

The branch was `main` (a default branch), so the feature name is derived from the prompt. It names the specs/ folder and the implementation branch.

### Decision

Name the feature `copy-master-packing-items`.

### Rationale

It is scoped to the master-list surface, disambiguating from any future trip-level copy, and avoids the word "share", which already denotes CloudKit trip sharing in this codebase.

### Alternatives Considered

- **`copy-packing-items`**: Ambiguous about which surface (could read as trip-level). Rejected.
- **`share-packing-items`**: "Share" collides with CloudKit trip-sharing vocabulary. Rejected.

### Consequences

**Positive:**
- Unambiguous folder/branch name.

**Negative:**
- Longer than the alternatives.

---

## Decision 5: Post-copy confirmation host, and all-skipped as no-op success

**Date**: 2026-06-20
**Status**: accepted

### Context

Reviews found the requirements reused an "existing master-list toast pattern" that does not exist on the list surface — `transientToast` is hosted only on the editor sheets and Trip views, and the editor dismisses only on full success, so its toasts always render on a still-mounted view. Separately, the confirm-time duplicate recheck (AC 3.5) can skip every selected target, producing a successful action that creates nothing — a state the original ACs left undefined.

### Decision

The post-copy confirmation is shown on the Master Lists packing list surface after the picker dismisses (a toast host on the list, not on the dismissing picker). When the confirm-time recheck skips all selected targets so zero items would be created, the action is a no-op success: no master writes, no trip recompute, and a confirmation stating everyone was skipped.

### Rationale

A toast presented by the picker as it tears down would not render; the list is the surface that survives the action. Treating all-skipped as success (not failure) matches user intent — nothing went wrong, there was simply nothing new to create — and avoids running the engine for no change.

### Alternatives Considered

- **Keep the picker mounted to show the confirmation**: Rejected — leaves a spent picker on screen and diverges from the dismiss-on-success flow users already know.
- **Treat all-skipped as a failure**: Rejected — misrepresents a benign outcome and would surface an error toast for a correct no-op.

### Consequences

**Positive:**
- Confirmation reliably renders; the empty outcome is well-defined and testable.

**Negative:**
- Adds a toast host to the Master Lists list surface (new wiring, not free reuse).

---

## Decision 6: Guard the copy action for degenerate source items

**Date**: 2026-06-20
**Status**: accepted

### Context

`MasterPackingItem` permits `name == ""` and `person == nil` at the model level (only the editor draft validates these on save, and synced/legacy records bypass that). An empty trimmed name collides with every other empty-named item under case-insensitive duplicate detection, and an ownerless source has no meaningful "everyone except the owner" target set. The rules engine already skips nil-person masters, so an ownerless copy would never materialise anyway.

### Decision

Do not offer the copy action when the source item has no owner or an empty trimmed name (in addition to requiring at least two people).

### Rationale

These are degenerate states with no coherent copy semantics; guarding the entry point is simpler and safer than defining special-case behaviour for inputs the normal UI never produces.

### Alternatives Considered

- **Define copy behaviour for empty-name / ownerless sources**: Rejected — specifies behaviour for states the supported UI cannot create, for no user benefit.

### Consequences

**Positive:**
- Removes an undefined edge from the duplicate-detection and target-selection logic.

**Negative:**
- A user who somehow holds such a record cannot copy it without first giving it a name/owner via the editor.

---

## Decision 7: Copy is a new per-row affordance; tap still edits

**Date**: 2026-06-20
**Status**: accepted

### Context

Requirements AC 1.1 originally cited "the existing per-row Edit action" as the affordance to match. Design review found `MasterPackingList` rows have no per-row Edit action — the whole row is a `Button` that opens the editor on tap. The swipe + context-menu Edit pattern the requirement meant lives on the trip-level `PackingItemRow` (used only in `PackingSheet`), a different surface and model type.

### Decision

Introduce a new per-row affordance on the master packing list: a trailing swipe action and a long-press context menu, both labelled "Copy to people…", reusing the `PackingItemRow` swipe+context-menu pattern. The existing whole-row tap continues to open the item editor.

### Rationale

The whole-row `Button` already consumes the tap gesture, so a second action must be layered as swipe/long-press. Reusing the established `PackingItemRow` pattern keeps the interaction consistent across the two packing surfaces while leaving the familiar tap-to-edit behaviour intact.

### Alternatives Considered

- **Convert the row's tap target to a menu** (tap opens an action menu offering Edit + Copy): Rejected — adds a tap for the common Edit path and diverges from every other list row in the app.
- **Claim reuse of an existing master-list affordance**: Rejected — there is none; the design must state this is new UI.

### Consequences

**Positive:**
- Tap-to-edit is unchanged; copy is discoverable via the same gestures used for Edit elsewhere.

**Negative:**
- Net-new UI on the list (swipe + context menu), not free reuse.

---

## Decision 8: Post-copy recompute is best-effort; per-trip failures self-heal

**Date**: 2026-06-20
**Status**: accepted

### Context

AC 4.2 ties a deferred-update toast to the post-copy recompute failing. Review found `RulesEngineRunner.runForAllNonPastTrips` catches per-trip `apply` failures inside its loop (rollback + log + continue) and only throws at the top level (the trip / master-snapshot fetches). So a single trip's failure does not surface through the toast.

### Decision

Keep the existing runner contract unchanged. The deferred toast covers a top-level recompute failure only. A trip skipped by a per-trip failure self-heals on the next recompute trigger (cold launch, foreground, or the next master edit), exactly as the editor's saves behave today.

### Rationale

`runForAllNonPastTrips` is a shared path the master editor and several triggers already depend on. Changing it to surface per-trip failure counts for this feature would alter behaviour well outside the feature's scope for a rare, self-correcting case. The self-heal triggers already bound the staleness window.

### Alternatives Considered

- **Have the runner return/throw per-trip failure counts so the copy flow can report partial materialisation**: Rejected — scope creep into a shared engine path with broad blast radius, for a transient condition that the next trigger repairs.

### Consequences

**Positive:**
- No change to a load-bearing shared component; behaviour matches the established editor path.

**Negative:**
- A per-trip materialisation failure is silent to the user until the next recompute (logged only).

---
