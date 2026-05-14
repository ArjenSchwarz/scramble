# Implementation Explanation: Phase 4 — Packing Sheet

Three-level explanation of how the Packing Sheet feature works. Use to validate completeness and catch logic gaps before pushing.

## Beginner — "What did we build?"

You can now open a Trip and tap the **Departure** phase to see a list of every person on the trip with a progress bar showing how much packing each one has done. Tap a person's row and a sheet slides up showing their packing list in three groups: *Still need to pack*, *Packed*, *Not bringing*. You can tick items off, skip items you're not bringing, restore items you skipped, and add a one-off item that isn't in the master list.

The **Day-before-return** phase shows the same thing but for repacking: *Still in suitcase*, *Back in suitcase*, *Left behind*. The "Left behind" group is read-only — items end up there if they were never packed or were skipped, and you can't toggle them, only see why they're there.

Long-press an item to see *why* the app put it on your list — for example, "This matches: Beach trip, More than 7 days". The app figures this out by looking at the master list's rule conditions and comparing them to the trip's attributes.

If you don't have any people on the trip yet, the Packing section politely tells you to add some from the trip details screen.

## Intermediate (5–10 yrs) — "How is it wired?"

`TripDetailView` owns a `@State packingSheetState: PackingSheetState?` and binds it to `.sheet(item:)`. The state is `Identifiable` keyed by `Person.id` so SwiftUI uses the same sheet instance across re-renders for the same person.

`AccordionTimeline.row(for:variant:proxy:)` branches its content `@ViewBuilder` on phase: `.departureDay` and `.dayBeforeReturn` render `TaskListSection` + `PackingSummarySection`; everything else renders `TaskListSection` alone. The packing section receives an `onOpenSheet: (Person, PackingMode) -> Void` callback that bubbles up to `TripDetailView` and sets `packingSheetState`.

`PackingSummarySection` calls `PackingListHelpers.countsByPerson(trip)` **once per body evaluation** and looks up each row's `PackingCounts` by `Person.id`. Earlier drafts called `counts(for:in:)` inside the `ForEach` — O(participants × packing items) — and the single-pass helper exists to avoid that fan-out. The same anti-pattern is avoided in `PackingListHelpers.phaseSubline`, which sums in one pass over `trip.packingItems` rather than calling `counts(for:in:)` per participant.

`PackingSheet` composes three `PackingItemGroup` children. It pre-filters `personItems = PackingListHelpers.itemsForPerson(trip, person:)` **once** at the body level and hands the array to each group, which then filters by its own predicate (`SheetGroup.matches(_:)`). Without this, three groups × one filter per body = three full scans of `trip.packingItems`.

Item-level mutations (`toggleState`, `skipOrRestore`) commit via `try modelContext.save()` immediately so the underlying timeline reads up-to-date counts the moment the sheet dismisses. Save failure logs `[PackingSheet.save-failed]` and lets SwiftData re-render the prior state on the next body eval — no error banner in v1.

VoiceOver focus handoff is the trickiest piece. On `PackingSheet.body.task` we run `Task.sleep(500ms)` before setting `headerFocused = true` because the sheet's accessibility frame is not yet built when `.onAppear` fires. On dismiss, `TripDetailView.handlePackingSheetDismiss` checks whether the originating person is still in `trip.participants`: if yes, it sets the `@AccessibilityFocusState` binding to that person's id; if no, it posts `UIAccessibility.Notification.layoutChanged` so VoiceOver picks the next focusable element heuristically. The originating person is remembered in `lastOpenedPackingPerson` because `.sheet(item:)` clears the bound state to `nil` **before** `onDismiss` fires.

Manual-add is sheet-on-sheet: `PackingSheet` presents `PackingItemForm` via an inner `.sheet(item: $pendingForm)`. The form has divergent save semantics from `TaskForm` — on failure it keeps the form open with an inline error and the user's typed input intact, calling `modelContext.delete(item)` (for `.add`) or `modelContext.rollback()` (for `.edit`) to undo the in-memory mutation.

`WhyDisclosureView` migrated from `init(reason:, phaseColour:)` to `init(reason:, style:)` where `style: WhyDisclosure.Style` is `.tasks(phaseColour:)` or `.packing(personColour:)`. Internal mapping: tasks → 8% background + 20% border; packing → 6% background + no border. `WhyResolver` gained a second `@MainActor` overload for `TripPackingItem` mirroring the task-side four-branch decision tree. The ~30-line duplication is deliberate; abstracting via a protocol would re-touch shipped Phase 3 code.

