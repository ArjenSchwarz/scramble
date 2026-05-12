# Phase 2 Rules Engine — Implementation Explanation

Three progressively-deeper walkthroughs of the Phase 2 rules-engine implementation, followed by a Completeness Assessment that maps each acceptance criterion to its implementing code.

---

## Beginner Level

### What This Does

Scramble is a trip-planning app. Users keep two **master lists** — one for reusable tasks ("renew passport"), one for reusable per-person packing items ("Alex / rain jacket"). Each item has *conditions* describing when it applies — for example, "only when the weather is rain or cold," or "only for international trips."

When the user creates or edits a trip, the **rules engine** looks at each master item and asks: "does this item's conditions match the trip's attributes?" If yes, a copy is added to the trip automatically. If a master's conditions later stop matching (the user changes the trip's weather, say), the engine doesn't delete the item — it just **dims** it by setting a "currently matches rules" flag to false. The user can still see it; they just see that the rule no longer applies.

Phase 2 ships:

1. The **Master Lists** screen, a tabbed view where users can add / edit / delete master tasks and master packing items, including a chip-based conditions picker.
2. The **rules engine** itself — a function that takes a trip and the master lists, decides what should change, and applies those changes to SwiftData.
3. The **triggers** that re-run the engine at the right moments: trip created, trip edited, master saved/deleted, app cold-launched, app foregrounded after being backgrounded.

### Why It Matters

A user with a thoughtful master list shouldn't have to copy items into every new trip by hand. They shouldn't see items disappear when they tweak a trip attribute; they should just see them dim. They shouldn't have to *manually* tell the app "this trip is similar to that one." The rules engine is what turns a flat list of items into a system that adapts to context.

### Key Concepts

- **Master item**: a reusable template. Editing a master does not retroactively rewrite copies already on trips — copies are *snapshots* of the master's name (and phase, for tasks; person, for packing items).
- **Trip-level item**: a `TripTask` or `TripPackingItem`. Owned by a trip. Has a `currentlyMatchesRules` flag and (if rule-driven) a back-reference to its master via `masterItemID`.
- **Conditions**: a small expression like "weather is rain or cold AND scope is international." Stored as a Codable blob so the storage shape can grow without a schema migration.
- **The "non-past" predicate**: a trip is non-past if its end date (calendar-day granularity) is on or after today. The engine only touches non-past trips during cold-launch / foreground-transition / master-save fan-out — past trips are frozen.
- **The exclusion asymmetry**: pinning an item, completing a task, packing or excluding a packing item *protects it from being dimmed*. It does NOT prevent the engine from un-dimming the item when its rule starts matching again. "Pin against demotion, not against re-matching."

---

## Intermediate Level

### Module Layout

```
Scramble/Scramble/
├── RulesEngine/
│   ├── Snapshots.swift           value-type capture of Trip + masters
│   ├── Plan.swift                Plan + TripItemRef
│   ├── Compute.swift             pure compute(...)
│   ├── Apply.swift               @MainActor apply(plan:context:)
│   └── RulesEngineRunner.swift   orchestrator with two entry points
├── Features/MasterLists/         the editor UI
│   ├── MasterListsTab.swift      segmented host
│   ├── MasterTasksList.swift     @Query grouped by Phase
│   ├── MasterPackingList.swift   @Query grouped by Person
│   ├── MasterTaskEditor.swift    create/edit task sheet
│   ├── MasterPackingEditor.swift create/edit packing sheet
│   ├── MasterPersistence.swift   mutate-only helpers
│   ├── MasterTaskDraft.swift     value-type draft + validate()
│   ├── MasterPackingDraft.swift  value-type draft + validate()
│   ├── ConditionsEditor.swift    chip multi-select per attribute
│   ├── AttributeSelections.swift bridge to/from ItemConditions
│   ├── AdvancedConditionView.swift read-only placeholder for non-v1 shapes
│   └── ItemConditions+PrettyPrint.swift display string for advanced view
└── Components/
    └── DashedAddButton.swift     shared "+ Add" affordance
```

### The Pipeline

