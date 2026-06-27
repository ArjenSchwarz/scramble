# Decision Log: Phase 4 — Packing Sheet

## Decision 1: Spec name and scope

**Date**: 2026-05-14
**Status**: accepted

### Context

Phase 4 builds the Packing Sheet UI and per-person packing summary blocks per `docs/implementation-phases.md` §"Phase 4 — Packing Sheet". Naming must match the existing convention used by `specs/phase-1-foundation`, `specs/phase-2-rules-engine`, and `specs/phase-3-timeline-tasks`.

### Decision

The spec is named `phase-4-packing-sheet` and is scoped to: per-person packing summary blocks on `departureDay` / `dayBeforeReturn`, the `PackingSheet` with pack and repack modes, manual one-off item creation (pack mode only), item renaming, `WhyDisclosure` reuse with the person-coloured variant, dimmed rendering of unmatched-non-pinned items, and resolution of UI design doc open question 1 (presentation detents).

### Rationale

Matches phases 1-3. The "packing-sheet" suffix differentiates from later phases that touch the same screen (Phase 5 CKShare on the per-trip surface, Phase 6 notification deep-links).

### Alternatives Considered

- **`phase-4-packing`**: Shorter — Rejected because Phase 4 ships both the summary blocks and the sheet; the sheet is the headline deliverable.

### Consequences

**Positive:**
- Naming is self-describing and grep-friendly.

**Negative:**
- Slightly longer directory name.

---

## Decision 2: Resolve open question 1 — single `.large` detent

**Date**: 2026-05-14
**Status**: accepted

### Context

UI design doc §"Engineering Decisions and Open Questions" item 1 flagged `presentationDetents` configuration as undecided. The doc's body describes the sheet as "~82% screen height" with "standard `.presentationDetents` behaviour (large detent), swipe-down to dismiss."

### Decision

The packing sheet uses a single `.large` detent with `presentationDragIndicator(.visible)` and swipe-down-to-dismiss enabled. No `.medium` or custom detent is offered in v1.

### Rationale

`.large` is what the UI doc body already describes; adding a medium detent would force users to make a routing decision before they have content to act on, and a custom detent invites visual drift across iOS versions. The packing surface is task-dense — grouping into three sections benefits from the full sheet height. Swipe-down dismiss is iOS standard and already accommodated by the body close button. For light-load trips (e.g., 8 items per person), `.large` will feel disproportionately tall; we accept that asymmetry for v1 and revisit if user testing flags it as a problem.

### Alternatives Considered

- **`.large` + `.medium`**: Two-detent configuration — Rejected because there is no obvious "compact" packing summary worth showing at medium height; the per-person summary block on the timeline already serves that need.
- **Custom detent (e.g., 0.82)**: Approximation of the "~82%" hint — Rejected because `.large` already accounts for safe areas correctly and Apple's automatic adjustments. Hardcoding 0.82 invites pixel-level discrepancies across screen sizes.

### Consequences

**Positive:**
- Resolves Phase 1 / UI doc open question 1.
- Deterministic, single-detent behaviour matches `.sheet()` defaults so testing surfaces are minimal.

**Negative:**
- Power users who would prefer a peeking medium detent are not served in v1; can be revisited as a Phase 6 polish item if requested.

---

## Decision 3: Exclusion is the only removal mechanism

**Date**: 2026-05-14
**Status**: accepted

### Context

Phase 3 introduced an asymmetric deletion model for tasks: manual tasks (`source: .manual`) get hard-deleted, rule tasks (`source: .rule`) get a `userDeletedOnThisTrip` flag so the engine treats them as already-handled. For packing items the analogous concern is "I don't want this item on this trip." The existing `PackingState.excluded` value already encodes that intent.

### Decision

In v1, Phase 4 does not expose a `Delete` affordance for packing items. The `Skip` inline action (and its "Restore" inverse) is the only mechanism for removing an item from the active pack list; it sets `state = .excluded` for both manual and rule-driven items. No `userDeletedOnThisTrip`-equivalent flag is added to `TripPackingItem`.

### Rationale

`.excluded` is reversible and surfaces the item under "Not bringing" so the user can revisit decisions; using it as the sole removal mechanism avoids divergence between manual and rule-driven items at the data layer. Hard-deleting manual packing items would also propagate a delete record across the share post-Phase-5. Asymmetry on the task side (Phase 3 Decision 7) was justified because phase-bound tasks have no "excluded" semantic; packing has one natively. The interaction with Decision 5 (dimmed items count toward progress) is acknowledged: a dimmed item the user wants to remove still nudges them toward Skip, leaving "Not bringing" populated over time. We accept that drift in v1; revisit if "Not bringing" becomes noisy enough to need a bulk-clear affordance.