## Expert — "What load-bearing decisions and invariants matter?"

**Determinism.** The rules engine is unaffected by Phase 4. The sheet only writes `state` on `TripPackingItem`; it never writes `currentlyMatchesRules` or `pinnedByUser`. Engine writes and user gestures can interleave during a CloudKit sync arrival without conflict because they touch disjoint fields. `Req 8.5`'s "engine write wins" is correct framing for the field the engine touches (`currentlyMatchesRules`); the user's gesture on `state` is not aborted.

**`.task(id: Set<UUID>)` participant-removal watcher.** Array keying would re-fire on every SwiftData relationship re-fault or CloudKit reorder because the array's identity changes; `Set<UUID>` compares by membership, which is the invariant we care about. The watcher calls `onDismiss()` when the bound person leaves the set. `TripDetailView.handlePackingSheetDismiss` then chooses focus restoration vs `layoutChanged` based on whether the person is still present at dismiss time.

**Single-pass helpers.** `PackingListHelpers` has three multi-pass risks. The fix in each case is a Dictionary-keyed pass:
1. `phaseSubline` — one pass over `trip.packingItems`, filtering by participant set membership.
2. `countsByPerson` — one pass building four `[UUID: Int]` dictionaries, materialised into a `[UUID: PackingCounts]` map.
3. `PackingSheet.body` — one `itemsForPerson` call passed down to all three `PackingItemGroup` children.

**Schema invariance (Decision 6).** No `SchemaV3`. `TripPackingItem` already carries `state`, `source`, `currentlyMatchesRules`, `pinnedByUser`, `masterItemID`, `name`, `person`, `trip`. Phase 4 is additive at the UI + explainability layers only.

**Dimming counts in totals (Decision 5).** Unlike tasks (where `+N inactive` excludes dimmed from the headline counter), packing counts include dimmed items because the user's mental model for packing is physical contents of the suitcase. `PackingListHelpers.counts` does no `currentlyMatchesRules` / `pinnedByUser` filtering.

**Skip is the only removal (Decision 3).** No hard-delete affordance; both manual and rule-driven items go to `.excluded` on Skip and back to `.unpacked` on Restore. Decision rationale: avoids the asymmetric delete model Phase 3 has for tasks, and "Not bringing" surfaces the reversible decision.

**Rename does not surface master-name divergence (Decision 8).** `WhyDisclosureView` for a renamed rule-driven item shows `Reason.ruleMatched(text)` / `Reason.ruleNoLongerMatches` with the same Phase 3 strings; the master's original name is not surfaced. Revisit if usage patterns demand it.

## Completeness Assessment

**Fully implemented:**
- Req 1.1 – 1.10: per-person summary block, sort order, status branches, progress ratio, subline composition.
- Req 2.1 – 2.9: presentation, drag indicator, header, counter, close button, scroll-to-top on open, body propagation, participant-removal auto-dismiss, Reduce Motion (delegated to iOS `.sheet` defaults).
- Req 3.1 – 3.9: pack-mode three groups, checkbox colour rules, Skip/Restore actions, dashed placeholder for `Not bringing`, dimmed-row opacity.
- Req 4.1 – 4.8: repack-mode three groups, read-only "Left behind", checkbox colour rules, dimmed handling.
- Req 5.1 – 5.8: manual-item creation, 200-char cap, defaults, sheet-on-sheet, ordering after dismiss.
- Req 6.1 – 6.5: edit affordance via swipe + context menu; rename only; trip-level renames are local.
- Req 7.1 – 7.10: WhyDisclosure long-press, single-open-at-a-time, on-demand condition matching, person-coloured variant, every-group inclusion.
- Req 8.1 – 8.5: immediate save, summary propagation, no engine re-trigger, save-failure logging, engine-write-wins interleave.
- Req 9.1 – 9.9: VoiceOver labels, rotor actions, 44pt min targets, focus handoff with 500ms delay, group-move announcements, Escape key cascade.
- Req 10.1 – 10.3: engine invariant documentation; sheet writes only `state`, scoped to the active trip.

**Partial / acknowledged gaps:**
- Italic condition tags on `PackingItemRow` (Req 3.3 mentions them) are not rendered. Carryover from Phase 3's `TaskRow` which also omits them; flag in the review HTML.
- 10 `XCTSkip` placeholders in `PackingSheetUITests.swift` document missing infra: save-failure injection hook, hardware-keyboard XCUI fixture, mid-test fixture mutation, colour-key debug marker, concurrent engine apply hook. These are deliberate placeholders, not gaps.

**Missing:** None against the documented spec.
