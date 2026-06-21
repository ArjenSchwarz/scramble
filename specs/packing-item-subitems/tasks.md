---
references:
    - specs/packing-item-subitems/requirements.md
    - specs/packing-item-subitems/design.md
    - specs/packing-item-subitems/decision_log.md
---
# Packing Item Sub-items

## Model & domain

- [x] 1. Write TripPackingItem note/subItems bridge tests (red) <!-- id:6zw6ike -->
  - Assert subItems get/set round-trip; subItems=[] ⇒ subItemsData==nil; a non-nil empty Data() reads back as []; garbage Data decodes to []; note set then clear.
  - Setting state to .excluded and back leaves note/subItems unchanged (skip→restore survival).
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [7.5](requirements.md#7.5)
  - References: Scramble/Scramble/Models/TripPackingItem.swift, Scramble/ScrambleTests/

- [x] 2. Add note + subItemsData fields + subItems bridge to TripPackingItem (green) <!-- id:6zw6ikf -->
  - note: String? and subItemsData: Data?, both Optional/nil-default so they ride on SchemaV3 — NO SchemaV4.
  - subItems bridge getter normalises empty Data()→[] via CodableBridge; setter stores nil for an empty list.
  - Add note param to init.
  - Blocked-by: 6zw6ike (Write TripPackingItem note/subItems bridge tests (red))
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [6.1](requirements.md#6.1)
  - References: Scramble/Scramble/Models/TripPackingItem.swift

- [x] 3. Write PackingSubItems helper tests incl. property-based round-trip (red) <!-- id:6zw6ikg -->
  - sanitizedEntry trims + caps 200 grapheme clusters (multi-scalar emoji intact at boundary); appending returns rejectedEmpty / rejectedFull(at 50) / added, preserving duplicates and order; removing(at:) removes only that index, OOR is a no-op; sanitizedNote trims, caps 500 graphemes, nil on empty.
  - PBT: decode(encode(xs))==xs for generated [String] (duplicates/empty/unicode/boundary-length); add/remove length invariants; count never exceeds 50. Use the repo's @Test(arguments:) parameterised style.
  - Stream: 2
  - Requirements: [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.6](requirements.md#2.6), [2.7](requirements.md#2.7), [3.2](requirements.md#3.2), [4.4](requirements.md#4.4)
  - References: Scramble/ScrambleTests/

- [x] 4. Implement PackingSubItems pure helpers (green) <!-- id:6zw6ikh -->
  - New Scramble/Scramble/Models/PackingSubItems.swift; maxCount=50, maxItemLength=200, maxNoteLength=500; AddOutcome enum; sanitizedEntry/appending/removing/sanitizedNote; no view or ModelContext dependency.
  - Blocked-by: 6zw6ikg (Write PackingSubItems helper tests incl. property-based round-trip (red))
  - Stream: 2
  - Requirements: [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.6](requirements.md#2.6), [2.7](requirements.md#2.7), [3.2](requirements.md#3.2), [4.4](requirements.md#4.4)
  - References: Scramble/Scramble/Models/PackingSubItems.swift

## Sync & migration

- [ ] 5. Write translator clear-matrix + blob-cap tests (red) <!-- id:6zw6iki -->
  - Extend TripPackingItemRecordTranslatorTests: note+subItems survive toRecord→from without loss/reorder; clear matrix {nil, empty, non-empty} including non-nil empty Data() (must serialise as an absent field); populated→cleared yields nil/[] on the receiver; blobTooLarge thrown when subItemsData is forced over kRecordBlobSizeCap.
  - Blocked-by: 6zw6ikf (Add note + subItemsData fields + subItems bridge to TripPackingItem (green))
  - Stream: 1
  - Requirements: [6.2](requirements.md#6.2), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5)
  - References: Scramble/Scramble/Sharing/Translators/TripPackingItemRecordTranslator.swift, Scramble/ScrambleTests/Sharing/Translators/

- [ ] 6. Implement translator note/subItemsData encode/decode (green) <!-- id:6zw6ikj -->
  - toRecord: note as CKRecordValue? (nil clears); subItemsData written only when non-empty with cap check, else cleared.
  - from: unconditional assignment for both (clear-propagation; masterItemID precedent), diverging from the if-let sibling fields.
  - Add a doc comment on from(): requires a full server snapshot — never pass a partial/desiredKeys record.
  - Blocked-by: 6zw6iki (Write translator clear-matrix + blob-cap tests (red))
  - Stream: 1
  - Requirements: [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5)
  - References: Scramble/Scramble/Sharing/Translators/TripPackingItemRecordTranslator.swift

- [ ] 7. Write relocation, migration-materialization, and rules-independence tests (red) <!-- id:6zw6ikk -->
  - ZoneMigrationCoordinator.relocateTrip carries note/subItemsData; an item with both nil relocates as still-nil (not an empty blob).
  - Opening a pre-feature SchemaV3-shaped store surfaces the two new columns as nil (no SchemaV4, no duplicate-checksum crash).
  - Running RulesEngineRunner.runForTrip leaves existing items' note/subItems unchanged and does not affect counts/groups (Req 7.1–7.3); deleting an item removes its note/subItems (7.4).
  - Blocked-by: 6zw6ikf (Add note + subItemsData fields + subItems bridge to TripPackingItem (green))
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4)
  - References: Scramble/Scramble/Persistence/Migrations/ZoneMigrationCoordinator.swift, Scramble/ScrambleTests/Persistence/

- [ ] 8. Carry note/subItemsData through the relocateTrip clone (green) <!-- id:6zw6ikl -->
  - Copy note and subItemsData onto the relocated TripPackingItem alongside the existing field list (≈line 360).
  - Blocked-by: 6zw6ikk (Write relocation, migration-materialization, and rules-independence tests (red))
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1)
  - References: Scramble/Scramble/Persistence/Migrations/ZoneMigrationCoordinator.swift

## UI

- [ ] 9. Implement PackingSubItemsView (green) <!-- id:6zw6ikm -->
  - New Scramble/Scramble/Components/PackingSubItemsView.swift; plain-value params (note, subItems, isInteractive, accent, onAdd, onRemove, onEditNote), no @Model reference.
  - Renders note (tappable→onEditNote when interactive) + sub-item rows + reveal-on-tap add field (@FocusState, live 200-cap .onChange, hidden at 50 items).
  - Row-local @State [SubItemDraft] (id=UUID) re-seeded on .onChange(of: subItems); ForEach by id, never id:\.self; remove maps draft→index→onRemove.
  - a11y: sub-item list as .contain container with per-entry Remove actions; Dynamic Type wraps, no truncation.
  - Blocked-by: 6zw6ikf (Add note + subItemsData fields + subItems bridge to TripPackingItem (green)), 6zw6ikh (Implement PackingSubItems pure helpers (green))
  - Stream: 2
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.7](requirements.md#2.7), [3.1](requirements.md#3.1), [4.2](requirements.md#4.2), [5.1](requirements.md#5.1), [5.3](requirements.md#5.3), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3)
  - References: Scramble/Scramble/Components/PackingSubItemsView.swift

- [ ] 10. Write PackingItemForm note-field helper tests (red) <!-- id:6zw6ikn -->
  - performAdd/performEdit set item.note = sanitizedNote(input); clearing to empty stores nil; live 500-grapheme cap.
  - Blocked-by: 6zw6ikf (Add note + subItemsData fields + subItems bridge to TripPackingItem (green)), 6zw6ikh (Implement PackingSubItems pure helpers (green))
  - Stream: 2
  - Requirements: [4.1](requirements.md#4.1), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4)
  - References: Scramble/Scramble/Features/Trips/PackingItemForm.swift, Scramble/ScrambleTests/

- [ ] 11. Add the note field to PackingItemForm (green) <!-- id:6zw6iko -->
  - TextField(axis:.vertical) below the name field, capped via sanitizedNote semantics; shown in add and edit modes; wired through performAdd/performEdit.
  - Blocked-by: 6zw6ikn (Write PackingItemForm note-field helper tests (red))
  - Stream: 2
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4)
  - References: Scramble/Scramble/Features/Trips/PackingItemForm.swift

- [ ] 12. Wire PackingItemRow + PackingItemGroup (green) <!-- id:6zw6ikp -->
  - PackingItemGroup.addSubItem/removeSubItem mutate via PackingSubItems then save(_:) through the hook chokepoint; add/remove never change state or group (Req 2.5/3.3).
  - Embed PackingSubItemsView in PackingItemRow below the name and above WhyDisclosure; PackingItemRow.body reads item.note/item.subItems directly for SwiftData observation; onEditNote reuses the existing .edit form presentation.
  - Restructure the row a11y from .combine to a combined row element (carrying the Add sub-item custom action) plus the .contain sub-item list; gate add/remove on !SheetGroup.isReadOnly; display still renders on read-only/dimmed rows (5.2/5.4).
  - Widen the sheet background tap-catcher to also dismiss the active add field; update any existing PackingItemRow a11y tests.
  - Blocked-by: 6zw6ikm (Implement PackingSubItemsView (green)), 6zw6iko (Add the note field to PackingItemForm (green)), 6zw6ikh (Implement PackingSubItems pure helpers (green))
  - Stream: 2
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.5](requirements.md#2.5), [3.1](requirements.md#3.1), [3.3](requirements.md#3.3), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.4](requirements.md#5.4), [6.3](requirements.md#6.3), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)
  - References: Scramble/Scramble/Components/PackingItemRow.swift, Scramble/Scramble/Features/Trips/PackingSheet.swift

- [ ] 13. Write UI test for inline add/remove and read-only display (red) <!-- id:6zw6ikq -->
  - ScrambleUITests: in pack mode reveal the add field, type a sub-item, submit → it renders on the row; remove it; switch the item to Not bringing → the sub-item shows but no add/remove control appears. Add the needed accessibility identifiers.
  - Blocked-by: 6zw6ikp (Wire PackingItemRow + PackingItemGroup (green)), 6zw6iko (Add the note field to PackingItemForm (green))
  - Stream: 2
  - Requirements: [2.2](requirements.md#2.2), [3.1](requirements.md#3.1), [5.2](requirements.md#5.2)
  - References: Scramble/ScrambleUITests/
