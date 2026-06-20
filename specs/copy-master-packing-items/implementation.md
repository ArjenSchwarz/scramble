# Implementation: Copy Master Packing Items

## Beginner Level

### What this does
In the Master Lists tab, each person has their own list of packing items, where every item carries the rules that decide when it should appear on a trip (e.g. "only beach trips"). Re-typing "underwear" or "shirts" for each family member is tedious. This feature adds a **"Copy to people…"** action to any item: pick the other people, and each gets their own independent copy — same name, same rules. The app then automatically adds the copies to every trip they apply to.

### Why it matters
One action replaces re-entering the same item per person. The copy behaves exactly like an item you authored by hand, including showing up on the right trips with no further effort.

### Key concepts
- **Master item** — a reusable per-person template: a name plus the conditions that decide when it appears.
- **Rules engine** — the part of the app that reads templates and drops real items onto each trip. We only create templates; the engine materialises the trip-level items.
- **Independent copy** — the copies don't stay linked to the original. Editing one later doesn't change the others.

## Intermediate Level

### Components
- `MasterPersistence.copyPacking(source:toPersonIDs:in:)` — creates one `MasterPackingItem` per eligible target person (de-duped ids, skips anyone already owning a same-name item), inserting into the `globals` store without saving. Returns a value-only `CopyResult` (`createdCount` + `copiedNames` + `skippedNames`). Pure helpers `normalizedName` (the single trim+lowercase comparator) and `copyToastMessage` build the confirmation text.
- `CopyPackingItemSheet` — the target-person picker. A `@MainActor static eligibleTargets(source:people:)` helper (the unit-tested seam) lists everyone except the owner minus same-name owners, using the same `normalizedName` over `Person.masterPackingItems` that `copyPacking` uses. Multi-select, ineligible rows disabled + labelled, empty-state when no one's eligible, confirm gated on selection ∩ eligible. Passes raw selected ids to its callback.
- `MasterPackingList` — hosts the per-row "Copy to people…" affordance (swipe + context menu, gated on source eligibility), a single `SheetTarget` enum (`create`/`edit`/`copy`) behind one `.sheet(item:)`, the confirmation toast, and `performCopy`.

### Implementation approach
`performCopy` mirrors the established `MasterPackingEditor.runEngineAndDismiss` sequence: `copyPacking` → `modelContext.save()` (rollback + toast on throw) → `RulesEngineRunner(...).runForAllNonPastTrips()` (best-effort) → confirmation toast. The branch selection is extracted into a pure `copyOutcome(createdCount:save:runEngine:)` returning `CopyOutcome` (`nothingToCopy` / `saveFailed` / `copied(deferred:)`), so the save-failure, all-skipped, and deferred-recompute paths are unit-testable without forcing a real SwiftData save failure.

### Trade-offs
- **Conditions copied by value, not by raw blob.** Passing the decoded `ItemConditions` value into the initializer gives deep equality and independence for free (value semantics), and re-encodes a distinct `conditionsData`. A corrupt source blob would copy as `.always` (its decode fallback) — acceptable, since the engine already treats corrupt blobs that way.
- **Master save is atomic; trip materialisation is best-effort.** Masters and trips live in different containers (`globals` vs `tripsLocal`), so a per-trip recompute failure can't roll back the committed masters. Per-trip failures self-heal on the next recompute trigger.
- **Skip, not overwrite, on same-name collision.** Never clobbers a target's deliberately customised conditions.

## Expert Level

### Technical deep dive
- **Single comparator over a single data source.** Both the picker's display eligibility and `copyPacking`'s confirm-time skip read `Person.masterPackingItems` through `MasterPersistence.normalizedName`. A test proves SwiftData surfaces an *unsaved* in-context same-name insert through that relationship, so the AC 3.5 defensive re-check holds against a picker→confirm race, not just saved state.
- **Container boundary is load-bearing.** `LocalWriteHook.mapping(for:)` returns `nil` for `Person`/`Master*` (globals), so master creation bypasses the hook and is saved via the globals `modelContext`; only the engine's trip-zone writes go through the hook. Copied masters reach other devices via the `globals` CloudKit mirror; copied trip items reach shared-trip participants via the hook-backed engine apply path (AC 4.3) — both reused, no feature-specific sync code.
- **Deferred-toast scope.** `runForAllNonPastTrips` catches per-trip `apply` failures internally (rollback + log + continue) and only throws at the top level (the trip/master fetches). The deferred-update toast therefore covers a top-level recompute failure; a single trip's failure is silent until the next trigger (Decision 8 — the shared runner is deliberately unchanged).

### Architecture impact
No schema change. The feature is additive: one new view, one persistence helper family, and a per-row affordance + toast host on an existing list. `SheetTarget` collapses the list's sheet presentations into one modifier (avoiding the SwiftUI multiple-`.sheet` conflict), with a `"copy-\(id)"` discriminator preventing `.copy`/`.edit` identity collision.

### Potential issues / things to watch
- The picker's eligibility scan is O(people × items-per-person), recomputed once per body pass — fine at family scale, would warrant memoisation if rosters grew large.
- `performCopy`'s end-to-end save-failure/deferred branches are now covered at the `copyOutcome` seam, not via a forced-SwiftData-failure integration test; the seam is the contract under test.

## Completeness Assessment

**Fully implemented** — all 21 acceptance criteria (1.1–1.3, 2.1–2.6, 3.1–3.7, 4.1–4.3, 5.1–5.2), each traced to a symbol in the spec-adherence review. Source eligibility gate, multi-select picker with ineligible-marking + empty-state, independent deep-equal copies, de-dupe, all-skipped no-op, atomic save with rollback, best-effort recompute, and the list-hosted confirmation toast naming copied + skipped people.

**Tested** — helper/persistence/eligibility layers (`CopyPackingTests`, `CopyPackingItemSheetEligibilityTests`) cover ownership, trimmed naming, conditions fidelity + independence over a nested advanced form, dedupe, the unsaved-insert 3.5 race, unresolvable-id and empty-name boundaries, engine materialisation, and the atomicity mechanism; `CopyOutcomeTests` covers the four orchestration branches (all-skipped, save-failed, deferred, success); one happy-path UI test (`CopyMasterPackingItemUITests`).

**Partially implemented** — none.

**Missing** — none against the spec. Out of scope by design: trip-level copy, multi-source copy, copying master tasks, overwrite-on-collision, creating new people as targets.

**Known caveat** — verified against a flaky simulator test-host (xcodebuild's xcresult aggregate misreports failures while the action exits 0); the new suites were confirmed green on a single booted simulator. A clean-environment `make test` is advisable before merge.
