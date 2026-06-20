---
references:
    - specs/copy-master-packing-items/requirements.md
    - specs/copy-master-packing-items/design.md
    - specs/copy-master-packing-items/decision_log.md
---
# Copy Master Packing Items — Implementation Tasks

## Persistence & helpers

- [x] 1. Write tests for the pure copy helpers (normalizedName, copyToastMessage) <!-- id:6axrhsd -->
  - New Swift Testing suite (e.g. Scramble/ScrambleTests/MasterLists/CopyPackingTests.swift).
  - normalizedName: trims surrounding whitespace + lowercases; '  Socks ' and 'socks' map equal; empty/whitespace-only maps to empty string.
  - copyToastMessage(copiedNames:skippedNames:): copied-only, copied-with-skips, and all-skipped (empty copied) wordings; names rendered in the message.
  - Tests reference symbols that do not exist yet, so the suite fails to compile (red).
  - Stream: 1
  - Requirements: [3.7](requirements.md#3.7), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2)
  - References: Scramble/ScrambleTests/MasterLists/MasterDraftTests.swift

- [x] 2. Implement CopyResult, normalizedName, and copyToastMessage in MasterPersistence <!-- id:6axrhse -->
  - CopyResult: Sendable value type { createdCount: Int; copiedNames: [String]; skippedNames: [String] } — no @Model values.
  - nonisolated static normalizedName(_:) and nonisolated static copyToastMessage(copiedNames:skippedNames:) (MasterPersistence is a @MainActor enum; these must be nonisolated to be callable from tests without await).
  - Blocked-by: 6axrhsd (Write tests for the pure copy helpers (normalizedName, copyToastMessage)), helpers, helpers, helpers, helpers, helpers
  - Stream: 1
  - Requirements: [3.7](requirements.md#3.7), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2)
  - References: Scramble/Scramble/Features/MasterLists/MasterPersistence.swift

- [x] 3. Write tests for MasterPersistence.copyPacking <!-- id:6axrhsf -->
  - In-memory ModelContainer: Schema(versionedSchema: SchemaV3.self), isStoredInMemoryOnly, cloudKitDatabase: .none (mirror RulesEngineRunnerTests.makeContainer).
  - One copy per eligible target, each owned by the right Person (3.1); copied name equals trimmed source name (3.2).
  - Skips a target already owning a same-name item, case-insensitive + trimmed (2.3/3.5); skipped person name appears in skippedNames.
  - All targets already own it -> createdCount == 0 and nothing inserted (3.7).
  - Duplicate ids in toPersonIDs produce exactly one copy (de-dupe).
  - Conditions fidelity: source with nested .all([.any([.match,.match]), .match]); assert copy.conditions == source.conditions (decoded value, NOT conditionsData byte-equality) (3.3) and mutating the copy leaves the source unchanged (3.4).
  - Blocked-by: 6axrhse (Implement CopyResult, normalizedName, and copyToastMessage in MasterPersistence)
  - Stream: 1
  - Requirements: [2.3](requirements.md#2.3), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.7](requirements.md#3.7)
  - References: Scramble/ScrambleTests/RulesEngine/RulesEngineRunnerTests.swift, Scramble/Scramble/Features/MasterLists/MasterPersistence.swift

- [x] 4. Implement MasterPersistence.copyPacking <!-- id:6axrhsg -->
  - Signature: @discardableResult static func copyPacking(source: MasterPackingItem, toPersonIDs: [UUID], in context: ModelContext) -> CopyResult.
  - De-dupe toPersonIDs; for each, resolve Person and skip when its masterPackingItems already contains normalizedName(source.name).
  - Create MasterPackingItem(name: source.name trimmed, person: target, conditions: source.conditions) — passing the decoded value gives deep-equal + independent copy.
  - Insert into context; do NOT call save() (caller owns mutate -> save -> run-engine, per MasterPersistence convention).
  - Blocked-by: 6axrhsf (Write tests for MasterPersistence.copyPacking)
  - Stream: 1
  - Requirements: [2.3](requirements.md#2.3), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.7](requirements.md#3.7)
  - References: Scramble/Scramble/Features/MasterLists/MasterPersistence.swift, Scramble/Scramble/Models/MasterPackingItem.swift

- [x] 5. Write engine-integration and save-atomicity tests for the copy sequence <!-- id:6axrhsh -->
  - Materialisation: seed a trip whose attributes satisfy the copied conditions and one that does not; copyPacking -> context.save() -> RulesEngineRunner.runForAllNonPastTrips(); assert a TripPackingItem for the target Person exists on the matching trip and not on the non-matching one (4.1).
  - Atomicity mechanism (3.6): copyPacking inserts but does not save; a subsequent context.rollback() leaves zero new MasterPackingItems persisted and no engine run occurred.
  - Use a recording-notifier LocalWriteHook as in ApplyTests / PackingFormSaveTests; runner wired context = trips, mastersContext = masters (same container is fine).
  - Blocked-by: 6axrhsg (Implement MasterPersistence.copyPacking)
  - Stream: 1
  - Requirements: [3.6](requirements.md#3.6), [4.1](requirements.md#4.1)
  - References: Scramble/ScrambleTests/RulesEngine/RulesEngineRunnerTests.swift, Scramble/ScrambleTests/RulesEngine/ApplyTests.swift

## UI & wiring

- [ ] 6. Write tests for the CopyPackingItemSheet eligibility helper <!-- id:6axrhsi -->
  - Static helper resolving eligible target people from a source item + the people list, reading each Person.masterPackingItems via normalizedName (same data path as copyPacking).
  - Owner of the source is excluded (2.1); a person already owning a same-name item is ineligible (2.3); when every other person is ineligible the eligible set is empty (drives the 2.5 empty-state).
  - @MainActor test over an in-memory container (helper touches @Model relationships).
  - Blocked-by: 6axrhse (Implement CopyResult, normalizedName, and copyToastMessage in MasterPersistence)
  - Stream: 2
  - Requirements: [2.1](requirements.md#2.1), [2.3](requirements.md#2.3), [2.5](requirements.md#2.5)
  - References: Scramble/Scramble/Models/Person.swift, Scramble/Scramble/Models/MasterPackingItem.swift

- [ ] 7. Implement CopyPackingItemSheet <!-- id:6axrhsj -->
  - New file Scramble/Scramble/Features/MasterLists/CopyPackingItemSheet.swift.
  - let source; onCopy: ([UUID]) -> Void (raw selected ids, no re-filter); onCancel. @Query(sort: \Person.name) allPeople; @State selected: Set<UUID>.
  - List allPeople minus owner, sorted by name (2.1); multi-select toggles (2.2); ineligible rows disabled + 'already has it' label with accessibilityValue (2.3 display).
  - Confirm disabled until selected-intersect-eligible non-empty (2.4); empty-state when no eligible person (2.5); Cancel/dismiss writes nothing (2.6).
  - Accessibility: copy action label+button trait; success/skip announced via UIAccessibility; DEBUG accessibilityIdentifiers on confirm button and person rows.
  - Blocked-by: 6axrhsi (Write tests for the CopyPackingItemSheet eligibility helper)
  - Stream: 2
  - Requirements: [1.2](requirements.md#1.2), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6)
  - References: Scramble/Scramble/Features/MasterLists/MasterPackingEditor.swift, Scramble/Scramble/Components/PackingItemRow.swift

- [ ] 8. Wire copy into MasterPackingList (SheetTarget merge, row affordance, toast, performCopy) <!-- id:6axrhsk -->
  - Replace EditTarget with one SheetTarget enum { create, edit(PersistentIdentifier), copy(PersistentIdentifier) } behind a single .sheet(item:); unresolved .copy id dismisses with no write.
  - Per-row trailing swipe + long-press context menu 'Copy to people...' gated on source eligibility (1.3: >= 2 people, source.person != nil, trimmed name non-empty); whole-row tap still opens the editor (1.1).
  - Add @Environment(\.tripsLocalContainer), @Environment(\.localWriteHook), @State toastMessage; .transientToast on the list.
  - performCopy(source:toPersonIDs:): copyPacking -> if createdCount == 0 no save/no engine + all-skipped toast (3.7); else modelContext.save() [rollback + 'Copy failed' toast on throw (3.6)] -> RulesEngineRunner(context: tripsLocalContainer.mainContext, mastersContext: modelContext, hook: hook).runForAllNonPastTrips() [deferred toast on top-level throw (4.2)] -> success toast via copyToastMessage (5.1/5.2).
  - Production hook wiring carries materialised TripPackingItems to shared-trip participants (4.3).
  - Blocked-by: 6axrhsj (Implement CopyPackingItemSheet), 6axrhsg (Implement MasterPersistence.copyPacking)
  - Stream: 2
  - Requirements: [1.1](requirements.md#1.1), [1.3](requirements.md#1.3), [3.6](requirements.md#3.6), [3.7](requirements.md#3.7), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2)
  - References: Scramble/Scramble/Features/MasterLists/MasterPackingList.swift, Scramble/Scramble/Components/TransientToast.swift, Scramble/Scramble/RulesEngine/RulesEngineRunner.swift

- [ ] 9. Add UI happy-path test for the copy flow <!-- id:6axrhsl -->
  - ScrambleUITests: seed >= 2 people with a packing master on the source person; open Master Lists -> Packing Items; long-press the source row -> 'Copy to people...'; select a target; confirm.
  - Assert the sheet dismisses and the confirmation toast text naming the target appears; drive via accessibilityIdentifiers from task 7.
  - Blocked-by: 6axrhsk (Wire copy into MasterPackingList (SheetTarget merge, row affordance, toast, performCopy))
  - Stream: 2
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [5.1](requirements.md#5.1)
  - References: Scramble/ScrambleUITests