```
trigger site → RulesEngineRunner
              ├─ TripSnapshot.capture(from:)   (reads @Model on main actor)
              ├─ fetchMasterTaskSnapshots()    (reads @Model on main actor)
              ├─ compute(trip:masterTasks:masterPacking:)  (PURE — value types only)
              └─ apply(plan:context:)          (writes @Model + context.save())
```

`compute(...)` is the engine's load-bearing pure function. It takes only value-type inputs (`TripSnapshot`, `[MasterTaskSnapshot]`, `[MasterPackingSnapshot]`) and returns a value-type `Plan`. No `ModelContext`, no `@Model` reference. This is what makes the engine's bulk coverage unit-testable without spinning up a `ModelContainer`.

### The Compute Algorithm

For each (Trip, masters) pair:

1. Build `[UUID: MasterTaskSnapshot]` and `[UUID: MasterPackingSnapshot]` lookup maps. We use `Dictionary(uniquingKeysWith:)` so a CloudKit-merge race that briefly surfaces two masters with the same UUID does not trap.
2. Build a `Set<UUID>` of master ids already referenced on the trip (union over `existingTasks.masterItemID` and `existingPacking.masterItemID`, ignoring nils). This handles dedup in one pass, including duplicate refs from sync races.
3. For each master, evaluate its conditions against the trip's attributes. If true and the master id is not in the referenced-id set, emit to `toAddTasks` / `toAddPacking`.
4. For each existing ref with a non-nil `masterItemID`, classify per a **4-way decision matrix**:

   | `currentlyMatchesRules` | master conditions evaluate | Action |
   |---|---|---|
   | `true` | `true` | no-op (avoid CloudKit churn for unchanged state) |
   | `true` | `false` | `toFlagUnmatched` (subject to exclusion table) |
   | `false` | `true` | `toFlagMatched` (NO exclusions — re-matching is unconditional) |
   | `false` | `false` | no-op |

   Pre-filters: items with `source == .manual` are invisible (AC 4.6); items whose `masterItemID` no longer resolves are treated as condition-false (AC 4.7).

5. `Plan.init` then sorts each output collection (`toAdd*` by id; `toFlag*` by `(kind, id)`) so the wire output is deterministic. (Sort in `Plan.init` rather than `compute` is a deliberate refinement of the design — see Decision 8.)

### The Asymmetric Exclusion Table

Pin / completion / engagement state protect against **demotion**, never against **re-matching**:

| Trip-level item attribute | Excludes from `toFlagUnmatched`? | Excludes from `toFlagMatched`? |
|---|---|---|
| `pinnedByUser == true` | Yes (AC 6.1) | No (AC 6.1 last sentence) |
| `isCompleted == true` (tasks) | Yes (AC 6.2) | No |
| `state ∈ {.packed, .repacked, .excluded}` (packing) | Yes (AC 6.3) | No |
| `source == .manual` | Yes (AC 4.6) | Yes (AC 4.6 — engine ignores manual items entirely) |

### Triggers

| AC | Trigger | Wiring |
|---|---|---|
| 5.1 | Trip created | `TripListView.swift` `onSave` closure runs `runner.runForTrip(newTrip)` after `context.save()` |
| 5.2 | Trip attributes saved | `TripDetailView.swift` edit-sheet closure, same pattern |
| 5.3 | Master saved/deleted | Both master editors' `runEngineAndDismiss()` → `runner.runForAllNonPastTrips()` |
| 5.4 | Cold launch | `ScrambleApp.init()` synchronously runs `runForAllNonPastTrips()` after `UITestSeed.applyIfRequested(...)` |
| 5.7 | Foreground transition | `RootView.onChange(of: scenePhase)` with a `hasBeenBackgrounded: Bool` latch |

The ordering invariant is **mutate → save → run engine**. Reversing save and run would leave the engine reading stale state.

### Conditions Editor