### Alternatives Considered

- **Mirror Phase 3 exactly**: Hard-delete for manual items, flag for rule items — Rejected because it creates two surfaces for "I don't want this" (Skip and Delete) without a user-facing distinction that justifies them.
- **Add `userDeletedOnThisTrip` flag**: Rejected for the same reason plus the model-migration cost without a corresponding behavioural gain.

### Consequences

**Positive:**
- Single, reversible mechanism that scales identically to manual and rule items.
- No schema migration in Phase 4.

**Negative:**
- A user who created a manual item by typo has to "Skip" it rather than delete; the item lingers in "Not bringing" until the trip is deleted. Acceptable trade-off for v1.
- Combined with Decision 5, dimmed items the user wants gone require an extra step (Skip) and then occupy "Not bringing" indefinitely.

---

## Decision 4: Edit affordance limited to rename

**Date**: 2026-05-14
**Status**: accepted

### Context

Phase 3 allowed editing a `TripTask`'s name and assignee. For `TripPackingItem`, the `person` field is fundamental to grouping (the entire packing surface is person-scoped), `conditions` lives only on the master, and `source` / `masterItemID` are stable references.

### Decision

The Phase 4 edit affordance permits renaming the item only. Changing assignee, conditions, source, or master link is out of scope.

### Rationale

Renaming covers the realistic on-trip use case (typo correction, clarifying note). Changing the assignee would re-shuffle which sheet the item belongs to and complicates progress accounting mid-trip without a clear user benefit. Conditions belong on the master; trip-level rule items are snapshots. Source / master link are stable references — editing them turns rule items into manuals (or vice versa) without a workflow that demands it.

### Alternatives Considered

- **Allow assignee change**: Move item to another person's list — Rejected because a typo on assignee is corrected by skip-and-add-on-the-correct-person; cross-person move is a workflow that has not been requested.
- **No edit affordance at all**: Rely on skip-and-re-add — Rejected because rule-driven items can't be re-added by the user; only the engine can recreate them.

### Consequences

**Positive:**
- Edit surface is small, easy to test, and parallels Phase 3 in shape (swipe action + context menu).

**Negative:**
- A user who needs to reassign an item to a different person must skip the item on the wrong person and add a manual item on the correct person. Acceptable for v1.

---

## Decision 5: Dimmed items still count in progress and counters

**Date**: 2026-05-14
**Status**: accepted

### Context

Phase 3 Req 5.3 defined task counts as "items with `currentlyMatchesRules == true OR pinnedByUser == true`" plus a `+N inactive` suffix for unmatched-non-pinned tasks. For packing items, the same dimmed concept applies (Req 4.4 parallel). The question is whether the per-person progress bar and counters in Phase 4 should follow the same "exclude inactive" rule.

### Decision

Per-person progress bars, sheet header counters, and summary-row status labels SHALL include dimmed (unmatched-non-pinned) items in their counts. There is no `+N inactive` suffix on the packing surface.

### Rationale

The user's mental model for packing is "what is in my suitcase right now" — a dimmed-but-physically-packed item is still in the suitcase and should count. Tasks are different: a dimmed task is "no longer required by your trip configuration" and excluding it from counts matches user intent. Packing is physical state; tasks are required-vs-not state. Splitting the counter with `+N inactive` would obscure the physical reading on the progress bar.

### Alternatives Considered

- **Exclude dimmed from counts, mirror Phase 3 tasks**: Rejected because the progress bar would be inconsistent with the suitcase's actual contents.
- **Show dimmed in counter denominator only, not numerator**: Rejected because it produces nonsensical "5/14 packed" ratios that under-count packed items.

### Consequences

**Positive:**
- Progress bars and counters match physical reality.
- Single, simple counting rule across the summary block and sheet header.

**Negative:**
- A user who used to need a "raincoat" rule but no longer does (so the item is now dimmed) sees it counted toward their total until they skip it. Trade-off accepted; the dimming + WhyDisclosure already signals the staleness.

---

## Decision 6: No schema change in Phase 4

**Date**: 2026-05-14
**Status**: accepted

### Context

Phase 3 Decision 11 established that every schema change gets a new `SchemaV<N>` and an explicit migration stage. `TripPackingItem` already exposes `state`, `source`, `currentlyMatchesRules`, `pinnedByUser`, `masterItemID`, `name`, `person`, and `trip` — every field Phase 4 needs.

### Decision

