# Requirements: Phase 4 — Packing Sheet

## Introduction

Phase 4 makes the per-person packing surface usable inside Trip Detail. The Departure and Day-before-return phases gain a packing summary block that lists each participant with a progress bar and status, and tapping a person row opens a bottom sheet with grouped item lists. The sheet uses one component with two modes (pack on Departure, repack on Day-before-return), reuses `WhyDisclosure` from Phase 3 with a person-coloured variant, and resolves UI design doc open question 1 by fixing the `presentationDetents` configuration.

## Non-Goals

- Schema changes to `TripPackingItem` (existing fields already cover Phase 4 needs)
- Permanent deletion of packing items on a trip (skip → `excluded` is the only removal mechanism in v1; restore reverses it)
- Reordering items inside a group
- Switching active person from within the sheet (each open is bound to the person whose row was tapped)
- A "default assignee" or "default person" field on items (master items already carry `person`)
- Promoting a manual one-off packing item into the master list
- Filtering by state, search, or bulk actions
- Editing trip-level conditions for a packing item (conditions live on the master)
- CKShare merge semantics for `state`, `currentlyMatchesRules`, `pinnedByUser`, or new flags (Phase 5)
- Notifications related to packing readiness (Phase 6)
- An iPad / macOS layout for the sheet
- A separate Repack-only entry point outside the Day-before-return phase
- Showing trip-level packing items from compressed phases (packing phases never compress per Phase 3 Decision 2; this is non-applicable rather than unsupported)

## Cross-phase preliminaries

### Item state vocabulary (recap of `PackingState`)

`unpacked`, `packed`, `repacked`, `excluded`. The pack-mode sheet operates over `unpacked` / `packed` / `excluded`; the repack-mode sheet operates over `packed` / `repacked` / (`unpacked` ∪ `excluded` shown as "Left behind", read-only).

### Active vs dimmed items

Mirroring Phase 3 Req 4.4, an item is *dimmed* (unmatched-non-pinned) when `currentlyMatchesRules == false AND pinnedByUser == false`. Otherwise the item is *active*. Dimmed items remain interactive in pack mode; in repack mode their interactivity follows the mode's group rules (see Req [4](#4-repack-mode-groups-and-row-rules)).