`AttributeSelections` is a value-type bridge between `ItemConditions` (the persisted blob) and the chip editor's `[TripAttribute: Set<String>]` representation. `from(_:)` decodes an `ItemConditions` to selections or returns nil if the shape isn't v1-representable (nested groups, top-level `.any`, out-of-domain values). On nil, the editor swaps `ConditionsEditor` for `AdvancedConditionView` — a read-only placeholder that prints the condition tree via `ItemConditions.prettyPrinted` and offers "Reset to simple" to overwrite with `.always`. Name / phase / person editing remains live in the placeholder mode.

`toConditions()` is the inverse: iterates `TripAttribute.allCases` in declaration order, emits one `.match(attribute:, anyOf:)` per attribute with selections, wraps the matches in `.all(...)`. Empty selections produce `.always`. Values within each match are sorted alphabetically for stable encoding (so two devices that produce the same selections write the same blob).

### Trade-offs

- **Pure compute over value types, separate from snapshot capture and apply**: lets every test cover compute without a `ModelContainer`. Cost: two snapshot type families (`TripSnapshot` + refs, master snapshots).
- **Synchronous cold-launch run in `ScrambleApp.init()`**: blocks first paint by up to the run cost, but pins the Phase 1 auto-open ordering invariant (the auto-opened trip sees post-scan state). Phase 1 AC 5.6 made this load-bearing.
- **Chip editor only handles the v1 shape**: any user can produce a hand-crafted JSON blob or sync from a future v2 editor. We exit gracefully via `AdvancedConditionView` rather than silently mangling the shape.
- **Snapshot semantics, not live-linking**: rename a master, existing trip-level items keep their old name. Avoids "I completed Charge Kindle and now it says Charge tablet" surprise.

---

## Expert Level

### Pure-Function Boundary

`compute(...)` is `nonisolated` and accepts only value-type snapshots. `TripSnapshot.capture(from: Trip)` is `@MainActor` (it reads `@Model` properties) but the resulting struct is `nonisolated Sendable`. Tests construct `TripSnapshot` directly without ever touching a `Trip` or a `ModelContainer`; the integration suites cover the `@MainActor` halves.

The pipeline's invariant is: **`compute` never touches SwiftData, and `apply` never classifies**. Reversing either side would re-entangle the engine with the model context and lose the unit-testable contract that AC 4.8 codifies.

### Determinism

`Plan.init` enforces the AC 4.9 sort by construction. Originally the design assigned sort to `compute`; the implementation moved it to the type so callers cannot construct an unsorted `Plan` (Decision 8 documents the refinement). Internally `compute` builds whatever order falls out of its iteration, and the initializer normalises. The cost is a redundant pass for already-sorted callers; the benefit is that no test fixture, future call site, or sync handler can produce an unsorted `Plan`.

The sort key for `toFlag*` is `(kind.rawValue, id)` — `kind` first to keep all tasks together, then all packing items, with `id` ordering within each kind. `TripItemRef.Kind: Comparable` is implemented by `rawValue` comparison; with only two cases this is harmless, but if a third kind is ever added, the ordering shifts and snapshot tests will need to be updated.

### Performance — N×M Fetch Elimination

The original `runForAllNonPastTrips` re-fetched the master arrays per trip via `runForTrip`. With AC 5.5's bound (≤20 non-past trips × ≤200 masters) that was up to 4,000 model materialisations per kind × 2 kinds = 8,000 materialisations per run, on the main actor, against a 250ms budget. The current implementation hoists `fetchMasterTaskSnapshots()` / `fetchMasterPackingSnapshots()` to the top of `runForAllNonPastTrips`, and dispatches to a private `runForTrip(_:masterTasks:masterPacking:)` overload that takes the pre-fetched arrays. The public single-trip entry point keeps the old shape for editor-driven calls (where there's only one trip).

`Apply.insertAddedPacking` batch-fetches `Person` via a single `idSet.contains` predicate, then resolves from a `[UUID: Person]` map. Same shape as `flagTasks` / `flagPacking`. Per-item `FetchDescriptor<Person>` was the prior shape; eliminated.

### scenePhase Carve-Out

