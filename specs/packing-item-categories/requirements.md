# Requirements: Packing Item Categories

## Introduction

Packing items in Scramble currently appear in the packing sheet sorted alphabetically within each pack/repack state section, which forces the user to hunt for related items (for example, clothes) scattered across the list. This feature adds an optional, free-text category to packing items so that both the Packing Sheet and Master Lists group related items together, with previously-used category names offered as suggestions to keep categories consistent.

A category is a **managed projection**, not a live read-time binding: each item physically stores its category so it can be displayed and synced (a shared-trip participant cannot see the owner's master lists). For trip items derived from a master, the owner's device re-applies the master's current category to existing trip items so they converge on it over time; manual one-off items keep their own independently-set category.

This work tracks Transit ticket T-1605.

## Terminology and data model

- **Category**: an optional, free-text label on a packing item. Stored on `MasterPackingItem` (the source value) and on `TripPackingItem` (the value shown and synced on a trip).
- **Normalized category key**: the value used to decide whether two categories are the *same* for grouping, suggestions, and sorting — derived by trimming, collapsing internal whitespace, and case-folding. Two categories with the same normalized key are one category.
- **Master-derived trip item**: a `TripPackingItem` with a master (`masterItemID != nil`); its category is an owner-written projection of the master's category and is read-only for shared-trip participants.
- **Manual one-off trip item**: a `TripPackingItem` with no master; its category is set directly on the item and is never re-applied from a master.
- **Reconciliation**: the owner-device step that re-applies a master's current category onto its derived trip items. It runs as part of the rules-engine pass (which otherwise only adds items and flags match state); category is the one projection field the engine may rewrite on existing items.

## Non-Goals

- No managed category list or category entity — categories are free-text strings stored on items. A category exists only while at least one accessible item uses it; clearing the last item using a category removes it from suggestions. There is no persistent category vocabulary.
- No bulk rename or merge tool for consolidating category variants; the suggestion list is the consistency mechanism.
- No category support for tasks — this feature covers packing items only.
- No manual reordering of categories.
- No per-trip override of a master-derived item's category — it is owner-controlled and reflects the master.
- No change to how the rules engine matches items — category is metadata, not a matching condition.

## Requirements

### 1. Category field on packing items

**User Story:** As someone maintaining packing lists, I want to assign a category to a packing item, so that related items can be grouped together.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL allow an optional, free-text category to be set on a packing item.  
2. <a name="1.2"></a>WHEN a category value is empty or whitespace-only THEN the system SHALL store no category and treat the item as uncategorised.  
3. <a name="1.3"></a>The system SHALL trim leading and trailing whitespace and collapse internal runs of whitespace to a single space before storing a category.  
4. <a name="1.4"></a>The system SHALL display packing items that have no category as uncategorised, including items created before this feature existed.  
5. <a name="1.5"></a>The system SHALL treat two categories whose normalized category keys are equal as the same category for grouping, suggestions, and sorting.  

### 2. Setting a category with suggestions in Master Lists

**User Story:** As someone maintaining packing lists, I want to pick from previously-used category names when categorising an item, so that I don't create duplicate variants of the same category.

**Acceptance Criteria:**

1. <a name="2.1"></a>WHEN editing a packing item in Master Lists THEN the system SHALL provide a control to set or clear its category.  
2. <a name="2.2"></a>WHEN the user is entering a category THEN the system SHALL offer, as selectable suggestions, the distinct categories present in the packing data available on the device (the user's master items and the trip items visible to them).  
3. <a name="2.3"></a>The system SHALL match existing categories for suggestion purposes by normalized category key, so that values differing only in case or whitespace are presented as a single suggestion.  
4. <a name="2.4"></a>WHEN the user selects a suggested category THEN the system SHALL store that suggestion's existing spelling rather than creating a new variant.  
5. <a name="2.5"></a>WHERE a device has no access to the master lists (a shared-trip participant), the system SHALL draw suggestions from the trip items visible on that device.  

### 3. Category reflects the current master definition

**User Story:** As someone planning trips, I want category changes I make in Master Lists to appear on trips I have already planned, so that categorising an item once organises every trip.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHEN a packing item is added to a trip from a master item THEN the system SHALL set the trip item's category to that master item's current category.  
2. <a name="3.2"></a>WHEN a master packing item's category changes THEN the owner's device SHALL re-apply the new category to existing trip items derived from that master on active (non-past) trips, converging on the master's value (eventually-consistent, applied on the next rules-engine run).  
3. <a name="3.3"></a>WHEN re-applying a category onto existing trip items THEN the system SHALL NOT alter any other field of those items (including the snapshotted name).  
4. <a name="3.4"></a>Reconciliation SHALL write a trip item's category only when it differs from the master's current category, performing no write when the value is already equal.  
5. <a name="3.5"></a>WHERE a trip is shared, the system SHALL present a master-derived item's category as read-only to participants and SHALL NOT offer them a control to edit it.  
6. <a name="3.6"></a>WHEN a master packing item is deleted THEN the system SHALL leave the last-applied category on its existing derived trip items unchanged (the category is not cleared).  
7. <a name="3.7"></a>WHERE the owner uses more than one device, reconciliation SHALL converge derived trip items on the most recent master category. Transient older values are permitted while the master and trip-item sync pipelines are still converging and SHALL self-heal once the master has synced.  

### 4. Category on manual trip items

**User Story:** As someone packing for a trip, I want to categorise one-off items I add directly to a trip, so that they group alongside everything else.

**Acceptance Criteria:**

1. <a name="4.1"></a>WHEN adding or editing a one-off packing item on a trip (an item with no master) THEN the system SHALL allow setting or clearing its category, offering the same suggestions as Master Lists.  
2. <a name="4.2"></a>The system SHALL group manual one-off items by category in the Packing Sheet using the same rules as master-derived items.  
3. <a name="4.3"></a>Reconciliation SHALL NOT change the category of manual one-off items.  

### 5. Grouped display in the Packing Sheet

**User Story:** As someone packing, I want the Packing Sheet to group items by category, so that I don't have to hunt for related items across the list.

**Acceptance Criteria:**

1. <a name="5.1"></a>WHERE items are shown within a packing state section, the system SHALL group them by normalized category under category sub-headers.  
2. <a name="5.2"></a>The system SHALL order category sub-headers by a locale-independent collation so that the same trip renders the same order on every device, placing the uncategorised section last.  
3. <a name="5.3"></a>WITHIN a category the system SHALL retain the existing item ordering (active items before dimmed items, then case-insensitive name).  
4. <a name="5.4"></a>The system SHALL apply category grouping in both pack and repack modes, including the read-only repack sections.  
5. <a name="5.5"></a>WHEN no item in a section has a category THEN the system SHALL render that section as a flat list with no category sub-headers (including no uncategorised header).  
6. <a name="5.6"></a>WHERE category spelling variants with the same normalized key coexist, the system SHALL display a deterministic header label (the variant that sorts first under the pinned collation).  
7. <a name="5.7"></a>The system SHALL compute a Packing Sheet body once per render without re-scanning the person's item set per row.  
8. <a name="5.8"></a>The system SHALL expose category sub-headers to VoiceOver as headers and support Dynamic Type, consistent with existing section headers.  

### 6. Grouped display in Master Lists

**User Story:** As someone maintaining packing lists, I want Master Lists to group items by category within each person, so that the list mirrors how I will pack.

**Acceptance Criteria:**

1. <a name="6.1"></a>WHERE packing items are listed for a person in Master Lists, the system SHALL group them by normalized category under category sub-headers within that person.  
2. <a name="6.2"></a>The system SHALL order categories consistently with the Packing Sheet (same collation, uncategorised last) and SHALL render a person's items as a flat list when none of them is categorised.  

### 7. Category synchronisation

**User Story:** As someone using Scramble across my devices and sharing trips with family, I want categories to sync, so that grouping is consistent everywhere.

**Acceptance Criteria:**

1. <a name="7.1"></a>The system SHALL synchronise a packing item's category across the user's devices.  
2. <a name="7.2"></a>The system SHALL synchronise a trip packing item's category to the participants of a shared trip.  
3. <a name="7.3"></a>WHEN a synced record omits the category (for example, from an older app version) THEN the system SHALL treat the item as uncategorised without error.  
