# Decision Log: Packing Item Categories

## Decision 1: Name the new axis "category", not "group"

**Date**: 2026-06-27
**Status**: accepted

### Context

The ticket asks for "groupings" of packing items. However, the codebase already uses "group" for a different concept: `SheetGroup` is the pack/repack state-section axis in the Packing Sheet (still-to-pack / packed / not-bringing, and the repack equivalents), with `group.matches`, `group.headerTitle`, and accessibility announcements built around it.

### Decision

Name the new grouping axis "category" throughout the data model, UI, and code. Reserve "group" for the existing state-section concept.

### Rationale

Reusing "group" would overload an already load-bearing term and create ambiguity in code and accessibility text. "Category" is unambiguous and matches the user's intent (group by type, e.g. clothes, toiletries).

### Alternatives Considered

- **"group"**: Matches the ticket wording - Rejected because it collides with the `SheetGroup` state-section concept.
- **"type"**: Also unambiguous - Rejected as slightly less natural than "category" for free-text labels and more likely to read as a fixed enumeration.

### Consequences

**Positive:**
- No overloading of the existing `SheetGroup` vocabulary.
- Clear separation between the state axis (group) and the category axis.

**Negative:**
- Field name differs from the ticket's wording ("group"); requires a note in the spec.

---

## Decision 2: Category reflects the current master definition

**Date**: 2026-06-27
**Status**: accepted

### Context

Trip packing items snapshot `name` from their master item at creation and are never live-linked, so editing a master does not rename existing trip items. The question was whether category should follow this same snapshot rule or reflect the master live. If categories only applied to newly-added items, already-planned trips would not benefit until re-packed. After review (see Decision 5), it became clear that "live" cannot mean read-time derivation: shared-trip participants cannot see the owner's master lists (masters live in the private `globals` container, not the per-trip shared zone), so the category value must be physically stored on each `TripPackingItem`. The user was re-presented with the resulting cost and re-confirmed the live-reflect behaviour over the simpler snapshot alternatives.

### Decision

Category is a **managed projection**: it is physically stored on each trip item, and for master-derived items the owner's device re-applies (re-stamps) the master's current category onto existing trip items so they converge on it over time. Manual one-off trip items (no master) keep their own independently-set category and are never re-stamped. This is owner-driven and eventually-consistent, not a live read-time binding.

### Rationale

The user's goal is to organise packing without hunting for items, and they want that to apply to trips they have already planned. Read-time derivation is structurally impossible for participants, so denormalization onto the trip item is forced regardless. Given the value is stored anyway, re-stamping on master edits delivers the "categorise once, organises everything" behaviour the user asked for. Category is presentation-only metadata (it does not participate in rules matching), so re-stamping it does not undermine the reasons `name` is snapshotted (user-editable, trip-specific identity).

### Alternatives Considered

- **Pure snapshot like name**: Simplest, follows existing contract - Rejected by the user because existing trips would stay uncategorised until items are removed and re-added.
- **Snapshot + manual "apply to current trips" action**: Owner-initiated one-off push, no ongoing reconciliation - Rejected by the user in favour of automatic propagation.

### Consequences

**Positive:**
- Categorising an item once organises it on all current and future trips.
- Matches user expectation that a category is a property of the item, not the trip.

**Negative:**
- Requires a dedicated reconciliation step distinct from the rules engine, which by contract never rewrites existing trip items. The snapshot invariant is narrowed: it covers identity/display fields like `name`; category is a managed projection field outside it.
- Requires compare-before-write idempotency (Decision 6) to avoid mass CloudKit re-uploads, plus a conflict/authority rule and master-deletion semantics (Decision 6).

---

## Decision 3: Category suggestions are drawn from all items globally

**Date**: 2026-06-27
**Status**: accepted

### Context

When typing a category, the user wants previously-used names offered as options to avoid duplicate variants. Suggestions could be scoped per-person or drawn from every packing item.

### Decision

Offer the distinct categories used on any packing item, globally, as suggestions. Match case-insensitively and ignore surrounding whitespace so variants are presented as one suggestion.

### Rationale

The stated goal is avoiding multiple variants of the same category. A global list maximises reuse and prevents the same category being recreated per person.

### Alternatives Considered

- **Per-person suggestions**: Narrower list - Rejected because it allows per-person variants of the same category, the exact problem the feature aims to prevent.

### Consequences

**Positive:**
- Maximum consistency of category names across people and trips.

