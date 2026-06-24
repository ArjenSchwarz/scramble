# Requirements: Packing Item Sub-items

## Introduction

Scramble's packing items are single named entries (e.g. "toys", "books") whose only tracked state is packed / unpacked. For generic items, a packer often needs to record exactly which specific things to bring without tracking each one's status. This feature adds an optional per-trip free-form note plus an appendable list of sub-items to each packing item, shown inline on the packing sheet and editable while packing. The note and sub-items are trip-specific, never touched by the rules engine, and sync to everyone sharing the trip.

## Non-Goals

- Tracking packed / unpacked (or any) status per sub-item — sub-items are reference text only.
- Promoting a note or sub-items onto the master packing list — they stay on the trip item.
- Letting notes or sub-items influence rule matching, group membership, or the packing progress counters.
- Reordering sub-items, or nesting sub-items inside sub-items.
- Adding notes or sub-items to trip tasks (`TripTask`) — packing items only.
- Per-sub-item assignee, due date, or "why is this here?" explainability.
- Surfacing notes / sub-items on the timeline packing-summary block — they live on the packing sheet only.
- Merging concurrent sub-item edits from multiple devices — the list resolves last-writer-wins per field (see [6.3](#6.3)); no CRDT / per-entry merge.
- Reconciling a remote sync arriving mid-edit against unsaved local text — handled as a design concern, not a guaranteed-merge behaviour.

## Requirements

### 1. Per-trip note and sub-items on a packing item

**User Story:** As a trip packer, I want to attach a free-form note and a list of sub-items to a packing item, so that I can record exactly which specific things to bring for a generic item.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL allow each packing item to carry an optional free-form note and an ordered list of sub-item entries, scoped to the trip on which they are entered.  
2. <a name="1.2"></a>A note or sub-item entered on one trip's packing item SHALL NOT appear on any other trip's items, nor on the master packing list.  
3. <a name="1.3"></a>The system SHALL display sub-items in the order they were added on the device where they are entered.  
4. <a name="1.4"></a>WHEN a packing item has neither a note nor any sub-items, the system SHALL treat both as empty and require no content.  

### 2. Adding sub-items while packing

**User Story:** As a packer, I want to quickly append a sub-item to a packing item while packing, so that I can note what to bring as I think of it.

**Acceptance Criteria:**

1. <a name="2.1"></a>WHERE a packing item row is interactive (an active pack or repack group), the system SHALL present an affordance to add a new sub-item to that item.  
2. <a name="2.2"></a>WHEN the user submits a non-empty sub-item, the system SHALL append it to that item's sub-item list and display it on the row.  
3. <a name="2.3"></a>IF the submitted sub-item text is empty or whitespace-only, THEN the system SHALL NOT add an entry.  
4. <a name="2.4"></a>The system SHALL limit a single sub-item entry to a maximum of 200 grapheme clusters, matching the existing item-name limit.  
5. <a name="2.5"></a>Adding a sub-item SHALL NOT change the packing item's packed / unpacked state or its group membership.  
6. <a name="2.6"></a>The system SHALL allow duplicate sub-item text and SHALL NOT silently de-duplicate entries.  
7. <a name="2.7"></a>WHEN a packing item already holds 50 sub-items, the system SHALL prevent adding another and indicate the limit at the point of entry, rather than allowing a later sync-time failure.  

### 3. Removing sub-items

**User Story:** As a packer, I want to remove a sub-item I added by mistake, so that the list stays accurate.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHERE a packing item row is interactive, the system SHALL provide a way to remove an individual sub-item.  
2. <a name="3.2"></a>WHEN the user removes a sub-item, the system SHALL delete only that entry and keep the remaining sub-items in their existing order.  
3. <a name="3.3"></a>Removing a sub-item SHALL NOT change the packing item's packed / unpacked state.  

### 4. Free-form note

**User Story:** As a packer, I want a free-form note on a packing item, so that I can capture detail that isn't a discrete sub-item (e.g. "keep batteries out").

**Acceptance Criteria:**

1. <a name="4.1"></a>WHERE a packing item row is interactive, the system SHALL allow the user to set or edit the item's note.  
2. <a name="4.2"></a>WHEN the user saves note text, the system SHALL persist it and display it on the row, visually distinct from the sub-item list.  
3. <a name="4.3"></a>IF the note is cleared to empty or whitespace-only, THEN the system SHALL store no note and display none.  
4. <a name="4.4"></a>The system SHALL limit the note to a maximum of 500 grapheme clusters.  

### 5. Display across modes and groups

**User Story:** As a packer, I want to see an item's note and sub-items wherever the item appears, so that the information is available when repacking or reviewing.

**Acceptance Criteria:**

1. <a name="5.1"></a>The system SHALL display an item's existing note and sub-items inline on the item's row in both pack and repack modes.  
2. <a name="5.2"></a>WHERE a row is in a read-only group (Not bringing, Left behind), the system SHALL display existing note and sub-items but SHALL NOT present add or remove affordances.  
3. <a name="5.3"></a>WHEN an item has neither a note nor sub-items, the system SHALL keep the row's current layout and provide a reachable affordance to add the first sub-item on interactive rows.  
4. <a name="5.4"></a>WHEN a packing item is dimmed (unmatched and not pinned), the system SHALL still display and allow editing of its note and sub-items where the row is interactive.  

### 6. Persistence and sync

**User Story:** As someone sharing a trip, I want notes and sub-items to sync to everyone on the trip, so that we all see the same packing detail.

**Acceptance Criteria:**

1. <a name="6.1"></a>The system SHALL persist an item's note and sub-items across app launches.  
2. <a name="6.2"></a>The system SHALL include the note and sub-items when synchronising the packing item to other devices on a shared trip, such that the winning record's note and sub-items survive a save → load → sync round-trip without loss or reordering.  
3. <a name="6.3"></a>WHEN edits to the same packing item's note or sub-item list arrive concurrently from different devices, the system SHALL resolve them last-writer-wins at the field level; one side's concurrent addition to the sub-item list MAY be dropped as a result.  
4. <a name="6.4"></a>Before saving, the system SHALL reject input that exceeds the per-entry length limits or the sub-item count limit, surfacing the rejection inline at the point of entry rather than failing later at sync time.  
5. <a name="6.5"></a>WHEN a note or sub-item list is cleared on one device, the system SHALL propagate the cleared (empty) value to the other devices on the trip rather than leaving a stale non-empty value.  

### 7. Independence from the rules engine and master list

**User Story:** As a user, I want my per-trip notes and sub-items to be unaffected by automatic list recomputation, so that I never lose them.

**Acceptance Criteria:**

1. <a name="7.1"></a>The deterministic rules recompute SHALL NOT add, remove, or modify any note or sub-item.  
2. <a name="7.2"></a>WHEN a packing item becomes unmatched, pinned, or re-matched, the system SHALL retain its note and sub-items unchanged.  
3. <a name="7.3"></a>A note or sub-item SHALL NOT affect rule matching, group membership, or the packing progress counters.  
4. <a name="7.4"></a>WHEN a packing item is deleted, the system SHALL remove its note and sub-items with it.  
5. <a name="7.5"></a>WHEN a packing item is skipped (moved to Not bringing) and later restored, the system SHALL retain its note and sub-items unchanged.  

### 8. Accessibility

**User Story:** As a VoiceOver user, I want to read and manage sub-items, so that the feature is usable without sight.

**Acceptance Criteria:**

1. <a name="8.1"></a>The system SHALL expose an item's note and sub-items to VoiceOver as readable content associated with the item's row.  
2. <a name="8.2"></a>WHERE a row is interactive, the system SHALL provide a VoiceOver custom action to add a sub-item, and SHALL make each existing sub-item individually addressable with its own remove action.  
3. <a name="8.3"></a>The add and remove sub-item controls SHALL each present a touch target of at least 44×44 points.  
