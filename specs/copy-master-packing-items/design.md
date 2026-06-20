# Design: Copy Master Packing Items

## Overview

Add a per-row "Copy to people…" action to the Master Lists packing list that creates independent `MasterPackingItem` copies for selected people, then runs the existing non-past-trip rules recompute so the copies materialise onto matching trips. No schema change; the work is one new sheet, one persistence helper, and a toast host on the list surface.

## Architecture

### Integration points

| Concern | Existing seam reused | Adaptation |
|---|---|---|
| Master save | `MasterPackingEditor.attemptSave` — insert into globals `@Environment(\.modelContext)`, `modelContext.save()`, `rollback()` on failure | Same, but N inserts before one save (all-or-nothing falls out of single save) |
| Trip materialisation | `MasterPackingEditor.runEngineAndDismiss` — `RulesEngineRunner(context: tripsLocalContainer.mainContext, mastersContext: modelContext, hook: hook).runForAllNonPastTrips()` | Identical wiring, called from the list instead of the editor |
| Row affordance | `PackingItemRow` Edit pair (`.swipeActions` + `.contextMenu`, `PackingItemRow.swift:132,141`) — a trip-level component | **New UI on this surface.** `MasterPackingList` rows are a whole-row `Button` that taps into the editor and have no per-row swipe/context action today. The copy action reuses that swipe+context-menu *pattern* on a new surface; **tap continues to open the editor, long-press/swipe copies** |
| Confirmation/error feedback | `transientToast(message:)` modifier | New host on `MasterPackingList` (it has none today; editor/Trip views do) |
| Conditions value | `MasterPackingDraft(from:)` reads `master.conditions` (decoded `ItemConditions`) | Copy passes `source.conditions` straight into the new item's initializer |

`LocalWriteHook.mapping(for:)` returns `nil` for `Person`/`Master*` (they live in `globals`, not a trip zone), so master creation does **not** go through the hook — only the engine run does, exactly as the editor already does. The copied masters themselves reach other devices through the `globals` container's CloudKit mirroring (the same path every editor-created master already uses), not through the hook.

### Flow

```
MasterPackingList row  (whole-row tap still opens the editor)
  └─ long-press contextMenu / trailing swipe "Copy to people…"   (shown only for an eligible source: Req 1.3)
       └─ .sheet(item: $sheetTarget → .copy(id)) → CopyPackingItemSheet(source)
            ├─ lists people = allPeople − owner, sorted by name (2.1)
            ├─ rows that already own a same-name item are disabled + labelled (2.3)
            ├─ empty-state when none eligible (2.5)
            └─ Confirm → onCopy(rawSelectedPersonIDs); parent dismisses sheet
                 └─ MasterPackingList.performCopy(source, ids)
                      ├─ MasterPersistence.copyPacking(...) → de-dupes ids, inserts copies, returns CopyResult
                      ├─ createdCount == 0 (all skipped/raced-out): no save, no engine, "all skipped" toast (3.7)
                      └─ createdCount  > 0: modelContext.save()  [rollback+fail toast on throw] (3.6)
                                       → runner.runForAllNonPastTrips()  [deferred toast on top-level throw] (4.2)
                                       → success toast naming copied + skipped (5.1/5.2)
```