**Negative:**
- Suggestion source must gather distinct values across all packing items (a net-new query; no existing autocomplete pattern in the app).

---

## Decision 4: Group by category in both the Packing Sheet and Master Lists

**Date**: 2026-06-27
**Status**: accepted

### Context

The ticket focuses on "when packing" (the Packing Sheet). Master Lists currently groups items by person. The question was whether to add category grouping only to the Packing Sheet or to both surfaces.

### Decision

Group by category in both the Packing Sheet and Master Lists. In Master Lists, group by category within each person.

### Rationale

A consistent grouping model across both surfaces makes the Master List mirror how items will actually be packed, reducing cognitive mismatch between maintaining lists and packing.

### Alternatives Considered

- **Packing Sheet only**: Smaller scope, matches the literal ticket - Rejected in favour of consistency across both surfaces.

### Consequences

**Positive:**
- Consistent mental model between list maintenance and packing.

**Negative:**
- Adds a second grouping surface to build and test; increases UI scope.

---

## Decision 5: Define a normalized category key and a locale-independent sort

**Date**: 2026-06-27
**Status**: accepted

### Context

External review (Codex, Kiro) and the design-critic flagged that the requirements defined normalization for suggestions and ordering but not for the grouping key itself. Without one stable key, variants such as "Clothes", "clothes", and " Clothes " split into separate sub-headers (defeating the feature), and "alphabetical" ordering is locale-sensitive, so the same shared trip could render different header orders on different devices.

### Decision

Define a single normalized category key (trim, collapse internal whitespace, case-fold) that drives grouping, suggestion matching, and sorting. Order category headers by a locale-independent collation with the uncategorised section last. When spelling variants with the same key coexist, display a deterministic header label (the variant that sorts first under the pinned collation).

### Rationale

One normalized key guarantees that case/whitespace variants collapse into a single group everywhere, and a pinned collation guarantees that owner and participant devices render the same order for a shared trip. This closes the core correctness issue at the root rather than per-surface.

### Alternatives Considered

- **Group by exact stored string**: Simplest - Rejected because case/whitespace variants would fragment groups, undercutting the feature.
- **Locale-default sort**: Familiar per-device ordering - Rejected because it produces inconsistent header order across devices on a shared trip.

### Consequences

**Positive:**
- Variants collapse consistently; cross-device order is deterministic.

**Negative:**
- Diacritic-distinct values (e.g. "Café" vs "Cafe") remain distinct unless folding is extended; accepted for v1.

---

## Decision 6: Reconciliation authority, idempotency, and master-deletion semantics

**Date**: 2026-06-27
**Status**: accepted

### Context

Decision 2's managed-projection model introduces an owner-device reconciliation step. Review raised three risks: write-amplification (unconditional re-stamping dirties objects and triggers mass CloudKit uploads), concurrent writers (owner re-stamp vs participant edit on a shared record), and undefined behaviour when a master is deleted.

### Decision

Reconciliation is owner-only and compare-before-write (it writes a trip item's category only when it differs from the master's current value). It is implemented inside the existing rules-engine `compute`/`apply` pipeline (narrowing the engine invariant: category is the one projection field the engine may rewrite on existing items), not as a separate subsystem. Master-derived categories are owner-controlled and read-only for shared-trip participants; manual one-off categories are editable by whoever can edit the item. When a master is deleted, its derived trip items keep their last-applied category (freeze; not cleared). Cross-device recency is eventually-consistent, not guarded — see Decision 9.

### Rationale

Compare-before-write removes the only realistic performance/sync-churn risk. Owner-wins for master-derived categories removes the ambiguous two-writer conflict and matches the mental model that the category belongs to the master. Freezing on delete is the least destructive option and keeps existing trips organised.

### Alternatives Considered

- **Unconditional re-stamp every pass**: Simpler control flow - Rejected due to CloudKit write-amplification and conflict storms.
- **Clear category on master deletion**: "Live" purity - Rejected as destructive and surprising; freezing preserves organisation.
- **Last-writer-wins on shared category**: No authority rule - Rejected because owner and participant edits would clobber arbitrarily.

### Consequences

**Positive:**
- No redundant writes; predictable conflict behaviour; no data loss on master deletion.

**Negative:**
- Detecting "stale" master values across multiple owner devices would need extra state; v1 deliberately omits this (Decision 9), accepting a transient self-healing window.

---

