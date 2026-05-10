# Scramble — Design Document

## Overview

Scramble is a native iOS app (macOS planned for later) for trip planning and packing management. It replaces a fragmented workflow of templates in Drafts, task management in OmniFocus, and manual coordination — consolidating everything into a single shared app.

**Target:** Personal/family use. Shared via CloudKit (CKShare) with any iCloud user — no Family Sharing requirement. Typical use is within the family, but sharing a trip with friends or other travel companions works the same way.

**Platform:** iOS 26+, Swift 6.2, SwiftUI, SwiftData, CloudKit.

-----

## Core Concepts

### Trip

A trip is the top-level object. It has:

- **Name** (e.g., “Barcelona Summer 2026”)
- **Start date / End date**
- **Attributes** — used by the rules engine to auto-populate tasks and packing items:
  - Duration: short / long
  - Transport: car / plane / train
  - Scope: domestic / international
  - Weather: sun / rain / cold / hot *(multi-select)*
  - Purpose: work / leisure
- **People** — family members participating in the trip

Trips have two lifecycle states: **active** and **previous**. Previous trips are retained for history. A future improvement is the ability to copy a previous trip as a starting point.

### Phases

Tasks are organised into fixed phases derived from the trip’s start/end dates:

- Weeks before
- Day before
- Departure day
- During trip
- Day before return
- Return day
- After trip

Phases are not user-configurable in v1. The return packing list (repacking view) is always accessible but visually promoted when the “day before return” phase becomes active.

-----

## Features

### 1. Tasks

Tasks are actions tied to a trip and assigned to a phase. Examples: “Charge Kindle”, “Arrange pet sitter”, “Set out-of-office”.

- Shared — all participants can see and complete any task.
- Completion state: done / not done.
- **Reusable via rules engine** — a master task list with conditions, auto-populated per trip based on trip attributes (same mechanism as packing items).
- One-off tasks can be added directly to a trip without affecting the master list.

**Notifications:** The app sends notifications when a phase becomes active (e.g., “You have 5 outstanding tasks for ‘weeks before’”).

### 2. Packing Lists

Packing items are per-person but visible and editable by all participants (needed because kids can’t manage their own packing).

Each item has four states:

|State   |Meaning                                                                   |
|--------|--------------------------------------------------------------------------|
|Unpacked|Not yet packed                                                            |
|Packed  |In the suitcase                                                           |
|Repacked|Confirmed back in suitcase for return journey                             |
|Excluded|Deliberately not bringing — distinguishes “decided no” from “not done yet”|

The **return packing view** is always accessible but visually promoted when the trip reaches the “day before return” phase. It filters to packed items and allows marking them as repacked.

### 3. Rules Engine (Master Lists)

The core of reusability. Instead of maintaining multiple templates, there is a single master list for tasks and a single master list of packing items per person.

Each master item has **conditions** evaluated against trip attributes. When a trip is created (or trip attributes change), matching items are auto-populated.

**Condition logic (v1):** Keep it simple but build foundations for complexity.

- Conditions are evaluated per attribute type.
- Within the same attribute type: OR (e.g., weather = rain OR cold → rain jacket).
- Across different attribute types: AND (e.g., transport = plane AND scope = international → passport).

**Implementation note:** Store conditions in a flexible format (e.g., JSON blob or codable struct) rather than rigid typed fields. V1 logic evaluates simple AND/OR as described above, but the storage format should not prevent introducing grouped/nested conditions later (e.g., `(international AND cold) OR (domestic AND long)`) without a data migration.

**Example master packing items:**

|Item            |Conditions           |
|----------------|---------------------|
|Passport        |scope: international |
|Rain jacket     |weather: rain OR cold|
|Laptop + charger|purpose: work        |
|Car seat        |transport: car       |

**Re-evaluation (deterministic with diffing):** The rules engine re-evaluates whenever any relevant input changes: trip attributes modified, master list edited, app launch, or sync from another device. The process is:

1. Compute the set of items that *should* exist based on current trip attributes and master lists.
1. Compare with the set of items that *currently* exist on the trip.
1. **New matches:** add automatically.
1. **Items that no longer match:** flag with `currentlyMatchesRules = false`. These are visually dimmed but not deleted — the user may have deliberately kept them, or they may already be packed.
1. **Items pinned by user:** never removed or flagged, regardless of rule changes.
1. **Already completed/packed items:** never removed.