iOS delivers backgrounding as `.background → .inactive → .active` — `.inactive` is an intermediary. `onChange(of: scenePhase)` does not observe a direct `.background → .active` edge, so the design's original `previousScenePhase == .background, newPhase == .active` guard never fired. The implementation latches a `hasBeenBackgrounded: Bool` on `.background`, resets it after firing on the next `.active`. The cold-launch carve-out (Phase 1 AC 5.6) is preserved because the initial `nil → .inactive → .active` sequence never visits `.background`. Decision 9 documents the supersede.

A DEBUG-only counter (`scenePhaseRunnerCalls`) is exposed through an accessibility identifier so `RootViewScenePhaseTests` can verify the carve-out: a `.inactive → .active` sequence at cold launch must leave the counter at 0; a `.background → .active` cycle must increment it.

### Cold-Launch Ordering

`ScrambleApp.init()` runs the scan synchronously before `WindowGroup` mounts. SwiftUI's `.task` modifier and `Scene.onChange(initial: true)` both have unspecified sibling-ordering relative to `TripsTab.task` (which auto-opens a qualifying trip per Phase 1 AC 5.6). Synchronous `init()` is the only structural guarantee that the scan completes before the auto-open task fires. The trade-off — blocking first paint by up to the run cost — is acceptable at the bounded dataset and protects the user-visible invariant that the auto-opened trip detail observes the post-scan state.

Errors are caught and logged (`[RulesEngine.cold-launch-failed]`); there is no UI mounted yet to show a toast against. The same applies to the scenePhase trigger (`[RulesEngine.scenePhase-failed]`). Editor-driven triggers (AC 5.1 / 5.2 / 5.3) propagate via the `transientToast` pattern.

### Idempotence

The compute matrix's `(true, true)` and `(false, false)` cells are no-ops, and `Plan.isEmpty` causes `apply` to skip the `context.fetch` + `context.save()`. Running the engine twice in succession against unchanged state produces zero CloudKit writes. `RulesEngineRunnerTests.runForTripIdempotent` and `ComputeIdempotenceTests` (a SplitMix64-driven property-based suite) pin this end-to-end and at the compute level.

### Conditions Storage Round-Trip

`AttributeSelections.from(.always)` returns `AttributeSelections.empty` (non-nil). This is what the "Reset to simple" flow at `MasterTaskEditor.swift:107-111` / `MasterPackingEditor.swift:116-120` relies on: writing `draft.conditions = .always` and re-deriving selections produces an empty (non-nil) selection, so the editor flips from `AdvancedConditionView` back to `ConditionsEditor` automatically. The reset confirmation copy paraphrases AC 3.7c: "Reset conditions to empty? On the next re-evaluation this item will match every non-past trip until you save new conditions."

`toConditions()` sorts each match's `anyOf` alphabetically so two devices that produce the same chip selections write the same blob. `from(_:)` rejects values outside `TripAttributeOptions.values(for: attr)` so a stored blob whose values fell out of the domain (e.g., after a future trim) is routed into `AdvancedConditionView`.

### Person Deletion Guard

AC 8.2 ships with **zero new code**. Phase 1's `PersonDeleteBlocker.make(for:tripPacking:masterPacking:)` already accepts both reference kinds and produces an alert message naming both. The Phase 2 contribution is one UI test (`PersonDeletionGuardUITests`) seeded with a person owning a `MasterPackingItem` and no `TripPackingItem` refs, asserting the alert surfaces the master-list count via the Phase 1 helper.

### What's Deliberately Deferred

- `WhyDisclosure` "which clauses matched" walk — Phase 3 (Decision 6). Phase 2 ships `evaluate(against:) -> Bool` only.
- CloudKit sync as a re-evaluation trigger — CKShare phase (Decision 4). The scenePhase trigger bounds the cross-device staleness window meanwhile.
- AC 5.5's 250ms wall-clock target is not enforced by an automated test — CI lacks a stable wall-clock harness; design acknowledges this. An Instruments observation should be recorded once a worst-case fixture is built.

---

## Completeness Assessment

Mapping every AC 1.1–8.2 to its implementing code and test coverage.

### 1. Master Task CRUD