Manual items (`source: .manual`) are created with `currentlyMatchesRules: true` (Req [5.3](#5.3)) and the rules engine never writes to `source == .manual` records (Req [10.1](#10.1)), so manual items are always active until the user explicitly toggles `pinnedByUser` (no Phase 4 affordance — see Decision 7).

### Phase-to-mode mapping

The pack mode is opened from a person row inside the `departureDay` phase. The repack mode is opened from a person row inside the `dayBeforeReturn` phase. No other phase exposes packing rows or the sheet.

## Requirements

### 1. Per-person packing summary block

**User Story:** As a trip planner, I want a row per participant on the Departure and Day-before-return phases showing how far along packing is, so that I can see at a glance who still has work to do.

**Acceptance Criteria:**

1. <a name="1.1"></a>WHEN the expanded phase is `departureDay` or `dayBeforeReturn`, the system SHALL render a "Packing" (Departure) or "Repack" (Day-before-return) section inside the phase content, with one row per `Person` in `trip.participants`, ordered by `Person.name` case-insensitive ascending with stable tiebreak on `Person.id`.  
2. <a name="1.2"></a>Each row SHALL display the person's 26pt avatar (per UI doc §"Avatars"), the person's name, a 3pt-high progress bar in person colour per UI doc §"Progress indicators", a status label, and a trailing chevron.  
3. <a name="1.3"></a>The pack-mode status label SHALL be: `"No items"` WHEN the person has zero items in `unpacked ∪ packed ∪ excluded`, `"—"` WHEN the person has items but all are in `excluded`, `"✓ ready"` WHEN at least one item exists in `unpacked ∪ packed` AND every `unpacked ∪ packed` item is in `packed`, and `"{N} to pack"` otherwise where `N` is the count of `unpacked` items.  
4. <a name="1.4"></a>The repack-mode status label SHALL be: `"No items"` WHEN the person has zero items in `unpacked ∪ packed ∪ repacked ∪ excluded`, `"—"` WHEN the person has items but `packed ∪ repacked` is empty, `"✓ all back in"` WHEN at least one item exists in `packed ∪ repacked` AND every such item is in `repacked`, and `"{N} to repack"` otherwise where `N` is the count of `packed` items.  
5. <a name="1.5"></a>The progress bar fill ratio SHALL be `packed / (unpacked + packed)` in pack mode and `repacked / (packed + repacked)` in repack mode. WHEN the denominator is zero, the bar SHALL render empty (0% fill) in person colour at the track opacity. The fill colour SHALL be the person colour at full opacity WHEN the ratio is in `[0.0, 1.0)` and the theme's `checkColour` WHEN the ratio equals exactly 1.0; un-toggling an item below 1.0 SHALL revert the fill colour back to the person colour on the next body evaluation (no hysteresis).  
6. <a name="1.6"></a>The denominator and numerator counts in Req [1.3](#1.3) – [1.5](#1.5) SHALL include both active and dimmed items (a dimmed item still counts toward the person's progress).  
7. <a name="1.7"></a>Tapping anywhere on a row SHALL open the packing sheet for that person in the mode determined by the phase, and SHALL produce the soft-impact "Sheet present" haptic per UI doc §"Haptics".  
8. <a name="1.8"></a>WHEN `trip.participants` is empty, the system SHALL render a single non-interactive row reading `"No participants yet — add people on the trip details screen"` styled in `textSecondary`. No add affordance for participants is provided from this surface.  
9. <a name="1.9"></a>Each row SHALL meet the 44pt × 44pt minimum touch target.  
10. <a name="1.10"></a>WHEN the expanded phase is `departureDay` or `dayBeforeReturn` AND the phase has at least one task with `currentlyMatchesRules == true OR pinnedByUser == true`, the phase header subline composed by Phase 3 Req 5.3 SHALL be appended with a packing clause `" · {S} to pack"` (Departure) or `" · {S} to repack"` (Day-before-return), where `S` is the sum of per-person pack-mode `N`-to-pack (Departure) or repack-mode `N`-to-repack (Day-before-return) values across `trip.participants`. WHEN `S == 0`, the packing clause SHALL read `" · packing ready"` (Departure) or `" · all back in"` (Day-before-return). WHEN the phase has zero tasks, the subline SHALL omit the Phase 3 tasks clause and SHALL begin with the packing clause without the leading `" · "`. The subline SHALL be allowed to wrap to a second line per Phase 3 Req 5.4; the packing clause MAY wrap independently of the tasks clause.  

### 2. Packing sheet shell and presentation

**User Story:** As a trip planner, I want the packing list to slide up as a sheet over the trip without losing my place in the timeline, so that I can return to where I was after packing.

**Acceptance Criteria:**

1. <a name="2.1"></a>The packing sheet SHALL be presented from the Trip Detail screen as a `presentationDetents` sheet with a single `.large` detent (resolves open question 1) and SHALL support swipe-down to dismiss in addition to the explicit close button.  
2. <a name="2.2"></a>The timeline view underneath SHALL NOT be unmounted while the sheet is presented; its scroll position and expanded-phase state SHALL be preserved on dismissal.  
3. <a name="2.3"></a>The sheet header SHALL display: the drag handle (system-supplied), a 36pt avatar in the person's active style (full-opacity border per UI doc §"Avatars"), the person's name, a counter, and a close button.  
4. <a name="2.4"></a>The counter SHALL read `"{packed}/{packed+unpacked} packed"` in pack mode and `"{repacked}/{packed+repacked} repacked"` in repack mode. WHEN the denominator is zero, the counter SHALL read `"0/0 packed"` or `"0/0 repacked"` respectively.  
5. <a name="2.5"></a>The close button SHALL dismiss the sheet without writing any pending state (every state change is committed at the point of interaction; there is no draft/apply step).  
6. <a name="2.6"></a>On every open, the sheet body SHALL display the first group's section header at the top of the scrollable region. Scroll position SHALL NOT be preserved across opens.  
7. <a name="2.7"></a>Concurrent rules-engine updates (e.g., a sync-trigger or scenePhase trigger fires while the sheet is open) SHALL be reflected in the sheet body the next time SwiftUI evaluates the body; no manual refresh affordance is provided.  
8. <a name="2.8"></a>WHEN the sheet's bound `Person` is no longer present in `trip.participants` at the next body evaluation (e.g., a sync-arrival removed them, or a developer-deleted-the-record race), the sheet SHALL dismiss itself and return focus to the timeline. No error UI is shown.  
9. <a name="2.9"></a>Reduce Motion (`accessibilityReduceMotion`) SHALL suppress the sheet's slide-up animation in favour of an instant crossfade; the rest of the sheet's affordances remain unchanged.  

### 3. Pack mode groups and row rules

**User Story:** As someone packing for a trip, I want my items grouped by state so I can see what is left to pack, what is done, and what I am not bringing.

**Acceptance Criteria:**

1. <a name="3.1"></a>In pack mode the sheet body SHALL render three groups in order: "Still need to pack" (filter `state == .unpacked`), "Packed" (filter `state == .packed`), "Not bringing" (filter `state == .excluded`). Section header colours SHALL be `warnColour`, `checkColour`, and `textSecondary` respectively per UI doc §"Section header colour rules".  
2. <a name="3.2"></a>Empty groups SHALL still render their section header but display no body rows; no placeholder string is shown beneath an empty header.  
3. <a name="3.3"></a>Each item row SHALL display: a checkbox (or dashed placeholder for `Not bringing`), the item name, italic condition tags for rule-driven items per UI doc §"Item row", and an inline action ("Skip" in `Still need to pack` / `Packed`; "Restore" in `Not bringing`).  
4. <a name="3.4"></a>The checkbox in pack mode SHALL render per UI doc §"Checkbox colour rules" pack row: unchecked uses person colour at ~67% opacity, checked uses `checkColour` solid.  
5. <a name="3.5"></a>Toggling the checkbox SHALL flip `state` between `.unpacked` and `.packed` and produce a light-impact haptic per UI doc §"Haptics".  
6. <a name="3.6"></a>Activating "Skip" SHALL set `state = .excluded` and produce a light-impact haptic. Activating "Restore" on an excluded item SHALL set `state = .unpacked` and produce a light-impact haptic.  
7. <a name="3.7"></a>Rows in `Not bringing` SHALL render with a dashed-border placeholder where the checkbox would be, the name in `textSecondary`, and no toggle interaction; the "Restore" action remains active.  
8. <a name="3.8"></a>Within each group, items SHALL be ordered active-before-dimmed (Active vs dimmed defined above), then by `name` case-insensitive ascending with stable tiebreak on `id`.  
9. <a name="3.9"></a>A dimmed (unmatched-non-pinned) row SHALL render at ~50% opacity on top of the standard active styling, including dimmed items already in `Packed` or `Not bringing`. Skip / Restore / checkbox interactions remain enabled on dimmed rows.  

### 4. Repack mode groups and row rules

**User Story:** As someone returning from a trip, I want a read-only view of what got left behind and an interactive view of what is back in the suitcase, so that I can mark the return packing without re-opening Day-of-Departure decisions.

**Acceptance Criteria:**

1. <a name="4.1"></a>In repack mode the sheet body SHALL render three groups in order: "Still in suitcase" (filter `state == .packed`), "Back in suitcase" (filter `state == .repacked`), "Left behind" (filter `state == .unpacked OR state == .excluded`). Section header colours match pack mode's `warn` / `check` / `textSecondary` per Req [3.1](#3.1).  
2. <a name="4.2"></a>Each "Still in suitcase" or "Back in suitcase" row SHALL display the same elements as Req [3.3](#3.3) except no inline Skip/Restore action; "Left behind" rows SHALL display a dashed-border placeholder for the checkbox and no inline action.  
3. <a name="4.3"></a>The checkbox in repack mode SHALL render per UI doc §"Checkbox colour rules" repack row: unchecked uses `checkColour` at ~67% opacity, checked uses `checkColour` solid.  
4. <a name="4.4"></a>Toggling the checkbox SHALL flip `state` between `.packed` and `.repacked` and produce a light-impact haptic.  
5. <a name="4.5"></a>"Left behind" rows SHALL be read-only: no checkbox interaction, no Skip/Restore, no edit; long-press to reveal `WhyDisclosure` remains available per Req [7](#7-whydisclosure-for-packing-items).  
6. <a name="4.6"></a>The "+ Add item" affordance from Req [5](#5-manual-item-creation-pack-mode-only) SHALL NOT appear in repack mode.  
7. <a name="4.7"></a>Ordering within each repack-mode group SHALL follow Req [3.8](#3.8) (active-before-dimmed, then alphabetical with id tiebreak).  
8. <a name="4.8"></a>Dimmed-row styling per Req [3.9](#3.9) SHALL apply equally in repack mode for rows in "Still in suitcase" and "Back in suitcase". "Left behind" rows are read-only regardless of match state.  

### 5. Manual item creation (pack mode only)

**User Story:** As a trip planner, I want to add a one-off packing item for this trip directly inside the sheet, so that I can capture an item that does not deserve a master entry.

**Acceptance Criteria:**

1. <a name="5.1"></a>In pack mode the sheet SHALL render a dashed-border `"+ Add item for {short-name}"` affordance at the bottom of the body, beneath all three groups, where `{short-name}` is a derived display short form of the active person's name. The exact derivation algorithm is an implementation detail (design phase); the observable invariant is that `{short-name}` is non-empty whenever `Person.name` is non-empty.  
2. <a name="5.2"></a>Activating the affordance SHALL present a form requiring a name. The form SHALL be presented as a `.sheet` modally on top of the packing sheet (sheet-on-sheet); dismissing the inner form SHALL return the user to the packing sheet without dismissing the packing sheet itself. No assignee picker is shown (the active person is implied). No conditions field is shown (manual items are always active).  
3. <a name="5.3"></a>Submitting the form SHALL create a `TripPackingItem` with `source: .manual`, `name` (leading/trailing whitespace trimmed), `person` set to the active person, `trip` set to the active trip, `state: .unpacked`, `currentlyMatchesRules: true`, `pinnedByUser: false`, and `masterItemID: nil`.  
4. <a name="5.4"></a>Submit SHALL be disabled WHEN the trimmed name is empty.  
5. <a name="5.5"></a>The name field SHALL accept at most 200 characters; characters beyond the limit SHALL be rejected at input.  
6. <a name="5.6"></a>Cancelling the form SHALL discard the input and leave the sheet body unchanged.  
7. <a name="5.7"></a>WHEN the rules engine inserts or removes items while the form is presented, the form SHALL remain unaffected; the sheet body SHALL update on form dismissal.  
8. <a name="5.8"></a>A newly created manual item SHALL appear in the "Still need to pack" group immediately on form dismissal, ordered per Req [3.8](#3.8).  

### 6. Item editing

**User Story:** As a trip planner, I want to rename a packing item on this trip, so that I can correct a typo without revisiting the master list.

**Acceptance Criteria:**

1. <a name="6.1"></a>The system SHALL provide an edit affordance for each row that has a checkbox (i.e., not "Not bringing" / "Left behind"), triggered by a trailing swipe revealing an "Edit" action and a context menu (touch-and-hold via `contextMenu`) that mirrors it. The body-long-press gesture SHALL remain reserved for `WhyDisclosure` per Req [7](#7-whydisclosure-for-packing-items).  
2. <a name="6.2"></a>The edit affordance SHALL allow renaming the item (subject to Req [5.5](#5.5)'s 200-character limit) but SHALL NOT allow changing the assignee, conditions, source, or master link.  
3. <a name="6.3"></a>Renaming a rule-driven item on a trip SHALL NOT alter the corresponding `MasterPackingItem`; the change is local to the `TripPackingItem` record.  
4. <a name="6.4"></a>No separate "Delete" affordance is exposed in v1. Exclusion via "Skip" per Req [3.6](#3.6) is the only removal mechanism for both manual and rule-driven items; restore reverses it.  
5. <a name="6.5"></a>The `.contextMenu` per Req [6.1](#6.1) and the body long-press for `WhyDisclosure` per Req [7.1](#7.1) SHALL coexist by region: `.contextMenu` is attached only to the row's trailing-edge tap area (the area that would also receive the swipe action), while the body long-press is attached only to the row's leading content region (name + tags). The two gestures SHALL NOT overlap spatially. Mirrors Phase 3 Req 7.1's distinction.  

### 7. WhyDisclosure for packing items

**User Story:** As a trip planner, I want to see why a packing item is on this trip, so that I can adjust trip attributes if an item looks unexpected.

**Acceptance Criteria:**

1. <a name="7.1"></a>A long-press on the body region of a packing row (excluding the checkbox tap region and any inline action button) SHALL expand an inline disclosure beneath the row and produce a light-impact haptic per UI doc §"Haptics".  
2. <a name="7.2"></a>Only one disclosure SHALL be expanded at a time within the sheet body; opening a second SHALL collapse the first. Re-opening the sheet for a different person SHALL reset disclosure state.  
3. <a name="7.3"></a>A second long-press on the same row SHALL dismiss the disclosure. Any tap inside the sheet body that does not activate another control (checkbox, inline action, "+ Add item", row tap target, section header — none of which is currently interactive but is reserved) SHALL also dismiss the disclosure.  
4. <a name="7.4"></a>WHEN the item is rule-driven (`source: .rule`, `masterItemID` non-nil) AND the master exists AND at least one master condition currently matches the trip's attributes, the disclosure SHALL display the matched conditions joined per UI doc §"Explainability — Behaviour" (AND across attribute types, OR within an attribute type).  
5. <a name="7.5"></a>WHEN the item is rule-driven AND the master exists AND no master condition currently matches, the disclosure SHALL display `"No conditions currently match your trip's attributes — this item may have matched previously."`  
6. <a name="7.6"></a>WHEN the item is rule-driven AND the master no longer exists (`masterItemID` lookup returns nil), the disclosure SHALL display `"Originally added by a rule that has since been removed."`  
7. <a name="7.7"></a>WHEN the item is manual (`source: .manual`), the disclosure SHALL display `"You added this manually for this trip."`  
8. <a name="7.8"></a>The disclosure background and header style SHALL follow UI doc §"Visual treatment — Packing context": person-colour background at ~6% opacity, no border, header `"WHY?"` in 9pt heavy uppercase in the person colour.  
9. <a name="7.9"></a>Matched conditions SHALL be computed on demand by intersecting the master item's current conditions with the trip's current attributes (no snapshot), mirroring Phase 3 Req 8.9.  
10. <a name="7.10"></a>Long-press SHALL trigger `WhyDisclosure` on every row regardless of group, including "Not bringing" (pack mode) and "Left behind" (repack mode). Read-only here means the row's state cannot be mutated (no checkbox toggle, no Skip / Restore, no Edit per Req [4.5](#4.5)); explainability remains available so users can audit why an item ended up in those groups.  

### 8. Sheet body change propagation

**User Story:** As a trip planner, I want the timeline summary to stay in sync with my actions in the sheet, so that closing the sheet shows accurate progress.

**Acceptance Criteria:**

1. <a name="8.1"></a>Every state-change interaction inside the sheet (checkbox toggle, Skip, Restore, manual add, rename) SHALL commit immediately to SwiftData via `modelContext.save()` (or its `autosave` equivalent already in effect) so the underlying timeline reads updated counts the next time it evaluates.  
2. <a name="8.2"></a>The per-person summary row's status label and progress bar SHALL reflect the latest item states with no perceptible lag after sheet dismissal (within one SwiftUI body evaluation cycle).  
3. <a name="8.3"></a>The rules engine SHALL NOT be re-triggered by sheet interactions (state changes are not master-list changes and are not trip-attribute changes per Phase 2 trigger matrix).  
4. <a name="8.4"></a>WHEN `modelContext.save()` throws on a state-change commit, the system SHALL log the failure with the `[PackingSheet.save-failed]` marker and SHALL leave the underlying record untouched (the failure surfaces visually as the row re-rendering in its prior state on the next body evaluation). No alert or banner is shown in v1.  
5. <a name="8.5"></a>WHEN a concurrent rules-engine apply mutates an item that the user is interacting with (e.g., a sync-arrival flags it as unmatched or a master-list edit deletes it while a tap is in flight), the system SHALL prefer the engine's write: the row SHALL re-render with the engine's state on the next body evaluation, and any in-flight gesture SHALL be cancelled at that point.  

### 9. Accessibility

**User Story:** As a VoiceOver user or someone using larger text sizes, I want the packing summary and sheet to be fully usable, so that the app works without sight or at accessible text sizes.

**Acceptance Criteria:**

1. <a name="9.1"></a>Each per-person summary row SHALL expose a combined VoiceOver label of the form `"{Name}'s packing, {numerator} of {denominator} {packed|repacked}"` matching the mode, falling back to `"{Name}'s packing, no items"` when the denominator is zero. The label SHALL append `"double tap to open packing sheet"`.  
2. <a name="9.2"></a>Each item row SHALL expose a custom VoiceOver rotor action `"Why is this here?"` that toggles the `WhyDisclosure` inline.  
3. <a name="9.3"></a>Each item row that supports edit per Req [6.1](#6.1) SHALL also expose custom VoiceOver rotor actions `"Edit"` and the relevant skip/restore action label (`"Skip"` or `"Restore"`).  
4. <a name="9.4"></a>All interactive elements (summary row, item row, checkbox, "+ Add item" affordance, close button) SHALL provide a 44pt × 44pt minimum touch target.  
5. <a name="9.5"></a>The sheet content SHALL reflow without truncation or clipping at Dynamic Type sizes from xSmall through AX2.  
6. <a name="9.6"></a>"Left behind" rows SHALL announce their state via the VoiceOver label (e.g., `"left behind"` appended to the row label) so the read-only nature is audible.  
7. <a name="9.7"></a>On sheet present, VoiceOver focus SHALL move to the sheet header (avatar + person name + counter). On sheet dismiss, focus SHALL return to the per-person summary row that opened the sheet.  
8. <a name="9.8"></a>WHEN a checkbox toggle moves an item between groups, the system SHALL post a `UIAccessibility.Notification.announcement` of the form `"Moved to {target group name}"` so VoiceOver users receive confirmation that the item left its prior section.  
9. <a name="9.9"></a>External-keyboard navigation SHALL move focus between interactive controls in source order; Space SHALL toggle the focused checkbox; Escape SHALL dismiss the sheet (or, if an inner `WhyDisclosure` is open, dismiss that first).  

### 10. Rules-engine invariants Phase 4 depends on

**User Story:** As a developer, I want explicit Phase 4 contracts with the existing rules engine, so that future Phase 5 sync work inherits documented invariants instead of de facto behaviour.

**Acceptance Criteria:**

1. <a name="10.1"></a>The rules engine SHALL NOT write to any `TripPackingItem` whose `source == .manual` during compute / apply. Manual items are invisible to the engine in both directions (mirrors the existing task-side invariant documented in `docs/agent-notes/rules-engine.md` §"Exclusion asymmetry"). Phase 4 does not change the engine; this requirement records the dependency for Phase 5 review.  
2. <a name="10.2"></a>State writes initiated by the packing sheet (`state` transitions among `unpacked` / `packed` / `repacked` / `excluded`) SHALL NOT toggle `currentlyMatchesRules` or `pinnedByUser`. Those two flags are owned by the engine and the master-list editor respectively; the sheet is read-only with respect to them in v1.  
3. <a name="10.3"></a>Per-trip scope: state changes made via the sheet SHALL affect only the `TripPackingItem` records bound to the active trip. The corresponding `MasterPackingItem` SHALL NOT be mutated by any sheet interaction.  