Phase 4 ships without a new `SchemaV<N>`. The current schema (V2, from Phase 3) remains in force.

### Rationale

There is no new persisted state required by the packing surface. `userDeletedOnThisTrip`-equivalent for packing is explicitly rejected per Decision 3. Bumping the schema version when no model has changed would be pure ceremony.

### Alternatives Considered

- **Bump to `SchemaV3` as a no-op for consistency**: Rejected because Decision 11's policy is "every schema *change* gets a new version" — there is no change to encode.

### Consequences

**Positive:**
- No migration work; Phase 4 is purely additive at the UI layer plus the explainability layer.

**Negative:**
- None of consequence.

---

## Decision 7: No pin/unpin affordance in Phase 4

**Date**: 2026-05-14
**Status**: accepted

### Context

The `TripPackingItem.pinnedByUser` flag is load-bearing in the active/dimmed classification (per cross-phase preliminaries in requirements.md). The schema has carried the flag since Phase 1, but no phase has yet shipped a UI affordance to set it. Phase 3 tasks have the same gap.

### Decision

Phase 4 does not introduce a pin/unpin UI for packing items. All items created during Phase 4 (rule-driven by the engine, manual via Req 5.3) initialise with `pinnedByUser = false`. The flag's UI surface is deferred to a later phase.

### Rationale

The dimmed-row treatment plus skip/restore already covers the user's "I want to keep this even though it no longer matches" intent: they can simply leave the dimmed item alone, and it remains in their list. A dedicated pin affordance is therefore not necessary for the v1 packing experience. Deferring the affordance keeps Phase 4's UI surface to the documented scope and avoids two affordances (pin + skip) on a row that already carries checkbox, edit, why-disclosure, and skip.

### Alternatives Considered

- **Ship pin in Phase 4**: Add a "Pin to this trip" context menu item — Rejected because the user need is unverified and the affordance density on a row is already high.
- **Ship pin in Phase 3 tasks and Phase 4 packing together**: Rejected because Phase 3 has shipped and adding pin retroactively would expand the spec's scope post-merge.

### Consequences

**Positive:**
- Row affordance density stays low.
- Defers a design decision (where does the pin live?) until v1 ships and feedback arrives.

**Negative:**
- A power user who wants to lock a dimmed item in cannot do so explicitly in v1; they rely on the "dimmed-but-still-visible" treatment.

---

## Decision 8: Trip-level rename does not surface master-name divergence

**Date**: 2026-05-14
**Status**: accepted

### Context

