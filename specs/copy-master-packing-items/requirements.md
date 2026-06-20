# Requirements: Copy Master Packing Items

## Introduction

People on a trip often need the same packing items — underwear, shirts, a toothbrush — so re-entering each one per person in the Master Lists tab is repetitive. This feature lets the user copy one master packing item to one or more other people in a single action, producing an independent complete copy (same name, same conditions) for each target. The rules engine then materialises the new items onto every matching trip exactly as if they had been authored by hand.

## Non-Goals

- Copying trip-level packing items between people within a single trip (this feature is Master-Lists-only; trip items are produced by the rules engine).
- Copying multiple source items in one action (one source item per copy; see Decision 3).
- Overwriting or merging conditions on a target who already owns a same-name item (such people are skipped; see Decision 2).
- Copying master *task* items (this feature covers packing items only).
- Creating a new Person as a copy target (targets are existing people only).
- A live link between source and copies — edits to the source after copying do not propagate.
- Copying from a master item with no owner or with an empty name (the action is not offered for these degenerate states).

## Requirements

### 1. Initiate a copy from a master packing item

**User Story:** As a trip organiser, I want to start copying a master packing item to other people, so that I don't have to re-create shared items one person at a time.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL offer a "Copy to people…" action on each eligible master packing item row, exposed through the same per-row affordances the packing sheet's item rows use for Edit (a trailing swipe action and a long-press context menu); the existing whole-row tap SHALL continue to open the item editor.  
2. <a name="1.2"></a>WHEN the user activates the copy action on a master packing item, the system SHALL present a target-person picker scoped to that single source item.  
3. <a name="1.3"></a>The system SHALL NOT offer the copy action when fewer than two people exist, when the source item has no owner, or when the source item's name is empty after trimming surrounding whitespace.  

### 2. Select target people

**User Story:** As a trip organiser, I want to pick several people to copy an item to at once, so that one action covers everyone who needs it.

**Acceptance Criteria:**

1. <a name="2.1"></a>The target-person picker SHALL list every Person except the source item's owner, sorted by name ascending (matching the existing master-list person ordering).  
2. <a name="2.2"></a>The picker SHALL allow selecting more than one target person in a single copy action.  
3. <a name="2.3"></a>WHERE a listed person already owns a master packing item whose name equals the source item's name (compared case-insensitively after trimming surrounding whitespace), the system SHALL mark that person as ineligible and SHALL NOT allow them to be selected.  
4. <a name="2.4"></a>The system SHALL keep the confirm/copy control disabled until at least one eligible target person is selected.  
5. <a name="2.5"></a>IF no listed person is eligible (every other person already owns a same-name item), THEN the picker SHALL show a state that conveys no one else needs the item and SHALL keep the confirm/copy control disabled.  
6. <a name="2.6"></a>The system SHALL let the user dismiss the picker without copying, leaving all master packing items unchanged.  

### 3. Perform the copy

**User Story:** As a trip organiser, I want each selected person to get a complete, independent copy of the item, so that the copied item behaves exactly like one I authored for them directly.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHEN the user confirms the copy, the system SHALL create one new master packing item per selected eligible target person, owned by that person, in the same store that holds the existing master packing items.  
2. <a name="3.2"></a>Each created item SHALL have the same name as the source item (after trimming surrounding whitespace).  
3. <a name="3.3"></a>Each created item's conditions SHALL be deeply value-equal to the source item's conditions — including every associated value and the advanced (non-simple) form — such that they decode to an equal `ItemConditions` value.  
4. <a name="3.4"></a>Each created item SHALL be a distinct record; subsequent edits to it, to the source item, or to any sibling copy SHALL NOT affect the others, and creating the copies SHALL NOT modify the source item.  
5. <a name="3.5"></a>IF a selected target became a same-name owner between picker presentation and confirmation, THEN the system SHALL skip that target rather than create a duplicate.  
6. <a name="3.6"></a>Master-item creation SHALL be atomic: IF persisting the new items fails, THEN the system SHALL create none of them (no partial copy) and SHALL surface a failure indication using the master editor's existing save-failure toast pattern.  
7. <a name="3.7"></a>IF every selected target is skipped at confirmation (3.5) so that zero items would be created, THEN the system SHALL treat the action as a no-op success: make no master changes, skip the trip recompute, and report (per 5.2) that all selected people were skipped.  

### 4. Materialise copies onto trips

**User Story:** As a trip organiser, I want copied items to show up on the relevant trips automatically, so that I don't have to open each trip to add them.

**Acceptance Criteria:**

1. <a name="4.1"></a>WHEN one or more copies are persisted successfully, the system SHALL trigger the same non-past-trip rules recompute the master editor runs after a save, so that each new item appears on every trip whose attributes satisfy that item's conditions for its owner.  
2. <a name="4.2"></a>Trip materialisation SHALL be best-effort: IF the post-copy recompute fails, THEN the system SHALL keep the persisted master items and SHALL surface the same deferred-update indication the master editor already shows when a recompute fails after a successful save.  
3. <a name="4.3"></a>The trip-level items produced by the recompute SHALL propagate to participants of shared trips through the same sync path as other trip-item changes.  

### 5. Confirm the result

**User Story:** As a trip organiser, I want to know which people received the item, so that I can tell whether anyone was skipped.

**Acceptance Criteria:**

1. <a name="5.1"></a>WHEN a copy action creates at least one item, the system SHALL show a transient confirmation on the Master Lists packing list — after the picker is dismissed — that names the people the item was copied to.  
2. <a name="5.2"></a>IF one or more selected people were skipped at confirmation (3.5) because they already owned a same-name item, THEN the confirmation SHALL indicate that those people were skipped.  