| AC | Implementation | Tests |
|---|---|---|
| 1.1 | `MasterTasksList.swift:25-46` — `Dictionary(grouping: allTasks, by: \.phase)` iterating `Phase.allCases`, empty groups omitted | `MasterListsCRUDUITests` |
| 1.2 | `MasterTasksList.swift:47-49` — `DashedAddButton` `"Add task"` opens `MasterTaskEditor(mode: .create)` | `MasterListsCRUDUITests` |
| 1.3 | `MasterTasksList.swift:33-41` — row tap sets `editTarget = .edit(id)` → `MasterTaskEditor(mode: .edit(item))` | `MasterListsCRUDUITests` |
| 1.4 | `MasterTaskDraft.swift:13-19` + `MasterPersistence.swift:13-34` — `validate()` + `createTask`/`applyTask`; cancel = `dismiss()` without save | `MasterDraftTests`, `MasterListsCRUDUITests` |
| 1.5 | `MasterTaskDraft.swift:13-19` + `MasterTaskEditor.swift:85-90` — empty/whitespace name → `[.name: "Name is required"]` inline | `MasterDraftTests` |
| 1.6 | `MasterTaskEditor.swift:65-74, 117-125, 162-173` — destructive `.confirmationDialog` + `deleteTask` then engine re-run | `MasterListsCRUDUITests` |

### 2. Master Packing CRUD

| AC | Implementation | Tests |
|---|---|---|
| 2.1 | `MasterPackingList.swift:38-67` — group by `person.id`, sorted by `Person.name` ascending, header shows item count | `MasterListsCRUDUITests` |
| 2.2 | `MasterPackingList.swift:68-72` — `DashedAddButton` `"Add item"` opens `MasterPackingEditor(mode: .create)` | `MasterListsCRUDUITests` |
| 2.3 | `MasterPackingList.swift:46-56` — row tap → `editTarget = .edit(id)` | `MasterListsCRUDUITests` |
| 2.4 | `MasterPackingDraft.swift:14-23` + `MasterPersistence.swift:42-65` | `MasterDraftTests` |
| 2.5 | `MasterPackingDraft.swift:14-23` + `MasterPackingEditor.swift:103-108` | `MasterDraftTests` |
| 2.6 | `MasterPackingEditor.swift:67-76, 126-134, 171-182` | `MasterListsCRUDUITests` |
| 2.7 | `MasterPackingList.swift:29-37` — `if allPeople.isEmpty` → `ContentUnavailableView`, "+ Add item" hidden | `MasterPackingEmptyStateUITests` |

### 3. Conditions Editor

| AC | Implementation | Tests |
|---|---|---|
| 3.1 | `ConditionsEditor.swift:15-28` — `ForEach(TripAttribute.allCases)` with `Section(attribute.displayName)` | `ConditionsEditorUITests` |
| 3.2 | `ConditionsEditor.swift:17-26, 30-57` — `LazyVGrid(.adaptive(minimum: 88))` chip multi-select; OR within / AND across via `toConditions()` | `AttributeSelectionsTests`, `ConditionsEditorUITests` |
| 3.3 | `AttributeSelections.swift:19-25` — `toConditions()` omits attributes with empty selections | `AttributeSelectionsTests` |
| 3.4 | `AttributeSelections.swift:24` — `matches.isEmpty ? .always : .all(matches)` | `AttributeSelectionsTests`, `ConditionsEditorUITests` (empty-save case) |
| 3.5 | `AttributeSelections.swift:20-23` — iterates `TripAttribute.allCases` in declaration order; values sorted alphabetically | `AttributeSelectionsTests` |
| 3.6 | `AttributeSelections.swift:32-50` — `from(_:)` decodes `.always` and `.all([.match…])`; PBT round-trip | `AttributeSelectionsTests`, `ConditionsEditorUITests` |
| 3.7 | `AttributeSelections.swift:32-50` returns nil for non-v1 shapes; `AdvancedConditionView.swift` renders read-only + reset confirmation | `ConditionsEditorUITests` (advanced fixture) |
| 3.8 | `AttributeSelections.swift:55-61` — `isInDomain()` defensive guard; chip editor cannot produce out-of-domain selections by construction | `AttributeSelectionsTests` |

### 4. Rules Engine — Compute and Diff