This deterministic approach ensures consistent behaviour across devices and avoids drift bugs where the trip state diverges from what the rules would produce.

**Editing scope:** Adjustments made within a trip (adding/removing items) are trip-specific only. They do not modify the master list. The master list is edited separately through its own interface.

**Explainability:** Every rule-driven item exposes which rule conditions caused it to appear on this trip. The UI surfaces this via a “?” affordance on each item (see UI design doc). Implementation: compute on demand by intersecting the master item’s conditions with the current trip’s attributes. No need to snapshot the matched conditions at creation/re-evaluation — the master item conditions are stable references, and the trip’s current attributes are the input.

### 4. Sharing

Implemented via CloudKit CKShare. One person owns the trip and shares it with others. All participants can:

- View and complete tasks
- View and check off packing items for any person (including kids)
- Modify trip attributes

Scope: Share per trip. Each trip is its own CKShare, allowing selective sharing (e.g., a friend joining a specific trip without accessing other trips).

-----

## Data Model (Conceptual)

```
MasterTaskItem
  - id: UUID
  - name: String
  - phase: Phase
  - conditions: Data             // flexible storage (JSON/Codable), v1 evaluates simple AND/OR

MasterPackingItem
  - id: UUID
  - name: String
  - person: Person
  - conditions: Data             // same flexible storage as above

Trip
  - name: String
  - startDate: Date
  - endDate: Date
  - attributes: [TripAttribute: [String]]
  - people: [Person]

TripTask
  - masterItemID: UUID?          // stable reference to master item (nil for one-offs)
  - name: String                 // snapshot — copied from master item at creation, not live-linked
  - phase: Phase
  - isCompleted: Bool
  - source: ItemSource           // .rule or .manual
  - currentlyMatchesRules: Bool  // false if rules no longer match (visually dimmed)
  - pinnedByUser: Bool           // true = user override, immune to re-evaluation changes

TripPackingItem
  - masterItemID: UUID?          // stable reference to master item (nil for one-offs)
  - name: String                 // snapshot
  - person: Person
  - state: PackingState          // unpacked, packed, repacked, excluded
  - source: ItemSource           // .rule or .manual
  - currentlyMatchesRules: Bool
  - pinnedByUser: Bool

Person
  - name: String

Phase (enum)
  - weeksBefore
  - dayBefore
  - departureDay
  - duringTrip
  - dayBeforeReturn
  - returnDay
  - afterTrip

ItemSource (enum)
  - rule                         // auto-populated by rules engine
  - manual                       // added directly to this trip

PackingState (enum)
  - unpacked
  - packed
  - repacked
  - excluded                     // deliberately not bringing
```

-----

## UI Structure (High Level)

### Trip List View

- **Active trips** at the top
- **Previous trips** below, collapsed by default
- **Auto-open:** If exactly one trip is active (started or starting within ~2 days), the app opens directly to that trip’s detail view instead of the list. Standard back navigation returns to the full list.

### Trip Detail View

- Trip name, dates, attributes (editable)
- Tabs or sections for **Tasks** and **Packing**

### Tasks View

- Grouped by phase
- Each task shows assignee (if applicable) and completion state
- Add one-off task inline

### Packing View

- Grouped by person
- Each item shows state (unpacked / packed / repacked / excluded)
- Items that no longer match rules are visually dimmed but still visible
- **Return packing view** always accessible, highlighted when relevant — filters to packed items, shows repacked checkbox

### Master List Management

- Separate section/screen for editing master task and packing lists
- Each item shows its conditions
- Simple editing interface for adding/removing/modifying conditions

-----

## Future Improvements (Out of Scope for v1)

- macOS app
- Copy/duplicate a previous trip
- Accommodation type attribute (hotel / camping / family)
- Activity-based attributes (beach, skiing, hiking)
- User-configurable phases
- Publishing to App Store (would require rethinking sharing model)
- Promote one-off trip tasks/packing items to the master list
- Link Person entries to iCloud users (so a person is both a packing list owner and a trip collaborator)
- Trip itinerary / activity planning — day-specific and general “during trip” activities, with the ability to create linked tasks from activities (e.g., “Go to Sea World” generates a task “Get tickets for Sea World”)
- Multi-leg / staged trips — separate legs with independent phases, repacking between legs, and leg-specific tasks. Significant data model implications; v1 model should avoid making this impossible but doesn’t need to support it