## Decision 7: Suggestions are drawn from device-available data, accepting participant asymmetry

**Date**: 2026-06-27
**Status**: accepted

### Context

Decision 3 chose "global" suggestions. Review noted that the data spans two SwiftData containers (`globals` master items + `tripsLocal` trip items) which are not unioned by a single query, and that a shared-trip participant has no `globals` store at all — so a literal "global across all items" set is structurally different per role.

### Decision

Suggestions are the distinct categories present in the packing data available on the current device — the user's master items plus the trip items visible to them. A shared-trip participant, lacking the owner's master lists, draws suggestions from the trip items they can see. This asymmetry is accepted.

### Rationale

This is the only coherent definition given the container split and the sharing model; it maximises reuse on each device without inventing a cross-account category sync. The owner (who maintains the master lists) gets the full set, which is where category curation happens.

### Alternatives Considered

- **True global vocabulary synced across accounts**: Maximally consistent - Rejected as out of scope; it would require a shared category entity, contradicting the no-category-entity non-goal.

### Consequences

**Positive:**
- Coherent, implementable definition; strong reuse where curation happens.

**Negative:**
- Participants see a smaller suggestion set than the owner for the same shared trip.

---

## Decision 8: Unconditional CloudKit decode for the trip-item category field

**Date**: 2026-06-27
**Status**: accepted

### Context

`TripPackingItem` syncs via a hand-written record translator. The design phase first chose the guarded-read pattern ("absence = no change", as used for the structural `personSnapshotID`). Review showed this cannot represent a category *clear*: clearing to `nil` encodes as an absent CloudKit field, which guarded read ignores — so clears would never propagate, fatally for manual one-off items, which are never reconciled (Req 4.3) and have no re-stamp backstop.

### Decision

Decode `category` unconditionally in the translator (`item.category = record["category"] as? String`), matching the existing `note`/`subItems`/`Trip.countryCode` precedent.

### Rationale

It is the established posture for owner-editable optional scalars in this codebase, propagates clears correctly for both master-derived and one-off items, and the mixed-fleet wipe risk it carries is already accepted there.

### Alternatives Considered

- **Guarded read ("absence = no change")**: Safer against mixed-fleet wipe - Rejected because it cannot propagate a clear at all and breaks one-off items; also inconsistent with the adjacent `note` field.

### Consequences

**Positive:**
- Category clears propagate; consistent with existing fields.

**Negative:**
- A device on an older build omits the field, so a newer device reads it as cleared. Master-derived items self-heal via re-stamp; one-off items can be wiped during the rollout window. Accepted for a personal/family fleet.

---

## Decision 9: Multi-device recency is eventually-consistent, no version guard in v1

**Date**: 2026-06-27
**Status**: accepted

### Context

Compare-before-write tests inequality, not recency. The globals CloudKit mirror and the trip-sync pipeline converge independently, so a second owner device holding a momentarily stale master can re-stamp an older category over a newer one until its master syncs. Req 3.7 originally forbade overwriting with an older value (a hard "SHALL NOT"). Enforcing that needs a per-master generation/version marker carried on both records.

### Decision

Downgrade Req 3.7 to eventual consistency: reconciliation converges on the most recent master category; transient older values during cross-pipeline convergence are permitted and self-heal once the master syncs. No version guard and no extra CloudKit fields in v1. The user chose this over pre-provisioning generation-counter fields.

### Rationale

On a 2–4 device family fleet the window is brief, cosmetic, self-healing, and same-device echo is already suppressed by the trigger orchestrator. A version guard (plus its CloudKit fields and comparison logic) is disproportionate to that cost and runs against the project's simplicity ethos. If field data later shows the flicker matters, the guard can be added — at the cost of one more CloudKit schema promotion.

### Alternatives Considered

- **Lamport-style generation counter now**: Carry `categoryGeneration` (master) + `stampedCategoryGeneration` (trip item), gate re-stamp on recency - Rejected for v1 as premature; both external reviewers preferred pre-provisioning the fields as cheap insurance, but the user chose to defer.
- **Wall-clock or bare-UUID marker**: Simpler-looking - Rejected: wall clock is unreliable across devices and a UUID detects "different", not "newer".

### Consequences

**Positive:**
- No extra fields or comparison logic; simplest correct-enough behaviour for the target fleet.

**Negative:**
- A brief cross-device flicker is possible mid-sync. Enforcing strict recency later requires an additional (additive) CloudKit schema promotion.

---
