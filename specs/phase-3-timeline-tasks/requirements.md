# Requirements: Phase 3 — Timeline + Tasks

## Introduction

Phase 3 makes the Trip Detail screen usable by rendering the full timeline accordion and the tasks list inside each phase. It is the first UI surface that consumes the rules engine's output from Phase 2: rule-driven and manual tasks coexist in a single list, with explainability via long-press. The work also resolves the short-trip phase compression open question and adds an assignee field to `TripTask`.

## Non-Goals

- Per-person packing summary block and `PackingSheet` (Phase 4)
- CKShare invitations and multi-device sync UI (Phase 5)
- Phase activation notifications and notification deep-links (Phase 6)
- macOS layout
- Reordering tasks within a phase
- Copying or duplicating tasks
- Promoting a manual one-off task into the master list
- Country flag emoji on the header (deferred Decision 5 from Phase 1)
- Filtering by assignee or completion state
- Undo for task deletion
- Recovering or surfacing tasks attached to a compressed phase
- A "default assignee" field on `MasterTaskItem` (deferred; engine-created tasks start with no assignee)
- A UI affordance to view or restore user-deleted rule-driven tasks within a trip

## Trip-date-to-phase-date mapping

The following mapping defines each `Phase`'s calendar date range for a trip with `startDate = S` and `endDate = E` (both normalized to `startOfDay`). This mapping is what "phase duration" in the rest of this document refers to.

| Phase | Date range | Duration |
|---|---|---|
| `weeksBefore` | open, ending at `S − 2 days` (inclusive) | open-ended |
| `dayBefore` | `S − 1 day` (single day) | 1 day |
| `departureDay` | `S` (single day) | 1 day |
| `duringTrip` | `S + 1 day` through `E − 1 day` (inclusive) | `max(0, (E − S) − 1)` days |
| `dayBeforeReturn` | `E − 1 day` (single day) | 1 day |
| `returnDay` | `E` (single day) | 1 day |
| `afterTrip` | open, starting at `E + 1 day` | open-ended |

Overlapping phases (e.g., `dayBefore` and `dayBeforeReturn` coincide on the calendar when `S == E`; `departureDay` and `returnDay` coincide when `S == E`) are not treated as zero-duration: each still has 1 day. Their visual coexistence is a design-phase concern and does not trigger compression.

## Requirements

### 1. Timeline structure and phase nodes

**User Story:** As a trip planner, I want to see all seven phases of my trip on a single vertical timeline with clear visual states, so that I can spatially locate where I am in the trip lifecycle.

**Acceptance Criteria:**