Req 6.3 confirms that renaming a rule-driven `TripPackingItem` does not alter the corresponding `MasterPackingItem` (the trip-level `name` is a snapshot per `docs/scramble-design-doc.md` and Phase 1's invariant). A peer-review pass flagged that, after such a rename, the `WhyDisclosure` for that item could surface the master's current name to make the divergence visible.

### Decision

Phase 4 does not surface the master-name in `WhyDisclosure` when the trip-level rename has diverged from it. The disclosure text remains Req 7.4 – 7.7 verbatim.

### Rationale

Surfacing the master name in the disclosure adds a new piece of information that the user has not asked for and that would clutter the explainability panel for the common case (no rename, no divergence). The disclosure's purpose is to answer "why is this here?", not "what was this originally called?". If users do start renaming heavily and find the divergence confusing, the disclosure is the natural place to add the surfacing later.

### Alternatives Considered

- **Append `"Originally: {master name}"` when the trip name differs**: Rejected for v1 because it complicates the disclosure text for a usage pattern that has no observed demand.
- **Block trip-level rename of rule items entirely**: Rejected because the rename use case (typo correction, clarifying note) is real and Phase 3 already permits it for tasks.

### Consequences

**Positive:**
- `WhyDisclosureView` parameterisation in Phase 4 stays small (colour + Reason).
- No new copy strings.

**Negative:**
- A user who renames a rule-driven item, then forgets, has no in-app pointer back to the master's name.

---

## Decision 9: Manual-item form is presented as sheet-on-sheet

**Date**: 2026-05-14
**Status**: accepted

### Context

Req 5.2 presents an "Add item for {short-name}" form when the user activates the dashed affordance inside an already-presented packing sheet. iOS / SwiftUI offers several patterns: nested `.sheet`, navigation push within the sheet, or a custom `.medium`-detent transition inside the same sheet.

### Decision

The add-item form is presented as a separate `.sheet` modally on top of the packing sheet. Dismissing the inner form returns the user to the packing sheet without dismissing the outer sheet.

### Rationale

Nested sheets are the iOS-standard pattern for a focused secondary task. `NavigationStack` push inside a sheet works but introduces a back-button affordance the user did not ask for. A custom detent transition inside the same sheet would require swapping the sheet's body content and would lose the existing scroll/disclosure state on dismissal. Phase 3 already uses a `.sheet`-based form (`TaskForm`) for the same scenario; matching that precedent keeps the two surfaces consistent.

### Alternatives Considered

- **`NavigationStack` push inside the sheet**: Adds a back chevron that the user did not request — Rejected.
- **Inline form expansion at the bottom of the sheet**: Requires the user to scroll past three groups to reach it — Rejected.
- **Replace sheet body via a custom transition**: Loses scroll state and is non-standard — Rejected.

### Consequences

**Positive:**
- Matches Phase 3's `TaskForm` pattern.
- Outer sheet's scroll, disclosure, and group state are preserved on inner dismiss.

**Negative:**
- Two-sheet stack is a known iOS UI complexity (e.g., swipe-down can target the inner or outer sheet depending on framework version); accept and validate during testing.

---

## Decision 10: Remove the WhyDisclosure long-press explainability from the packing sheet

**Date**: 2026-06-26
**Status**: accepted — supersedes the packing-side parts of Req 6.1 / 6.5 / 7.1–7.10 / 9.2 / 9.9 (this spec) and Phase 6 Req 8.5 / 9.5 (the `PackingItemRow` carve-out only)

### Context

Phase 4 Section 7 specified a `WhyDisclosure` explainability panel for packing items, revealed by a long-press on the item name (Req 6.5) and mirrored by a `"Why is this here?"` VoiceOver custom action (Req 9.2, hardened in Phase 6 Req 9.5). In practice the owner found the packing-side surface unused, and the long-press made the (already action-dense) packing rows feel noisy — every name-region press armed a gesture, and the panel most often resolved to a low-value reason. The packing masters frequently fail to resolve from the trip's local context, so the panel often showed only the generic "added by a rule that has since been removed" message regardless of the item.

### Decision

Remove the long-press `WhyDisclosure`, its inline panel, the `"Why is this here?"` VoiceOver custom action, and the supporting per-row state/fetches from `PackingItemRow` / `PackingSheet`. The task-side explainability (`TaskRow` / `TaskListSection`, Phase 3) is unchanged. The shared `WhyResolver` and `WhyDisclosureView` stay in place — they are still used by the task surface; their `TripPackingItem` overload and the `WhyDisclosure.Style.packing` case become test-only but are retained rather than torn out (removing them would churn the shared resolver for no behavioural gain and lose existing test coverage).

### Rationale

The feature was a confirmed product cost (annoying gesture) with little realised benefit on the packing side. Removing it also deletes per-row SwiftData fetches that ran on accessibility-action setup and on every disclosure-open / attribute-change / rules-change event — a net efficiency win on the packing sheet. Scoping the removal to packing (leaving tasks intact) keeps the change small and avoids touching Phase 3's shipped, still-wanted task explainability.

### Alternatives Considered

- **Keep the VoiceOver action, drop only the long-press**: Rejected — the action exposes the same panel; keeping it is inconsistent with the removed visual affordance and still pays the per-row resolver fetch.
- **Fix the underlying master-resolution bug instead of removing**: Rejected — the owner does not want the surface at all on packing, independent of the bug.
- **Replace long-press with a tap affordance (e.g., a "?" glyph)**: Rejected — adds another glyph to an already-dense row for a feature the owner does not use.

### Consequences

**Positive:**
- Simpler, quieter packing rows; the name region no longer arms a gesture.
- Eliminates per-row `WhyResolver.reason(...)` fetches on the packing sheet.
- Task explainability is untouched.

**Negative:**
- Packing items lose in-app "why is this here?" explainability (sighted and VoiceOver). Accepted per owner request.
- `WhyResolver.reason(for: TripPackingItem,…)` and `WhyDisclosure.Style.packing` now have no production caller (test-only); a future reader must not mistake them for dead code — see `docs/agent-notes/packing-sheet.md`.
- The source-of-truth UI doc (`docs/scramble-ui-design-doc.md`) still describes packing long-press explainability in places; this ADR is the authoritative override.

### Impact

`Scramble/Scramble/Components/PackingItemRow.swift`, `Scramble/Scramble/Features/Trips/PackingSheet.swift`; removed tests in `PackingItemRowAccessibilityTests.swift` and `PackingSheetUITests.swift`; notes updated in `docs/agent-notes/packing-sheet.md` and `docs/agent-notes/accessibility.md`.

---