| AC | Implementation | Tests |
|---|---|---|
| 4.1 | `Compute.swift:11-52` — pure `compute(...) -> Plan` with `toAddTasks/Packing` + `toFlagUnmatched/Matched`, deterministic via `Plan.init` | `ComputeTests`, `PlanTests` |
| 4.2 | `Compute.swift` — no `toRemove` set anywhere; deletions are flag changes only | `ComputeTests` (matrix cells) |
| 4.3 | `Apply.swift:31-46` — `TripTask(...)` with snapshotted fields, `source = .rule`, `currentlyMatchesRules = true`, `pinnedByUser = false`, `isCompleted = false` | `ApplyTests.toAddTasksInsertsCorrectly` |
| 4.4 | `Apply.swift:50-77` — batch-fetched `Person`, `TripPackingItem(...)` with snapshotted fields, missing person logs + skips | `ApplyTests.toAddPackingMissingPersonSkips` |
| 4.5 | `Apply.swift:79-117` — only `currentlyMatchesRules` mutated; `Compute.swift` `(true,true) → no-op` cell avoids CloudKit push | `ApplyTests.toFlagUnmatchedTask`/`toFlagMatchedPacking`, `ComputeTests` |
| 4.6 | `Compute.swift:74, 97` — `guard ref.source != .manual` skip | `ComputeTests.manual*` |
| 4.7 | `Compute.swift:75, 98` — `taskMap[masterID]?.conditions...evaluate(...) ?? false` treats missing master as false | `ComputeTests.danglingMaster*` |
| 4.8 | `Compute.swift:11-52` — `nonisolated`, value-type inputs only; tests construct `TripSnapshot` without a container | `ComputeTests` (no container), `ComputeIdempotenceTests` |
| 4.9 | `Plan.swift:24-45` — `Plan.init` sorts `toAdd*` by id ascending, `toFlag*` by `(kind, id)` ascending | `PlanTests.sortInvariants`, `ComputeTests.sortInvariant` |

### 5. Re-evaluation Triggers

| AC | Implementation | Tests |
|---|---|---|
| 5.1 | `TripListView.swift:69-72` — `runner.runForTrip(newTrip)` after `context.save()` succeeds | `RulesEnginePopulationUITests.createPath` |
| 5.2 | `TripDetailView.swift:80-92` — `runner.runForTrip(trip)` after `TripPersistence.apply` + `context.save()` | `RulesEnginePopulationUITests.editPath` |
| 5.3 | `MasterTaskEditor.swift:175-184`, `MasterPackingEditor.swift:184-193` — `runForAllNonPastTrips()` in `runEngineAndDismiss()` | `RulesEngineRunnerTests` |
| 5.4 | `ScrambleApp.swift:13-21` — synchronous run in `init()` after `UITestSeed.applyIfRequested(...)` | `ColdLaunchSequencingUITests` |
| 5.5 | Bounded by design; not automated in Phase 2 (design acknowledges); Compute uses `Dictionary` lookups for O(1) per-ref lookup; `runForAllNonPastTrips` hoists master fetches | Indirect — `ComputeTests.bigFanOut` exercises 200-master worst case |
| 5.6 | `Compute.swift:71-105` matrix `(true,true)`/`(false,false)` cells emit nothing; `Apply.swift:7` `guard !plan.isEmpty` short-circuits save | `ComputeIdempotenceTests`, `RulesEngineRunnerTests.runForTripIdempotent` |
| 5.7 | `RootView.swift:35-49` — `hasBeenBackgrounded: Bool` latch; cold-launch carve-out preserved (Decision 9) | `RootViewScenePhaseTests` |

### 6. Pinned, Completed, Packed, Excluded, and Orphaned Items