1. <a name="1.1"></a>The Trip Detail screen SHALL render seven phase nodes in canonical phase order (weeks-before → after-trip), connected by a 2pt vertical spine line.  
2. <a name="1.2"></a>WHEN a phase is in the past, the node SHALL render as a filled circle in that phase's colour with a white checkmark, and the spine segment above SHALL render in that phase's colour.  
3. <a name="1.3"></a>WHEN a phase is current, the node SHALL render with a glow ring per UI doc §"Phase node visual states" and a "NOW" pill SHALL appear adjacent to the phase label.  
4. <a name="1.4"></a>WHEN a phase is in the future, the node SHALL render as an outlined circle on a dim spine segment.  
5. <a name="1.5"></a>WHEN a future or current phase is a packing phase (`departureDay` or `dayBeforeReturn`), the node SHALL display a packing glyph (🧳 for departure, 📦 for repack) inside the circle.  
6. <a name="1.6"></a>The phase header next to each node SHALL display the phase label and a subline of counts (per Req [5.3](#5.3) when tasks exist; `"Nothing here yet"` in tertiary text if a non-packing phase has no tasks).  
7. <a name="1.7"></a>Each phase node SHALL have a minimum 44pt × 44pt tappable target even though the visible circle is 24–28pt.  

### 2. Accordion expansion behaviour

**User Story:** As a trip planner, I want to expand one phase at a time and have the current phase open automatically, so that I focus on the relevant content without manually navigating.

**Acceptance Criteria:**

1. <a name="2.1"></a>Tapping a phase node or phase header SHALL toggle that phase's expanded state.  
2. <a name="2.2"></a>WHEN a phase is expanded, any previously expanded phase SHALL collapse simultaneously.  
3. <a name="2.3"></a>WHEN Trip Detail appears for a trip, the current phase SHALL be auto-expanded; previously expanded state from earlier visits SHALL NOT be persisted. WHEN the current phase is non-expandable (no tasks AND not a packing phase, or compressed per Req [3](#3-short-trip-phase-compression)), no phase SHALL be auto-expanded.  
4. <a name="2.4"></a>WHEN a phase expands, the timeline SHALL scroll so the expanding phase's header is positioned at the top of the visible area, OR at the maximum scroll offset when scrolling further is not possible (e.g., last phase).  
5. <a name="2.5"></a>A non-packing phase with zero matching-or-pinned tasks SHALL render as a non-expandable spine marker (tapping has no effect).  
6. <a name="2.6"></a>A packing phase (`departureDay` or `dayBeforeReturn`) SHALL always be expandable when it is not compressed per Req [3](#3-short-trip-phase-compression), even with zero tasks, because it carries the per-person packing summary added in Phase 4.  
7. <a name="2.7"></a>Tapping an expandable phase node or header SHALL produce a medium-impact haptic. Tapping a non-expandable spine marker SHALL produce no haptic and no visible feedback.  

### 3. Short-trip phase compression

**User Story:** As a trip planner working with a same-day or two-day trip, I want the "during trip" phase to compress visually when it has no calendar days, so that empty phases don't clutter the timeline.

**Acceptance Criteria:**

1. <a name="3.1"></a>The `duringTrip` phase SHALL render as a small spine marker (a dot on the spine, no header text, no "NOW" pill) WHEN its duration per the mapping above is zero days.  
2. <a name="3.2"></a>A compressed `duringTrip` phase SHALL NOT be tappable and SHALL NOT be expandable.  
3. <a name="3.3"></a>Packing phases (`departureDay` and `dayBeforeReturn`) SHALL NEVER be compressed, regardless of trip duration, so that the Phase 4 packing summary remains reachable. Other 1-day phases (`dayBefore`, `returnDay`) SHALL also never compress under this rule because their duration is always 1 day per the mapping above.  
4. <a name="3.4"></a>The spine line SHALL render continuously from the previous expandable phase through the compressed marker to the next expandable phase, with the marker rendered as a 4pt dot in the phase's colour at reduced opacity.  
5. <a name="3.5"></a>Tasks attached to a compressed phase SHALL remain in the underlying data, SHALL NOT be visible from the timeline, and SHALL NOT be recoverable via Phase 3 UI (orphan invisibility is an accepted Non-Goal). The rules engine is unchanged by Phase 3 and may still attach rule-driven tasks to a phase that subsequently compresses (e.g., on a trip-date edit); those tasks become orphaned per the same Non-Goal. Whether the engine should learn about compression is deferred and is not a Phase 3 deliverable.  

### 4. Task row rendering

**User Story:** As a trip planner, I want each task to show its completion state, name, and assignee, so that I know what to do and who is responsible.

**Acceptance Criteria:**

1. <a name="4.1"></a>A task row SHALL display a checkbox (left), task name, and an assignee avatar (right, when `assigneePersonID` resolves to a `Person` record).  
2. <a name="4.2"></a>The checkbox SHALL render per UI doc §"Checkbox colour rules" (tasks row).  
3. <a name="4.3"></a>WHEN a task is completed (`isCompleted == true`), the row SHALL render at 50% opacity with a strikethrough on the name.  
4. <a name="4.4"></a>WHEN a task has `currentlyMatchesRules == false` AND is not pinned, the row SHALL render dimmed (additional ~50% opacity reduction beyond completion styling) in the same task list (no separate section), remaining interactive for completion.  
5. <a name="4.5"></a>The assignee avatar SHALL render at 14pt diameter using the assignee `Person.colour` and initial per UI doc §"Avatars".  
6. <a name="4.6"></a>Each task row SHALL have a minimum 44pt height.  
7. <a name="4.7"></a>Toggling the checkbox SHALL produce a light-impact haptic and update `isCompleted` immediately.  
8. <a name="4.8"></a>WHEN `assigneePersonID` references a `Person` that no longer exists OR is no longer in `trip.participants`, the row SHALL render without an avatar; no error UI is shown.  

### 5. Task list ordering and counts

**User Story:** As a trip planner, I want a predictable task ordering and an accurate count in the phase header, so that the timeline reads consistently across visits.

**Acceptance Criteria:**

1. <a name="5.1"></a>Tasks SHALL be ordered: incomplete-matching first, then completed-matching, then incomplete-unmatching (dimmed), then completed-unmatching.  
2. <a name="5.2"></a>Within each group, tasks SHALL be ordered by name (case-insensitive ascending).  
3. <a name="5.3"></a>The phase header subline SHALL display `"{completed}/{total} tasks"` where `total` is the count of tasks with `currentlyMatchesRules == true OR pinnedByUser == true` and `completed` is the subset of those that are also `isCompleted == true`. WHEN any unmatched-non-pinned tasks are also rendered in the list, the subline SHALL append ` · +{N} inactive` where `N` is the count of unmatched-non-pinned tasks (regardless of completion). Example: with 1 of 2 active tasks completed and 3 inactive tasks rendered, the subline reads `"1/2 tasks · +3 inactive"`.  
4. <a name="5.4"></a>WHEN the subline cannot fit on a single line at the current Dynamic Type size and width, the subline SHALL wrap to a second line rather than truncate. The `+{N} inactive` clause MAY be moved to the second line independently of the `{completed}/{total} tasks` clause.  

### 6. Manual task creation

**User Story:** As a trip planner, I want to add a one-off task to a specific phase of this trip, so that I can capture trip-specific to-dos without editing the master list.

**Acceptance Criteria:**

1. <a name="6.1"></a>A "+ Add task" affordance with a dashed border SHALL appear at the end of the task list inside every expanded phase.  
2. <a name="6.2"></a>Activating the affordance SHALL present a form requiring a task name and offering an optional assignee picker showing all `Person` records in `trip.participants`. WHEN `trip.participants` is empty, the picker SHALL display a non-interactive "No participants yet — add people on the trip details screen" message; the form SHALL remain submittable with assignee unset.  
3. <a name="6.3"></a>Submitting the form SHALL create a `TripTask` with `source: .manual`, the entered name (trimmed of leading/trailing whitespace), the optional assignee, `phase` set to the currently expanded phase, `currentlyMatchesRules: true`, `pinnedByUser: false`, `userDeletedOnThisTrip: false`, and `masterItemID: nil`.  
4. <a name="6.4"></a>Submitting SHALL be disabled WHEN the trimmed name is empty.  
5. <a name="6.5"></a>The name field SHALL accept at most 200 characters; characters beyond the limit SHALL be rejected at input.  
6. <a name="6.6"></a>Cancelling the form SHALL discard the input and leave the task list unchanged.  
7. <a name="6.7"></a>WHEN the rules engine inserts or removes tasks while the form is presented, the form SHALL remain unaffected; the task list updates SHALL apply after the form is dismissed.  

### 7. Task editing and deletion

**User Story:** As a trip planner, I want to rename, reassign, and remove tasks on a trip, so that I can adjust the list without revisiting the master list.

**Acceptance Criteria:**

1. <a name="7.1"></a>The system SHALL provide an edit affordance for each task row, triggered by a trailing swipe (swipe-from-right) revealing "Edit" and "Delete" actions, with "Delete" rendered with the destructive tint per iOS conventions. A context menu (touch-and-hold via the SwiftUI `contextMenu` modifier, distinct from the body long-press gesture used for `WhyDisclosure`) SHALL mirror the same actions to provide a non-gesture path. The body-long-press gesture is reserved for `WhyDisclosure` (Req [8](#8-explainability-whydisclosure)) and SHALL NOT trigger edit.  
2. <a name="7.2"></a>The edit affordance SHALL allow renaming the task and changing or clearing the assignee. Phase SHALL NOT be editable post-creation.  
3. <a name="7.3"></a>Deletion of a manual task (`source: .manual`) SHALL remove the `TripTask` record from the trip permanently. No undo is provided in Phase 3 (see Non-Goals).  
4. <a name="7.4"></a>Deletion of a rule-driven task (`source: .rule`) SHALL set `userDeletedOnThisTrip = true` on the existing `TripTask` record (no record removal) and hide the row from the timeline. The rules engine SHALL treat such records as already-handled during compute/apply: the task is neither re-created nor un-set by subsequent re-evaluations.  
5. <a name="7.5"></a>The `userDeletedOnThisTrip` flag SHALL be scoped to a single `TripTask` record (i.e., to a single trip's instance of a rule). Deleting a rule-driven task on one trip SHALL NOT affect that rule-driven task on any other trip.  
6. <a name="7.6"></a>Renaming a rule-driven task on this trip SHALL NOT alter the corresponding `MasterTaskItem`; the change SHALL be local to the `TripTask` record.  
7. <a name="7.7"></a>CloudKit merge semantics for `userDeletedOnThisTrip` SHALL be addressed in Phase 5 (CloudKit Sharing) alongside merge semantics for `currentlyMatchesRules` and `pinnedByUser`, which Phase 2 did not define. Until Phase 5 lands, `userDeletedOnThisTrip` is treated as a per-device local field; cross-device divergence is an accepted limitation, consistent with Phase 2's deferral of sync-arrival callbacks.  

### 8. Explainability (WhyDisclosure)

**User Story:** As a trip planner, I want to see why a task is on this trip, so that I can adjust trip attributes if a task is unexpected.

**Acceptance Criteria:**

1. <a name="8.1"></a>A long-press on the body region of a task row (excluding the checkbox tap region and the assignee avatar tap region) SHALL expand an inline disclosure beneath the row and produce a light-impact haptic.  
2. <a name="8.2"></a>Only one disclosure SHALL be expanded at a time within a task list; opening a second SHALL collapse the first.  
3. <a name="8.3"></a>A second long-press on the same row, or a tap elsewhere within the expanded phase, SHALL dismiss the disclosure.  
4. <a name="8.4"></a>WHEN the task is rule-driven (`source: .rule`, `masterItemID` non-nil) AND the master item exists AND at least one master condition currently matches the trip's attributes, the disclosure SHALL display the matched conditions, with conditions joined per UI doc §"Explainability — Behaviour" (AND across attribute types, OR within an attribute type).  
5. <a name="8.5"></a>WHEN the task is rule-driven AND the master item exists AND no master condition currently matches (i.e., the task is in the unmatched-non-pinned state), the disclosure SHALL display "No conditions currently match your trip's attributes — this task may have matched previously."  
6. <a name="8.6"></a>WHEN the task is rule-driven AND the master item no longer exists (looking up `masterItemID` returns nil), the disclosure SHALL display "Originally added by a rule that has since been removed."  
7. <a name="8.7"></a>WHEN the task is manual (`source: .manual`), the disclosure SHALL display "You added this manually for this trip."  
8. <a name="8.8"></a>The disclosure background and header style SHALL follow UI doc §"Visual treatment — Tasks context".  
9. <a name="8.9"></a>Matched conditions SHALL be computed on demand by intersecting the master item's current conditions with the trip's current attributes (no snapshot).  

### 9. TripTask schema: assignee and deletion flag

**User Story:** As a developer, I want `TripTask` to carry an optional assignee reference and a per-trip deletion flag, so that the UI can display assignees and the rules engine can respect user deletion.

**Acceptance Criteria:**

1. <a name="9.1"></a>The `TripTask` model SHALL gain an optional `assigneePersonID: UUID?` property and a non-optional `userDeletedOnThisTrip: Bool` property (default `false`).  
2. <a name="9.2"></a>The schema change SHALL be introduced as a versioned `SchemaV2`; existing `TripTask` records SHALL migrate with `assigneePersonID == nil` and `userDeletedOnThisTrip == false`.  
3. <a name="9.3"></a>Tasks created by the rules engine SHALL initialize `assigneePersonID = nil`. The user assigns afterwards via Req [7.2](#7.2).  
4. <a name="9.4"></a>Deleting or removing-from-trip the `Person` referenced by `assigneePersonID` SHALL leave the `assigneePersonID` value unchanged (dangling); the task row SHALL render without an avatar per Req [4.8](#4.8). No `@Relationship` is used for `assigneePersonID`; the field is stored as `UUID?` to preserve dangling references and avoid CloudKit cross-zone `CKReference` fragility. This deviates from `MasterPackingItem.person`'s `@Relationship` convention; that convention is preserved on the packing side and is not changed here.  

### 10. Accessibility

**User Story:** As a VoiceOver user or someone using larger text sizes, I want the timeline and tasks to be fully usable, so that the app works without sight or at accessible text sizes.

**Acceptance Criteria:**

1. <a name="10.1"></a>Each phase node SHALL expose a combined VoiceOver label of the form "{Phase label}, {past|current|future} phase, {completed} of {total} tasks complete{, plus N inactive}". The label SHALL append "double tap to expand" only when the phase is expandable per Req [2.5](#2.5)/[2.6](#2.6).  
2. <a name="10.2"></a>Each task row SHALL expose a custom VoiceOver rotor action "Why is this here?" that toggles the WhyDisclosure inline.  
3. <a name="10.3"></a>Each task row SHALL also expose custom VoiceOver rotor actions "Edit" and "Delete" matching the swipe affordance of Req [7.1](#7.1).  
4. <a name="10.4"></a>All interactive elements (phase node, task row, checkbox, "+ Add task", assignee avatar when editable) SHALL provide a 44pt × 44pt minimum touch target.  
5. <a name="10.5"></a>The Trip Detail timeline content SHALL reflow without truncation or clipping at Dynamic Type sizes from xSmall through AX2.  
