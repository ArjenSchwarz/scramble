---
references:
    - specs/packing-item-categories/requirements.md
    - specs/packing-item-categories/design.md
    - specs/packing-item-categories/decision_log.md
---
# Tasks: Packing Item Categories

## Foundation

- [x] 1. Add category field to packing item models <!-- id:00zzi94 -->
  - Optional `category: String?` (nil default) on MasterPackingItem and TripPackingItem, plus init params.
  - Mirrors `note`; rides SchemaV3 lightweight inference — no SchemaV4, no models-array change.
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1)

- [x] 2. Write PackingCategory normalization/ordering tests <!-- id:00zzi95 -->
  - storageValue trims and collapses internal whitespace, case preserved, nil on empty/whitespace; normalizedKey uses non-localized lowercased().
  - keyOrder and rawOrder use Unicode-scalar order with nil last; displayLabel deterministic via rawOrder.
  - PBT: storageValue/normalizedKey idempotence; keyOrder total order.
  - Stream: 2
  - Requirements: [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.5](requirements.md#1.5), [5.2](requirements.md#5.2), [5.6](requirements.md#5.6)

- [x] 3. Implement PackingCategory namespace <!-- id:00zzi96 -->
  - New pure `Models/PackingCategory.swift` namespace implementing the functions under test. No SwiftData.
  - Blocked-by: 00zzi95 (Write PackingCategory normalization/ordering tests)
  - Stream: 2
  - Requirements: [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.5](requirements.md#1.5), [5.2](requirements.md#5.2), [5.6](requirements.md#5.6)

## Rules engine re-stamp

- [x] 4. Add category to snapshots, refs, and Plan re-stamp type <!-- id:00zzi97 -->
  - Add `category` to MasterPackingSnapshot and TripPackingItemRef; capture in fetchMasterPackingSnapshots and TripSnapshot.capture.
  - Add `PackingCategoryRestamp { id; category: String? }` and `Plan.toRestampCategory` (sorted by id, included in isEmpty). Types/wiring only.
  - Blocked-by: 00zzi94 (Add category field to packing item models)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2)

- [x] 5. Write ComputeTests for category re-stamp <!-- id:00zzi98 -->
  - present and differs => emit; equal => none; present-with-nil over non-nil item => emit nil (clear).
  - master absent/deleted => none (freeze); manual one-off (masterItemID nil) => none.
  - second pass with unchanged master => empty (idempotence). Exact-string compare.
  - Blocked-by: 00zzi97 (Add category to snapshots, refs, and Plan re-stamp type)
  - Stream: 1
  - Requirements: [3.2](requirements.md#3.2), [3.4](requirements.md#3.4), [3.6](requirements.md#3.6), [3.7](requirements.md#3.7), [4.3](requirements.md#4.3)

- [x] 6. Implement compute re-stamp emission <!-- id:00zzi99 -->
  - compute branches on master presence (not value) and emits toRestampCategory per the test matrix.
  - Blocked-by: 00zzi98 (Write ComputeTests for category re-stamp)
  - Stream: 1
  - Requirements: [3.2](requirements.md#3.2), [3.4](requirements.md#3.4), [3.6](requirements.md#3.6), [4.3](requirements.md#4.3)

- [x] 7. Write ApplyTests for re-stamp and creation stamping <!-- id:00zzi9a -->
  - apply writes only category (no other field, especially not name); empty toRestampCategory => no write.
  - insertAddedPacking stamps master.category at creation.
  - Blocked-by: 00zzi97 (Add category to snapshots, refs, and Plan re-stamp type)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4)

- [x] 8. Implement apply re-stamp and insertAddedPacking stamping <!-- id:00zzi9b -->
  - apply runs restampCategories before hook.commit; insertAddedPacking passes category: master.category.
  - Blocked-by: 00zzi9a (Write ApplyTests for re-stamp and creation stamping)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4)

## Sync

- [x] 9. Write translator round-trip tests for category <!-- id:00zzi9c -->
  - category survives toRecord then from; nil round-trips; absent inbound key decodes to nil (unconditional).
  - Blocked-by: 00zzi94 (Add category field to packing item models)
  - Stream: 1
  - Requirements: [7.2](requirements.md#7.2), [7.3](requirements.md#7.3)

- [x] 10. Implement unconditional category read/write in translator <!-- id:00zzi9d -->
  - Unconditional read/write in TripPackingItemRecordTranslator, matching note.
  - write record["category"] = item.category as CKRecordValue?; read item.category = record["category"] as? String.
  - Blocked-by: 00zzi9c (Write translator round-trip tests for category)
  - Stream: 1
  - Requirements: [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3)

## Master-list editing

- [x] 11. Write MasterPersistence category carry-through tests <!-- id:00zzi9e -->
  - createPacking, applyPacking, and copyPacking (copy-to-people) all persist category; storageValue normalization applied on store.
  - Blocked-by: 00zzi94 (Add category field to packing item models)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [2.1](requirements.md#2.1)

- [x] 12. Add category to MasterPackingDraft and thread through persistence <!-- id:00zzi9f -->
  - Add `category` to MasterPackingDraft (field + newDraft + init(from:)); thread through the three MasterPersistence sites.
  - validate() unchanged (category optional).
  - Blocked-by: 00zzi9e (Write MasterPersistence category carry-through tests)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [2.1](requirements.md#2.1)

- [x] 13. Write distinctCategories suggestion-gathering tests <!-- id:00zzi9g -->
  - Merges MasterPackingItem (globals) + TripPackingItem (tripsLocal); dedupe by normalizedKey; canonical spelling via displayLabel; ordered by keyOrder.
  - Participant device (no masters) yields trip-visible categories only (Req 2.5).
  - Blocked-by: 00zzi94 (Add category field to packing item models), 00zzi96 (Implement PackingCategory namespace)
  - Stream: 2
  - Requirements: [2.2](requirements.md#2.2), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5)

- [x] 14. Implement distinctCategories helper <!-- id:00zzi9h -->
  - Implement distinctCategories(globals:tripsLocal:) reading each container's mainContext via FetchDescriptor.
  - Blocked-by: 00zzi9g (Write distinctCategories suggestion-gathering tests)
  - Stream: 2
  - Requirements: [2.2](requirements.md#2.2), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5)

- [x] 15. Add category Section with suggestions to MasterPackingEditor <!-- id:00zzi9i -->
  - Category Section between person and conditions: TextField bound to draft.category + tappable suggestions.
  - Reads modelContext=globals + the tripsLocalContainer env key; computed once on appear; selecting stores canonical spelling; normalized matching presents variants as one.
  - Blocked-by: 00zzi9f (Add category to MasterPackingDraft and thread through persistence), 00zzi9h (Implement distinctCategories helper)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4)

## Trip manual form

- [x] 16. Add category field, suggestions, and read-only gate to PackingItemForm <!-- id:00zzi9j -->
  - Category field in Section("Item"); thread into performAdd/performEdit.
  - Inject the globalsContainer env key for suggestions; render read-only when isParticipantViewingSharedTrip && item.masterItemID != nil.
  - Re-inject the participant env key at PackingSheet's .sheet presentation site (sheets don't inherit custom env keys).
  - Blocked-by: 00zzi94 (Add category field to packing item models), 00zzi9h (Implement distinctCategories helper)
  - Stream: 1
  - Requirements: [3.5](requirements.md#3.5), [4.1](requirements.md#4.1)

## Grouped display

- [ ] 17. Write categorySections grouping-helper tests <!-- id:00zzi9k -->
  - Partition (each item in exactly one section; section count == distinct normalized keys); uncategorised last.
  - within-section order via supplied comparator; single-uncategorised input => one nil section (the flat signal); deterministic label.
  - PBT: partition invariant.
  - Blocked-by: 00zzi96 (Implement PackingCategory namespace)
  - Stream: 2
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2)

- [ ] 18. Implement categorySections helper <!-- id:00zzi9l -->
  - Generic categorySections<Item>(_:category:sortWithin:) returning ordered CategorySection values. Place in PackingListHelpers or PackingCategory.
  - Blocked-by: 00zzi9k (Write categorySections grouping-helper tests)
  - Stream: 2
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.6](requirements.md#5.6), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2)

- [ ] 19. Render category sub-grouping in PackingSheet <!-- id:00zzi9m -->
  - PackingItemGroup uses categorySections(filter(group.matches)): flat (no sub-header) when single-uncategorised; else category sub-headers with .accessibilityAddTraits(.isHeader).
  - within-section sorted order preserved; both modes incl read-only repack sections; one pass per body.
  - One-off items group identically (Req 4.2); uncategorised bucket includes pre-existing items (Req 1.4).
  - Blocked-by: 00zzi9l (Implement categorySections helper), 00zzi94 (Add category field to packing item models)
  - Stream: 2
  - Requirements: [1.4](requirements.md#1.4), [4.2](requirements.md#4.2), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.7](requirements.md#5.7), [5.8](requirements.md#5.8)

- [ ] 20. Sub-group by category within each person in MasterPackingList <!-- id:00zzi9n -->
  - Within each existing per-person Section, sub-group items via categorySections; flat when none categorised; ordering consistent with the sheet.
  - Uncategorised includes pre-existing items (Req 1.4).
  - Blocked-by: 00zzi9l (Implement categorySections helper), 00zzi94 (Add category field to packing item models)
  - Stream: 2
  - Requirements: [1.4](requirements.md#1.4), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2)

## Release prep

- [ ] 21. Update release-prep CloudKit schema-promotion checklist <!-- id:00zzi9o -->
  - Add MasterPackingItem.category (auto-mirrored private DB) and TripPackingItem.category (shared zone) to the promote-to-Production checklist in docs/release-prep.md.
  - The manual Dashboard promotion itself is a release prerequisite, not a code task.
  - Stream: 1
  - Requirements: [7.1](requirements.md#7.1), [7.2](requirements.md#7.2)