| AC | Implementation | Tests |
|---|---|---|
| 6.1 | `Compute.swift:74` — `if ref.pinnedByUser ... { continue }` in `toFlagUnmatched`; absent from `toFlagMatched` path | `ComputeTests.pin*` rows |
| 6.2 | `Compute.swift:74` — `\|\| ref.isCompleted` joined with pin guard | `ComputeTests.completion*` rows |
| 6.3 | `Compute.swift:97` — `engaged.contains(ref.state)` covers `.packed`/`.repacked`/`.excluded` | `ComputeTests.engagedState*` rows |
| 6.4 | `Compute.swift:51-60, 17-22` — `referencedMasterIDs(in:)` set unions both kinds; `toAdd` filter excludes referenced ids; duplicates tolerated | `ComputeTests.dedup*` |
| 6.5 | `Compute.swift:75, 98` — missing master → conditions false → `toFlagUnmatched` (subject to exclusions); `Apply.swift` preserves snapshot fields | `RulesEngineRunnerTests` master-delete path |

### 7. Master Item — Cross-Trip Effects

| AC | Implementation | Tests |
|---|---|---|
| 7.1 | `Apply.swift:31-46` snapshots `name` at insert; `MasterPersistence.applyTask` does not touch `TripTask.name` | `RulesEngineRunnerTests.ac71MasterRenameDoesNotPropagate` |
| 7.2 | `Apply.swift:31-46` snapshots `phase` at insert; `MasterPersistence.applyTask` does not touch `TripTask.phase` | `RulesEngineRunnerTests.ac72MasterPhaseChangeDoesNotPropagate` |
| 7.3 | `Apply.swift:50-77` snapshots `person` at insert; `MasterPersistence.applyPacking` does not touch `TripPackingItem.person` | `RulesEngineRunnerTests.ac73MasterPersonChangeDoesNotPropagate` |
| 7.4 | `Compute.swift:71-104` — condition flip on master edit + re-eval → `toFlagUnmatched` subject to AC 6.1–6.3 | `ComputeTests` condition-flip rows |
| 7.5 | `RulesEngineRunner.swift:48-58` — master snapshots are fetched at every runner invocation, not cached at trip creation | `RulesEngineRunnerTests` (multi-call paths) |

### 8. Person Deletion Guard

| AC | Implementation | Tests |
|---|---|---|
| 8.1 | `MasterPackingList.swift:55-65` — per-person header renders item count via `\(items.count)` | `MasterListsCRUDUITests` (count visible) |
| 8.2 | Phase 1 `PersonDeleteBlocker.make(for:tripPacking:masterPacking:)` already accepts both reference kinds; no Phase 2 code | `PersonDeletionGuardUITests` |

### Summary

- **All 39 acceptance criteria are implemented and have explicit test coverage**, except:
  - **AC 5.5** (250ms wall-clock target) — not automated; design explicitly accepts this. Performance-relevant code paths (Compute lookup maps, `runForAllNonPastTrips` hoisted fetches, `Apply.insertAddedPacking` batched person fetch) are in place. A future Instruments observation should be recorded in this file when a worst-case fixture is built.
  - **AC 3.8** (out-of-domain rejection) — covered by `AttributeSelections.isInDomain()` and the `from(_:)` domain-check rejection; the editor save path's defensive validation message is not directly tested, because the chip editor cannot produce out-of-domain selections by construction. Design explicitly accepts this.

- **Two design.md divergences are recorded as Decisions 8 and 9** in `decision_log.md`: `Plan.init` enforces the sort invariant (rather than `compute` sorting before construction), and the scenePhase carve-out uses `hasBeenBackgrounded: Bool` (rather than `previousScenePhase: ScenePhase?`, which would never fire because `.inactive` is the always-intermediary).

- **Pre-push review applied seven fixes** before merge: duplicate-master-id trap → `uniquingKeysWith:`; silent `try?` on cold-launch + scenePhase → logged `do/catch`; N×M master fetches in `runForAllNonPastTrips` → hoisted; per-item Person fetch in `Apply.insertAddedPacking` → batched; duplicated `phase` label helper → `Phase.displayName`; duplicated "+ Add" dashed button across three list views → shared `DashedAddButton` component; silent `try?` in `MasterPersistence.resolvePerson` → logged.

- **Implementation matches the spec**; the engine is unit-testable without a `ModelContainer`; trigger ordering, deterministic Plan output, and the exclusion asymmetry are all verifiable from test coverage.
