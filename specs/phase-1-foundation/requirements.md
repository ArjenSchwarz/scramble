# Requirements: Phase 1 Foundation

## Introduction

Phase 1 establishes the foundation that every later phase of Scramble depends on: the SwiftData model, the theme system, the app shell, and trip CRUD. After Phase 1, a user can launch the app, create and edit trips with attributes and people, and navigate between the Trip List and an empty Trip Detail timeline — but no phase content, packing UI, rules engine, or sharing UI exists yet. Getting the data model and CloudKit-aware schema right here avoids migrations later when the rules engine, packing, and CKShare are added.

## Non-Goals

- The full `PhaseNode` component from the UI design doc (glow ring, "NOW" pill, packing-phase glyph). Phase 1 ships only the minimal past/current/future distinction required by [6.4](#6.4).
- Accordion expansion, task rows, packing summary blocks, packing sheet (pack and repack), `WhyDisclosure`, or any per-phase content rendering.
- Rules engine evaluation, master-list item editing UI, or seeded master-list content.
- CloudKit `CKShare` invitation flow, share-acceptance UI, or per-trip participant management.
- Per-trip CloudKit custom zones (deferred to the CKShare phase — see `decision_log.md` Decision 9).
- Phase-activation notifications and notification deep-links.
- Haptics beyond what SwiftUI applies by default; explicit VoiceOver custom rotor actions; Dynamic Type pass beyond what stock components provide.
- macOS app target.
- App Group container; widgets and extensions are not part of v1.
- Multi-leg trip support, copy-previous-trip, accommodation/activity attributes, user-configurable phases.
- Country flag emoji on the trip header (deferred until the timeline phase ships).
- In-app theme picker or appearance override (system appearance drives variant selection in v1).

## Requirements

### 1. SwiftData Persistence Model

**User Story:** As a Scramble user, I want my trips, people, and master items to persist across launches and sync across my devices, so that I can plan a trip from any device and not lose data.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL persist `Trip`, `Person`, `MasterTaskItem`, `MasterPackingItem`, `TripTask`, and `TripPackingItem` entities using SwiftData.  
2. <a name="1.2"></a>Each persisted entity SHALL satisfy CloudKit constraints: every property has a default value or is optional, and no `@Attribute(.unique)` constraints are declared.  
3. <a name="1.3"></a>Each persisted entity SHALL expose an `id: UUID` that is assigned at construction (client-side), is never reassigned, and is the stable identifier used by every cross-entity reference.  
4. <a name="1.4"></a>The schema SHALL declare explicit inverse relationships, both directions, for: `Trip ↔ Person` (many-to-many; `Trip.participants` and `Person.trips`), `Trip ↔ TripTask` (one-to-many; `Trip.tasks` and `TripTask.trip`), `Trip ↔ TripPackingItem` (one-to-many; `Trip.packingItems` and `TripPackingItem.trip`), `Person ↔ TripPackingItem` (one-to-many; `Person.tripPackingItems` and `TripPackingItem.person`), and `Person ↔ MasterPackingItem` (one-to-many; `Person.masterPackingItems` and `MasterPackingItem.person`).  
5. <a name="1.5"></a>The schema SHALL declare delete rules: cascade from `Trip` to `TripTask`, cascade from `Trip` to `TripPackingItem`, deny from `Person` to `TripPackingItem` (model-level guard matching the UI-level guard in [9.7](#9.7)), and deny from `Person` to `MasterPackingItem`. Deleting a `MasterPackingItem` or `MasterTaskItem` SHALL NOT cascade — trip-level items keep their snapshot `name` per [1.9](#1.9).  
6. <a name="1.6"></a>`Trip.attributes` SHALL be stored as a Codable blob whose schema can express adding new attribute categories without a SwiftData migration. Filtering trips by attribute is expected to happen in memory after fetch (SwiftData predicates cannot index into the blob).  
7. <a name="1.7"></a>`MasterTaskItem.conditions` and `MasterPackingItem.conditions` SHALL be stored as a Codable blob whose schema can express AND/OR groupings without a SwiftData migration. Rule-engine evaluation in a later phase is expected to fetch then filter in memory.  
8. <a name="1.8"></a>`TripTask` and `TripPackingItem` SHALL each store an optional `masterItemID: UUID` (a stable reference, not a SwiftData relationship) and a `name: String` snapshot copied from the master item at creation, plus `source` (`.rule` or `.manual`), `currentlyMatchesRules: Bool` (default `true` when `source == .manual`), and `pinnedByUser: Bool`.  
9. <a name="1.9"></a>A `masterItemID` reference whose target master item has been deleted SHALL be acceptable; the trip-level item retains its snapshot `name` and continues to function. The "why is this here?" surface (later phase) SHALL handle the missing master gracefully.  
10. <a name="1.10"></a>The model SHALL expose Codable enums with the following exact cases: `Phase` = `weeksBefore | dayBefore | departureDay | duringTrip | dayBeforeReturn | returnDay | afterTrip`; `ItemSource` = `rule | manual`; `PackingState` = `unpacked | packed | repacked | excluded`.  
11. <a name="1.11"></a>The model SHALL expose `TripAttribute` covering Duration, Transport, Scope, Weather, and Purpose. The Codable storage shape mandated by [1.6](#1.6) SHALL hold each attribute as an array of values so any attribute can become multi-select later without a schema change. The trip editor in v1 SHALL enforce single-select for Duration / Transport / Scope / Purpose and multi-select for Weather as an editor-level rule, not a schema-level rule.  
12. <a name="1.12"></a>The schema SHALL be wrapped in a `VersionedSchema` and a `SchemaMigrationPlan` from day one (the v1 plan declares a single version with no migration steps), so future schema changes can register migration stages without restructuring.  
13. <a name="1.13"></a>The model SHALL NOT make multi-leg trips structurally impossible (a single `Trip` having a date range and an attribute set is acceptable; nothing in the schema may forbid future per-leg attribute sets).

### 2. CloudKit-Backed Container with Test-Safe Initialization

**User Story:** As a developer working on Scramble, I want the model container to use CloudKit in production but never block tests or previews, so that the app syncs across my devices without breaking the test suite or making previews dependent on entitlements.

**Acceptance Criteria:**

1. <a name="2.1"></a>The production `ModelContainer` SHALL be configured with `cloudKitDatabase: .private("iCloud.me.nore.ig.scramble")`. All Phase 1 entities use the default SwiftData CloudKit zone (per-trip custom zones are deferred to the `CKShare` phase — see `decision_log.md` Decision 9).  
2. <a name="2.2"></a>WHEN the app is running under unit tests, UI tests, or SwiftUI Previews, the system SHALL use an in-memory `ModelContainer` with `cloudKitDatabase: .none`. The mechanism for detecting these contexts is a design decision, but the contract is observable: no CloudKit mirroring is attempted in any of these contexts.  
3. <a name="2.3"></a>WHEN production container construction fails (missing entitlements, sandbox blocking, or other I/O error), the system SHALL silently fall back to a local-only `ModelContainer` (no CloudKit) at the default location and log the failure. The app SHALL NOT terminate before the first frame and SHALL NOT block the UI on an error screen.  
4. <a name="2.4"></a>The model container SHALL be exposed as a single shared instance accessible to the SwiftUI view tree via the standard `.modelContainer(_:)` modifier.

### 3. Theme System

**User Story:** As a Scramble user, I want the app's appearance to feel cohesive and to follow my system light/dark setting, so that it looks correct in any context without my having to configure it.

**Acceptance Criteria:**

1. <a name="3.1"></a>The system SHALL define a `Theme` value type whose properties cover every color key listed in `docs/scramble-ui-design-doc.md` (background gradient, accent, surface, surfaceBorder, textPrimary, textSecondary, checkColour, warnColour, phaseColours, person palette).  
2. <a name="3.2"></a>The system SHALL provide a Midnight Atlas theme with both dark and light variants whose color values match the table in the UI design doc.  
3. <a name="3.3"></a>The active theme variant SHALL be selected from the SwiftUI `colorScheme` environment value; no in-app appearance override exists in v1.  
4. <a name="3.4"></a>The active `Theme` SHALL be injected via the SwiftUI environment so any view can read it via an `@Environment` property.  
5. <a name="3.5"></a>The person color palette SHALL contain the eight colors listed in the UI design doc (Cyan, Pink, Yellow, Green, Purple, Orange, Red, Teal), each with dark and light hex values.  
6. <a name="3.6"></a>Adding a second theme later SHALL require no changes to call sites that read theme colors — only adding a new `Theme` instance and a selection mechanism.

### 4. App Shell and Tab Bar

**User Story:** As a Scramble user, I want a stable navigational frame (Trips and Master Lists) at the root, so that I always know where I am in the app.

**Acceptance Criteria:**

1. <a name="4.1"></a>The root scene SHALL present a two-item bottom tab bar with "Trips" and "Master Lists" tabs.  
2. <a name="4.2"></a>The bottom tab bar SHALL render with the system Liquid Glass treatment and float detached from the bottom edge.  
3. <a name="4.3"></a>The bottom tab bar SHALL be visible at the root of either tab and SHALL be hidden when the user has navigated into a Trip Detail screen.  
4. <a name="4.4"></a>Tab selection state SHALL persist for the duration of the app session but is not required to persist across launches.  
5. <a name="4.5"></a>The default selected tab on first launch SHALL be "Trips".

### 5. Trip List

**User Story:** As a Scramble user, I want to see my trips grouped by active vs previous and create new ones, so that I can manage planning across multiple trips at once.

**Acceptance Criteria:**

1. <a name="5.1"></a>The Trip List SHALL display a section "Active" containing trips whose end date is today or in the future (compared at calendar-day granularity), ordered by start date ascending.  
2. <a name="5.2"></a>The Trip List SHALL display a section "Previous" containing trips whose end date is before today, collapsed by default, ordered by end date descending.  
3. <a name="5.3"></a>The Trip List SHALL display a "+ New Trip" affordance, styled as a dashed-border button below the Active section, that opens the trip editor in create mode.  
4. <a name="5.4"></a>Each trip row SHALL show the trip name, date range, and a relative-day status string derived from today and the trip's start/end dates. The exact copy is a design-phase concern; the requirement is that the status communicates whether the trip is upcoming (and how far away), in progress (and how far in), returning soon, or completed (and how long ago).  
5. <a name="5.5"></a>Tapping a trip row SHALL push the Trip Detail screen for that trip onto the Trips tab navigation stack.  
6. <a name="5.6"></a>WHEN the app cold-launches AND exactly one trip qualifies as "active or starting within 2 days" (start date ≤ today + 2 days AND end date ≥ today, calendar-day granularity), the app SHALL open directly to that trip's Trip Detail screen with the Trip List as the back destination. Zero qualifying trips OR two-or-more qualifying trips SHALL show the Trip List as the entry screen. "Cold launch" means the app process was newly created for this scene activation (i.e., `application(_:didFinishLaunchingWithOptions:)` ran and the first scene was newly attached); resuming a suspended process does not qualify.  
7. <a name="5.7"></a>The auto-open path SHALL fire at most once per cold launch. WHEN the user taps back from an auto-opened Trip Detail, the Trip List SHALL be presented and SHALL NOT re-trigger auto-open until the next cold launch. Background-resume SHALL NOT re-trigger auto-open.

### 6. Trip Detail Scaffold

**User Story:** As a Scramble user, I want to see a trip's name, dates, and attributes at a glance with the timeline frame in place, so that the structure is recognisable from day one even before phase content lands.

**Acceptance Criteria:**

1. <a name="6.1"></a>The Trip Detail screen SHALL display a sticky header with the trip name, date range, and a status line per [5.4](#5.4).  
2. <a name="6.2"></a>The Trip Detail header SHALL display an attribute chip row showing every selected attribute value; tapping a chip opens the trip editor scrolled to that attribute.  
3. <a name="6.3"></a>The Trip Detail body SHALL render a vertical 2pt spine with seven phase markers (in the order Weeks before, Day before, Departure day, During trip, Day before return, Return day, After trip), labelled, but with no expandable content.  
4. <a name="6.4"></a>Phase markers SHALL render distinct visual states for past, current, and future phases based on today's date relative to the trip's date range. Phase 1 SHALL ship the minimum visual treatment that makes the three states distinguishable to a sighted user (e.g., filled vs outlined node). The full glow-ring and accordion treatment from the UI design doc is deferred to a later phase.  
5. <a name="6.5"></a>The Trip Detail screen SHALL provide an "Edit" affordance that opens the trip editor in edit mode for the current trip.  
6. <a name="6.6"></a>The Trip Detail screen SHALL provide a "Delete" affordance that, after a confirmation dialog, removes the trip and returns the user to the Trip List.

### 7. Master Lists Scaffold

**User Story:** As a Scramble user, I want the Master Lists tab to exist as a navigable destination, so that the navigation structure is complete even before list editing ships.

**Acceptance Criteria:**

1. <a name="7.1"></a>The Master Lists screen SHALL present a segmented control with "Packing Items" and "Tasks" segments.  
2. <a name="7.2"></a>Each segment SHALL render an empty-state placeholder explaining that master-list editing arrives in a later phase.  
3. <a name="7.3"></a>The Master Lists screen SHALL NOT expose any item creation, editing, or deletion affordances in Phase 1.

### 8. Trip Editor (Create and Edit)

**User Story:** As a Scramble user, I want one screen to create or edit a trip with all of its attributes and people, so that I can capture everything the rules engine will eventually need.

**Acceptance Criteria:**

1. <a name="8.1"></a>The trip editor SHALL accept a name (non-empty), a start date, and an end date (where end ≥ start).  
2. <a name="8.2"></a>The trip editor SHALL allow the user to select one value for Duration, Transport, Scope, and Purpose, and one or more values for Weather.  
3. <a name="8.3"></a>The trip editor SHALL allow the user to add existing people to the trip and remove people from the trip.  
4. <a name="8.4"></a>The trip editor SHALL allow the user to create a new person inline (name + color picker) and that new person SHALL be added to the trip and to the global people store.  
5. <a name="8.5"></a>The trip editor SHALL persist all changes via the shared `ModelContainer` when the user confirms; cancelling SHALL discard pending edits.  
6. <a name="8.6"></a>The trip editor SHALL block confirmation and surface inline validation messages when the name is empty or the date range is invalid.

### 9. People Management

**User Story:** As a Scramble user, I want people to exist as entities that survive across trips with stable colors, so that family members keep their identity from one trip to the next.

**Acceptance Criteria:**

1. <a name="9.1"></a>`Person` entities SHALL be stored globally (not nested per trip) and SHALL carry `name: String` and `colorKey: String` referencing one entry of the active theme's person palette as defined in [3.5](#3.5).  
2. <a name="9.2"></a>The system SHALL ship with no seeded `Person` entities; first-launch state is empty and the user creates people via the trip editor's inline create affordance.  
3. <a name="9.3"></a>WHEN a `Person` is created, the system SHALL assign the next unused palette color as the default; the user MAY override during creation.  
4. <a name="9.4"></a>WHEN the user picks a `colorKey` already in use by another `Person`, the editor SHALL display non-blocking advisory text inline near the colour picker that names the conflicting person, and SHALL still allow the choice. (Exact copy is a design-phase concern.)  
5. <a name="9.5"></a>Two `Person` records with the same `name` SHALL be permitted; uniqueness is not enforced at the model level (CloudKit constraints prohibit `@Attribute(.unique)`). The trip editor's "add existing person" picker SHALL distinguish duplicates by showing the colour swatch alongside the name.  
6. <a name="9.6"></a>The `Person` entity SHALL expose a derived `initial` (first grapheme of `name`, uppercased) used by the avatar component.  
7. <a name="9.7"></a>Deleting a `Person` SHALL be blocked when any locally-known `TripPackingItem` references that person; the UI SHALL surface this constraint with the names of the referencing trips. Cross-device eventual consistency means a delete may succeed locally while another device is holding an unsynced reference; the offline-created `TripPackingItem` SHALL retain its snapshot data and the dangling person reference SHALL be tolerated (consistent with [1.9](#1.9)).

### 10. Avatar and Theming Primitives

**User Story:** As a Scramble user, I want every place a person appears to use the same coloured-initial avatar, so that I can recognise people instantly across the app.

**Acceptance Criteria:**

1. <a name="10.1"></a>The system SHALL provide a reusable `PersonAvatar` view that renders a circle filled at ~16% opacity of the person's color, with the person's initial centred in the person's color at full opacity (weight 800).  
2. <a name="10.2"></a>`PersonAvatar` SHALL accept a size parameter and SHALL render at 14pt, 26pt, and 36pt presets without distortion.  
3. <a name="10.3"></a>Trip List rows, the Trip Detail header (when displaying participants), and the trip editor's people list SHALL use `PersonAvatar` at the appropriate preset size.

## Open Questions

None — see `decision_log.md` for resolved decisions.