The toast renders on `MasterPackingList`, which stays mounted while the picker sheet dismisses — the success path can dismiss and still show feedback (the editor's toasts work today only because it dismisses *after* success; the copy flow decouples the two).

If `.copy(id)` can no longer resolve to a live `MasterPackingItem` at confirm time (source deleted or its owner changed between row tap and confirm), `performCopy` writes nothing and dismisses — no toast.

### Source eligibility (Req 1.3)

The row offers the action only when all hold: `allPeople.count >= 2`, `source.person != nil`, and `source.name` is non-empty after trimming. These are cheap per-row checks against the list's existing `@Query` data.

## Components and Interfaces

### `CopyPackingItemSheet` (new — `Features/MasterLists/CopyPackingItemSheet.swift`)

Presentation only; owns selection state, not persistence.

```swift
@MainActor struct CopyPackingItemSheet: View {
  let source: MasterPackingItem
  let onCopy: ([UUID]) -> Void      // raw selected person IDs; parent does the work
  let onCancel: () -> Void

  @Query(sort: \Person.name) private var allPeople: [Person]
  @State private var selected: Set<UUID> = []
}
```

- Eligibility per person: not the owner, and the person's own `masterPackingItems` relationship contains no item with `normalizedName == normalizedName(source.name)`. Reading eligibility off `Person.masterPackingItems` — the **same data path** the persistence skip uses — closes the divergence the second `@Query` would have opened: both the picker display and the confirm-time re-check apply `MasterPersistence.normalizedName` over the same relationship (`Person` and `MasterPackingItem` are both `globals` records, so the relationship faults in-context). Ineligible rows are disabled and labelled "already has it".
- Confirm disabled until `selected` (intersected with eligible) is non-empty (2.4); whole sheet shows an empty-state when no person is eligible (2.5).
- On confirm the sheet passes its **raw** selected IDs to `onCopy`; it does not re-filter. `copyPacking` is the sole authority that drops ineligible/raced-out targets (Req 3.5), so there is no second, divergent filter.
- Accessibility: the row's copy action carries a `.isButton` trait and a "Copy to people" label; ineligible person rows expose the reason via `accessibilityValue("already has this item")` rather than relying on the disabled dimming alone; the success/skip toast is announced with a `UIAccessibility` announcement, matching `PackingItemRow`'s move announcements.

### `MasterPersistence` additions (`Features/MasterLists/MasterPersistence.swift`)

```swift
struct CopyResult: Sendable {        // value-only — no @Model values cross out of the helper
  var createdCount: Int              // copies inserted into context, NOT yet saved
  var copiedNames: [String]          // target person names that received a copy
  var skippedNames: [String]         // target person names skipped (already owned)
}

/// Inserts one copy per target person that does not already own a same-name
/// item. De-duplicates `toPersonIDs` (it is the sole authority on what gets
/// created). Does NOT call save() — caller owns mutate → save → run-engine,
/// per the existing MasterPersistence convention. The same-name check covers
/// Req 3.5 (a target that became a same-name owner since the picker opened).
@discardableResult
static func copyPacking(
  source: MasterPackingItem,
  toPersonIDs: [UUID],
  in context: ModelContext
) -> CopyResult

/// Trimmed + case-insensitive key for same-name detection (Req 2.3 / 3.5).
nonisolated static func normalizedName(_ raw: String) -> String

/// Builds the 5.1/5.2/3.7 confirmation strings. Takes the plain name arrays
/// (not the @Model-bearing CopyResult) so it stays nonisolated and unit-
/// testable; lives here, not on the sheet, which is dismissed before the
/// toast shows.
nonisolated static func copyToastMessage(copiedNames: [String], skippedNames: [String]) -> String
```

- Each created item: `MasterPackingItem(name: source.name.trimmed, person: targetPerson, conditions: source.conditions)`. Passing the decoded `source.conditions` value gives deep equality including advanced nested forms and a fully independent copy (value semantics) — satisfies Req 3.3 / 3.4 without touching `conditionsData` directly.
- Same-name detection compares `normalizedName` against the target person's existing `masterPackingItems`.

### `MasterPackingList` changes

- Add `@Environment(\.tripsLocalContainer)`, `@Environment(\.localWriteHook)`, `@State private var toastMessage: String?`.
- Fold the existing `editTarget` and the new copy presentation into **one** `SheetTarget` enum so only a single `.sheet(item:)` is mounted on the list (avoids the SwiftUI multiple-sheet conflict): `case create`, `case edit(PersistentIdentifier)`, `case copy(PersistentIdentifier)`. The `.copy` case resolves its source against `allItems` in the sheet builder, exactly as the current `.edit` case does (`MasterPackingList.swift:86-90`); an unresolved id renders nothing and the sheet is dismissed.
- Add the `.contextMenu` + `.swipeActions` "Copy to people…" entry to each item row (gated on source eligibility, Req 1.3) and `.transientToast(message: $toastMessage)` on the list. The whole-row tap keeps setting `sheetTarget = .edit(...)`.
- `private func performCopy(source:toPersonIDs:)` runs the save → engine → toast sequence described in Flow.

## Error Handling

| Failure | Handling | Req |
|---|---|---|
| `modelContext.save()` throws after inserts | `modelContext.rollback()` (drops all uncommitted copies → none created), `toastMessage = "Copy failed — try again."` | 3.6 |
| `runForAllNonPastTrips()` throws | Masters stay saved (different container, already committed); `toastMessage = "Copied. Some trips couldn't be updated — they'll sync on next launch."` | 4.2 |
| All targets skipped at confirm (`createdCount == 0`) | No save, no engine run; `toastMessage` reports everyone already had it | 3.7 |

Master save atomicity and trip-materialisation best-effort are distinct regimes: the single globals `save()` is all-or-nothing; the subsequent engine run is best-effort and never rolls back the committed masters.

**Scope of the deferred toast.** `runForAllNonPastTrips()` only throws at the top level (the trip fetch / the hoisted master-snapshot fetches). A *per-trip* `apply` failure is caught inside the runner loop, rolled back, and logged — it does **not** propagate (`RulesEngineRunner.swift:89-99`), so the deferred toast covers a top-level recompute failure, not a single trip's failure. A trip skipped by a per-trip failure self-heals on the next recompute trigger (cold launch, foreground, or the next master edit), exactly as the editor's saves do today. This feature does not change the runner's per-trip error contract.

## Testing Strategy

Swift Testing (`@Test`), in-memory `ModelContainer` with `cloudKitDatabase: .none`, masters + trips seeded in one container (the runner accepts the same context for both, per its `mastersContext` default).

**`MasterPersistence.copyPacking` (unit):**
- Creates one copy per eligible target, each owned by the right person (3.1).
- Skips a target already owning a same-name item; comparison is trimmed + case-insensitive ("  Socks " vs "socks") (2.3/3.5); skipped name appears in `skippedNames`.
- All targets already own it → `createdCount == 0`, nothing inserted (3.7).
- Duplicate ids in `toPersonIDs` produce one copy, not two (de-dupe).
- Copied name equals trimmed source name (3.2).
- **Conditions fidelity:** copy a source whose conditions are an advanced nested form `.all([.any([.match(...), .match(...)]), .match(...)])`; assert `copy.conditions == source.conditions` — the decoded value, **not** `conditionsData` byte-equality (encoding is not byte-stable) (3.3) — and that mutating the copy's conditions leaves the source unchanged (3.4).

**Save/sequence (unit, with a recording-notifier `LocalWriteHook`):**
- After `copyPacking` + a forced `save()` failure, `rollback()` leaves **zero** new `MasterPackingItem`s persisted and the engine is never invoked (3.6).
- Source owner is never offered as / never receives a copy (2.1).
- `onCancel` / dismiss-without-confirm writes nothing (2.6).

**Pure helpers (unit):** `normalizedName` (trim + lowercase, empty handling); `MasterPersistence.copyToastMessage(copiedNames:skippedNames:)` across the three outcomes — copied-only, copied-with-skips, all-skipped (5.1/5.2/3.7).

**Engine integration (unit):** seed a trip whose attributes match copied conditions; run `copyPacking` → `save` → `runForAllNonPastTrips`; assert a matching `TripPackingItem` now exists for the target person and not for a non-matching trip (4.1).

**UI (SHOULD, `ScrambleUITests`):** open packing master list → row context menu → "Copy to people…" → select a person → confirm → assert toast text. One happy-path test; accessibility identifiers on the sheet's confirm button and person rows.

**Property-based testing:** considered for the conditions round-trip/independence invariant (3.3/3.4). Not adopted — the project has no value-generator framework and uses example-based Swift Testing throughout. Covered instead by the explicit advanced-nested-form fixture above, which exercises every `ItemConditions` case.
