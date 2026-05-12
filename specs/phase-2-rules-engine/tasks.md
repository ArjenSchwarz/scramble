---
references:
    - specs/phase-2-rules-engine/requirements.md
    - specs/phase-2-rules-engine/design.md
    - specs/phase-2-rules-engine/decision_log.md
---
# Phase 2 Rules Engine Implementation

## Foundation value types

- [x] 1. Tests: Snapshot value types + Plan + TripItemRef <!-- id:diu0hgd -->
  - Add ScrambleTests/RulesEngine/PlanTests.swift covering TripSnapshot / TripTaskRef / TripPackingItemRef / MasterTaskSnapshot / MasterPackingSnapshot Equatable + Hashable + Sendable conformance.
  - Plan sort invariant: toAddTasks/toAddPacking sorted by master id asc; toFlagUnmatched/toFlagMatched sorted by (kind, id) asc.
  - Plan.isEmpty true iff all four collections empty.
  - TripItemRef.Kind raw values: 'task' / 'packing'.
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.8](requirements.md#4.8), [4.9](requirements.md#4.9), [6.4](requirements.md#6.4)

- [x] 2. Implement Snapshots.swift + Plan.swift <!-- id:diu0hge -->
  - Add Scramble/Scramble/RulesEngine/Snapshots.swift (TripSnapshot, TripTaskRef, TripPackingItemRef, MasterTaskSnapshot, MasterPackingSnapshot).
  - Add Scramble/Scramble/RulesEngine/Plan.swift (Plan, TripItemRef).
  - All types value-type Sendable; master snapshots also Hashable.
  - Blocked-by: diu0hgd (Tests: Snapshot value types + Plan + TripItemRef)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.8](requirements.md#4.8), [4.9](requirements.md#4.9)

## Conditions editor bridge

- [x] 3. Tests: AttributeSelections ↔ ItemConditions <!-- id:diu0hgf -->
  - Add ScrambleTests/MasterLists/AttributeSelectionsTests.swift, table-driven.
  - Round-trip: AttributeSelections.empty.toConditions() == .always; from(.always) == .empty; from(.all([.match(.weather,['rain','cold'])])) → matching chip selections; toConditions on those round-trips to .all([.match(.weather,['cold','rain'])]) (values sorted).
  - from(_:) returns nil for: top-level .any, nested .all/.any inside .all child, .match with anyOf containing value outside TripAttributeOptions.values(for: attr).
  - PBT (Swift Testing parameterised): random v1-shaped conditions round-trip equal.
  - Stream: 1
  - Requirements: [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6), [3.7](requirements.md#3.7)

- [x] 4. Implement AttributeSelections.swift <!-- id:diu0hgg -->
  - Add Scramble/Scramble/Features/MasterLists/AttributeSelections.swift.
  - Struct with byAttribute: [TripAttribute: Set<String>], static let empty, toConditions(), static from(_:), isInDomain().
  - toConditions iterates TripAttribute.allCases declaration order; values within match are sorted alphabetically for stable encoding.
  - Blocked-by: diu0hgf (Tests: AttributeSelections ↔ ItemConditions)
  - Stream: 1
  - Requirements: [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6), [3.7](requirements.md#3.7), [3.8](requirements.md#3.8)

- [x] 5. Tests: ItemConditions+PrettyPrint <!-- id:diu0hgh -->
  - Add ScrambleTests/MasterLists/ItemConditionsPrettyPrintTests.swift, representative trees.
  - .always → 'always'; .match(.weather, ['rain','cold']) → 'weather is Rain or Cold'; .all([.match(.weather,['rain']), .match(.scope,['international'])]) → multi-line 'all of:\n  weather is Rain\n  scope is International'; nested .any rendered 'any of:' with indented children.
  - ZWJ-emoji-in-value-string does not crash.
  - Stream: 1
  - Requirements: [3.7](requirements.md#3.7)

- [x] 6. Implement ItemConditions+PrettyPrint.swift <!-- id:diu0hgi -->
  - Add Scramble/Scramble/Features/MasterLists/ItemConditions+PrettyPrint.swift.
  - Recursive prettyPrinted(indent:) using attributeValueDisplay (Phase 1 String extension).
  - File deliberately not under Models/Codable/ so the model file stays CloudKit-pure.
  - Blocked-by: diu0hgh (Tests: ItemConditions+PrettyPrint)
  - Stream: 1
  - Requirements: [3.7](requirements.md#3.7)

## Rules engine

- [ ] 7. Tests: Compute decision matrix + exclusion table <!-- id:diu0hgj -->
  - Add ScrambleTests/RulesEngine/ComputeTests.swift, table-driven.
  - 4-way matrix: (currentlyMatchesRules, conditions-evaluate) → expected emission. All four cells.
  - Exclusion table: pin / completed / packed/repacked/excluded each protect against toFlagUnmatched but NOT toFlagMatched.
  - source == .manual: never emitted.
  - Missing master snapshot (deleted) → treated as conditions false; subject to exclusions.
  - Dedup: master already referenced on trip → not re-added; duplicate refs (sync race) tolerated as single 'present'.
  - Sort invariant: toAdd* sorted by master id; toFlag* sorted by (kind, id).
  - .match(_, anyOf: []) evaluates false (defensive against corrupt blob).
  - Blocked-by: diu0hge (Implement Snapshots.swift + Plan.swift)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.7](requirements.md#4.7), [4.9](requirements.md#4.9), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5)

- [ ] 8. Tests: Compute idempotence + determinism (PBT) <!-- id:diu0hgk -->
  - Add ScrambleTests/RulesEngine/ComputeIdempotenceTests.swift.
  - PBT determinism: compute(x, m1, m2) == compute(x, m1, m2) over random v1-shaped inputs.
  - PBT idempotence: simulate apply as a value-type rewrite of TripSnapshot.existingTasks/existingPacking (apply toAdd → append fresh refs with currentlyMatchesRules=true; toFlag → update flag), then second compute returns an empty Plan.
  - PBT no-spurious-adds: when every master evaluates false against trip.attributes, Plan.toAddTasks.isEmpty && Plan.toAddPacking.isEmpty.
  - Blocked-by: diu0hge (Implement Snapshots.swift + Plan.swift)
  - Stream: 1
  - Requirements: [4.5](requirements.md#4.5), [5.6](requirements.md#5.6)

- [ ] 9. Implement compute(...) in Compute.swift <!-- id:diu0hgl -->
  - Add Scramble/Scramble/RulesEngine/Compute.swift.
  - Build [UUID: MasterTaskSnapshot] and [UUID: MasterPackingSnapshot] lookup maps at entry (O(1) step-3 lookups).
  - Build Set<UUID> of referenced master ids across both existing collections.
  - Iterate masters for toAdd; iterate existing refs for toFlag; apply 4-way matrix + exclusion table per design.md compute algorithm.
  - Sort all four output collections; construct Plan.
  - File-top doc comment notes: currentlyMatchesRules undefined for source==.manual; .match(_, anyOf: []) evaluates false.
  - Blocked-by: diu0hgj (Tests: Compute decision matrix + exclusion table), diu0hgk (Tests: Compute idempotence + determinism (PBT))
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.7](requirements.md#4.7), [4.8](requirements.md#4.8), [4.9](requirements.md#4.9), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5)

- [ ] 10. Tests: Apply (in-memory ModelContainer) <!-- id:diu0hgm -->
  - Add ScrambleTests/RulesEngine/ApplyTests.swift using in-memory container per Phase 1 SchemaTests pattern.
  - Empty plan → no fetch, no save (assert via tracking ModelContext hasChanges before/after).
  - toAddTasks → TripTask inserted with name/phase/masterItemID snapshotted, source=.rule, currentlyMatchesRules=true, pinnedByUser=false, isCompleted=false.
  - toAddPacking → TripPackingItem inserted with name/person resolved by personID/masterItemID snapshotted, state=.unpacked.
  - Missing person at apply time → insert skipped + log emitted.
  - toFlagUnmatched/toFlagMatched → only currentlyMatchesRules mutated; name/phase/person/state untouched.
  - Missing trip (cross-device delete race) → log + return, no throw.
  - Missing trip-level item (cross-device cascade) → log + skip.
  - Blocked-by: diu0hge (Implement Snapshots.swift + Plan.swift)
  - Stream: 1
  - Requirements: [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.7](requirements.md#4.7)

- [ ] 11. Implement apply(plan:context:) in Apply.swift <!-- id:diu0hgn -->
  - Add Scramble/Scramble/RulesEngine/Apply.swift, @MainActor.
  - Algorithm per design.md: short-circuit on Plan.isEmpty; fetch Trip by id; insert tasks/packing per snapshot; fetch + update flag for toFlag*; context.save().
  - Implementer-choice fetch: FetchDescriptor with #Predicate { ids.contains($0.id) } preferred; per-id or trip-then-filter acceptable.
  - All skip paths log via modelLogger with [RulesEngine.skip-*] markers; save failure logs [RulesEngine.save-failed] and throws.
  - Blocked-by: diu0hgl (Implement compute(...) in Compute.swift), diu0hgm (Tests: Apply (in-memory ModelContainer))
  - Stream: 1
  - Requirements: [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5)

- [ ] 12. Tests: RulesEngineRunner end-to-end <!-- id:diu0hgo -->
  - Add ScrambleTests/RulesEngine/RulesEngineRunnerTests.swift using in-memory container.
  - runForTrip captures snapshot, computes, applies; round-trip end-to-end on a seeded trip.
  - runForAllNonPastTrips(today:calendar:) only touches non-past trips; the past trip is left untouched.
  - Empty store (zero trips) returns []; no crash.
  - Per-trip catch: first trip throws on apply (corrupt-blob fixture); second trip still processed; returns [Plan] containing only successful entries.
  - Snapshot capture skips MasterPackingItem with person==nil (logs [RulesEngine.skip-orphan-master]).
  - Second invocation against unchanged state returns empty Plan (AC 5.6 idempotency, end-to-end).
  - AC 7.1: rename a MasterTaskItem after a trip references it; re-run; assert existing TripTask.name unchanged.
  - AC 7.2: change a MasterTaskItem.phase; re-run; assert existing TripTask.phase unchanged.
  - AC 7.3: change a MasterPackingItem.person; re-run; assert existing TripPackingItem.person unchanged.
  - Blocked-by: diu0hgn (Implement apply(plan:context:) in Apply.swift)
  - Stream: 1
  - Requirements: [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.6](requirements.md#5.6), [5.7](requirements.md#5.7), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.5](requirements.md#7.5)

- [ ] 13. Implement RulesEngineRunner.swift <!-- id:diu0hgp -->
  - Add Scramble/Scramble/RulesEngine/RulesEngineRunner.swift, @MainActor struct.
  - runForTrip(_:): build TripSnapshot from a Trip @Model, fetch all masters as snapshots (skip nil-person), call compute, call apply, return Plan.
  - runForAllNonPastTrips(today:calendar:): predicate = calendar.startOfDay(endDate) >= calendar.startOfDay(today); evaluated once at top; per-trip do/catch around runForTrip; returns [Plan] of successful runs.
  - Snapshot factories on extensions of Trip/MasterTaskItem/MasterPackingItem (private to RulesEngine module).
  - Blocked-by: diu0hgo (Tests: RulesEngineRunner end-to-end)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.7](requirements.md#5.7), [7.5](requirements.md#7.5)

## Master lists UI

- [ ] 14. Tests: MasterTaskDraft + MasterPackingDraft validate() <!-- id:diu0hgq -->
  - Add ScrambleTests/MasterLists/MasterDraftTests.swift.
  - MasterTaskDraft: empty name → [.name: msg]; valid name → empty error map.
  - MasterPackingDraft: empty name → [.name: msg]; nil person → [.person: msg]; both → both fields populated.
  - Stream: 1
  - Requirements: [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5)

- [ ] 15. Implement MasterTaskDraft + MasterPackingDraft + MasterPersistence <!-- id:diu0hgr -->
  - Add Scramble/Scramble/Features/MasterLists/MasterTaskDraft.swift, MasterPackingDraft.swift.
  - Add Scramble/Scramble/Features/MasterLists/MasterPersistence.swift: createTask/applyTask/deleteTask + createPacking/applyPacking/deletePacking. None call context.save() — caller saves.
  - Blocked-by: diu0hgq (Tests: MasterTaskDraft + MasterPackingDraft validate())
  - Stream: 1
  - Requirements: [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6)

- [ ] 16. Implement ConditionsEditor + AdvancedConditionView <!-- id:diu0hgs -->
  - Add Scramble/Scramble/Features/MasterLists/ConditionsEditor.swift: ForEach(TripAttribute.allCases) row with LazyVGrid adaptive(minimum: 88) chip multi-select; binding to AttributeSelections.
  - Add Scramble/Scramble/Features/MasterLists/AdvancedConditionView.swift: ContentUnavailableView-style with prettyPrinted output + Reset to simple button + confirmation dialog ('Reset conditions to empty? On the next re-evaluation this item will match every non-past trip until you save new conditions.') — on confirm calls onReset, which writes .always.
  - Chip selected: theme accent fill; unchecked: 1pt surfaceBorder outline + surface fill.
  - Blocked-by: diu0hgg (Implement AttributeSelections.swift), diu0hgi (Implement ItemConditions+PrettyPrint.swift)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.7](requirements.md#3.7)

- [ ] 17. Implement MasterTaskEditor + MasterPackingEditor (wires AC 5.3 trigger) <!-- id:diu0hgt -->
  - Add Scramble/Scramble/Features/MasterLists/MasterTaskEditor.swift: Form with name field, Phase Picker, ConditionsEditor (or AdvancedConditionView if AttributeSelections.from returns nil); Save/Cancel toolbar; Delete with confirmation. Inline validation per AC 1.5.
  - Add Scramble/Scramble/Features/MasterLists/MasterPackingEditor.swift: same pattern, Person picker, validation per AC 2.5.
  - Both editors' Save closure: (1) MasterPersistence.{create|apply}*, (2) modelContext.save() with try/catch → toast, (3) RulesEngineRunner(context:).runForAllNonPastTrips() with try/catch → 'Saved. Some trips couldn't be updated…' toast (per design Error Handling table).
  - Delete closure: same 3-step pattern with deleteTask/deletePacking.
  - Blocked-by: diu0hgp (Implement RulesEngineRunner.swift), diu0hgr (Implement MasterTaskDraft + MasterPackingDraft + MasterPersistence), diu0hgs (Implement ConditionsEditor + AdvancedConditionView)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6), [5.3](requirements.md#5.3)

- [ ] 18. Implement MasterTasksList + MasterPackingList <!-- id:diu0hgu -->
  - Add Scramble/Scramble/Features/MasterLists/MasterTasksList.swift: @Query(sort: \.name) all MasterTaskItem; in-memory group by phase iterating Phase.allCases skipping empty groups; '+ Add task' dashed-border button; .sheet for MasterTaskEditor (create / edit).
  - Add Scramble/Scramble/Features/MasterLists/MasterPackingList.swift: @Query all MasterPackingItem + @Query all Person; group by person sorted by Person.name asc; per-person header shows owned-item count; '+ Add item' affordance.
  - Empty state for AC 2.7: when @Query Person is empty, render ContentUnavailableView 'No people yet' with 'Add a person to a trip first, then return here to define their packing items.' Hide '+ Add item' affordance.
  - Blocked-by: diu0hgt (Implement MasterTaskEditor + MasterPackingEditor (wires AC 5.3 trigger))
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.7](requirements.md#2.7), [8.1](requirements.md#8.1)

- [ ] 19. Wire MasterListsTab to host the two list views <!-- id:diu0hgv -->
  - Modify Scramble/Scramble/Features/MasterLists/MasterListsTab.swift: keep existing segmented control (Packing Items / Tasks); replace placeholder body with switch on segment → MasterTasksList() / MasterPackingList().
  - NavigationStack wraps content; tab keeps the existing navigation title.
  - Wiring task — content ACs are covered by tasks 17/18, so this is exempt from a preceding test task per skill rules.
  - Blocked-by: diu0hgu (Implement MasterTasksList + MasterPackingList)
  - Stream: 1

## Lifecycle trigger wiring

- [ ] 20. Wire AC 5.4 cold-launch scan in ScrambleApp.init() <!-- id:diu0hgw -->
  - Modify Scramble/Scramble/ScrambleApp.swift: after the existing UITestSeed.applyIfRequested block, add `try? RulesEngineRunner(context: ModelStore.shared.mainContext).runForAllNonPastTrips()`.
  - Wiring task — covered by RulesEngineRunnerTests + ColdLaunchSequencingUITests.
  - Blocked-by: diu0hgp (Implement RulesEngineRunner.swift)
  - Stream: 1
  - Requirements: [5.4](requirements.md#5.4)

- [ ] 21. Wire AC 5.7 scenePhase trigger in RootView <!-- id:diu0hgx -->
  - Modify Scramble/Scramble/Features/Root/RootView.swift: add @Environment(\.scenePhase), @State previousScenePhase: ScenePhase? = nil, .onChange(of: scenePhase) handler.
  - Handler: guard previousScenePhase == .background AND newPhase == .active → call try? RulesEngineRunner(...).runForAllNonPastTrips() with MainActor. defer { previousScenePhase = newPhase }.
  - Carve-out: nil → .inactive → .active sequence at cold launch must NOT fire the trigger (covered by RootViewScenePhaseTests).
  - Blocked-by: diu0hgp (Implement RulesEngineRunner.swift)
  - Stream: 1
  - Requirements: [5.7](requirements.md#5.7)

- [ ] 22. Wire AC 5.1 + 5.2 in TripListView + TripDetailView onSave closures <!-- id:diu0hgy -->
  - Modify Scramble/Scramble/Features/Trips/TripListView.swift onSave closure (create path): after TripPersistence.create + modelContext.save, insert `try? RulesEngineRunner(context: modelContext).runForTrip(newTrip)` before returning true.
  - Modify Scramble/Scramble/Features/Trips/TripDetailView.swift onSave closure at TripEditorView(mode: .edit(trip)) at line 79: after TripPersistence.apply + modelContext.save, insert `try? RulesEngineRunner(context: modelContext).runForTrip(trip)` before dismiss.
  - Runner-throw path surfaces transient toast using the existing TripPersistence orphan-participants toast pattern.
  - Blocked-by: diu0hgp (Implement RulesEngineRunner.swift)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2)

## UI and integration tests

- [ ] 23. MasterListsCRUDUITests <!-- id:diu0hgz -->
  - Add ScrambleUITests/MasterListsCRUDUITests.swift.
  - Create master task: open Master Lists → Tasks segment → '+ Add task' → fill name + select phase + skip conditions → Save → assert row appears under correct Phase header.
  - Edit master task: open existing row → change name → Save → assert row text updates.
  - Delete master task: open row → Delete → confirm → assert row disappears.
  - Mirror trio for master packing item (Packing segment, person selection, person-grouped row).
  - Blocked-by: diu0hgv (Wire MasterListsTab to host the two list views)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.6](requirements.md#1.6), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.6](requirements.md#2.6)

- [ ] 24. ConditionsEditorUITests <!-- id:diu0hh0 -->
  - Add ScrambleUITests/ConditionsEditorUITests.swift.
  - Round-trip: open editor, select Weather chips (rain, cold), select Scope chip (international), Save, reopen, assert chips reflect saved selection (AC 3.6).
  - Empty save: open editor, leave all attribute rows empty, Save, reopen, assert empty state matches .always (AC 3.4).
  - Domain-mismatched fixture seeded via UITestSeed: master with stored .all([.match(.weather, ['snow'])]) (snow not in domain). On open, AdvancedConditionView rendered; conditions section disabled; name + phase fields still editable (AC 3.7a + 3.7b).
  - Reset to simple: tap Reset on AdvancedConditionView → confirm dialog → confirm → assert editor flips to ConditionsEditor with all chips empty (AC 3.7c).
  - Blocked-by: diu0hgv (Wire MasterListsTab to host the two list views)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.4](requirements.md#3.4), [3.6](requirements.md#3.6), [3.7](requirements.md#3.7)

- [ ] 25. MasterPackingEmptyStateUITests <!-- id:diu0hh1 -->
  - Add ScrambleUITests/MasterPackingEmptyStateUITests.swift.
  - Seed: zero Person records. Open Master Lists → Packing Items. Assert ContentUnavailableView text matches the AC 2.7 copy; assert '+ Add item' affordance not present.
  - Blocked-by: diu0hgv (Wire MasterListsTab to host the two list views)
  - Stream: 1
  - Requirements: [2.7](requirements.md#2.7)

- [ ] 26. RulesEnginePopulationUITests <!-- id:diu0hh2 -->
  - Add ScrambleUITests/RulesEnginePopulationUITests.swift.
  - Extend UITestSeed with a phase2-rules-fixture keyword: seed one Person + one MasterPackingItem (e.g., 'Rain jacket' with conditions .all([.match(.weather, ['rain'])])).
  - AC 5.1 create path: launch with fixture, create new trip via TripListView with Weather=Rain, save. Assert (via debug accessibility identifier on TripDetailView) that the trip's packingItems contains 'Rain jacket' with currentlyMatchesRules=true.
  - AC 5.2 edit path: launch with fixture + a Weather=Sun trip pre-seeded, open TripDetailView, change Weather chip to Rain, save. Assert the same population.
  - Add the debug-only accessibility identifier on TripDetailView under #if DEBUG as part of this task.
  - Blocked-by: diu0hgy (Wire AC 5.1 + 5.2 in TripListView + TripDetailView onSave closures)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2)

- [ ] 27. ColdLaunchSequencingUITests <!-- id:diu0hh3 -->
  - Add ScrambleUITests/ColdLaunchSequencingUITests.swift.
  - Seed: one qualifying trip (start ≤ today+2d, end ≥ today) AND a MasterTaskItem whose conditions newly match. Cold launch.
  - Phase 1 AC 5.6 auto-open should land on TripDetail; assert the trip's tasks collection contains the rule-driven master with currentlyMatchesRules=true.
  - This proves ScrambleApp.init() scan completes before TripsTab's auto-open task fires.
  - Blocked-by: diu0hgw (Wire AC 5.4 cold-launch scan in ScrambleApp.init()), diu0hh2 (RulesEnginePopulationUITests)
  - Stream: 1
  - Requirements: [5.4](requirements.md#5.4)

- [ ] 28. RootViewScenePhaseTests <!-- id:diu0hh4 -->
  - Add ScrambleUITests/RootViewScenePhaseTests.swift (XCUITest, host-app harness).
  - Cold-launch carve-out: launch the app; nil → .inactive → .active sequence should NOT call the runner (asserted via a debug-only counter on RulesEngineRunner exposed via accessibility hook).
  - Background → foreground transition: send the app to background, return; assert one runner invocation since the carve-out's previousScenePhase==.background guard now holds.
  - Blocked-by: diu0hgx (Wire AC 5.7 scenePhase trigger in RootView)
  - Stream: 1
  - Requirements: [5.7](requirements.md#5.7)

- [ ] 29. PersonDeletionGuardUITests (extends to master refs) <!-- id:diu0hh5 -->
  - Add ScrambleUITests/PersonDeletionGuardUITests.swift.
  - Seed: a Person with one MasterPackingItem AND zero TripPackingItem refs. Open TripEditorView's person picker, attempt delete on that person; assert PersonDeleteBlocker alert message lists 'Master packing items: …' (proving Phase 1's existing helper handles master refs).
  - This is the only Phase 2 work for AC 8.2 (no new code — see design.md Person deletion guard section).
  - Blocked-by: diu0hgv (Wire MasterListsTab to host the two list views)
  - Stream: 1
  - Requirements: [8.2](requirements.md#8.2)
