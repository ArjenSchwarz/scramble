# Task Row Text Alignment

## Overview

In the trip timeline, a single-line task name renders slightly higher than its
checkbox circle because the row's name `Text` has no minimum height while the
checkbox sits centred in its own 44pt box. This change vertically centres the
task name with the checkbox, matching the packing row, which already received
this treatment in T-1587. Reference ticket: T-1619.

## Requirements

- When the task name fits within the checkbox's height, the system MUST render
  it vertically centred with the checkbox in `TaskRow`; when the name is taller
  (multi-line, or large Dynamic Type), it MUST fall back to top-alignment.
- The vertical alignment of name-to-checkbox in `TaskRow` SHOULD match the
  alignment behaviour of `PackingItemRow` at every Dynamic Type size so the two
  list styles look consistent.
- The change MUST NOT alter the position of the `WhyDisclosureView` beneath the
  name, the assignee avatar, the 44pt tap targets, or the row's swipe /
  context-menu actions.

## Implementation Approach

- Key file: `Scramble/Scramble/Components/TaskRow.swift` (line numbers below are
  indicative — locate by symbol, as they drift with edits).
- The task name is rendered by `Text(task.name)` (around line 39) inside an
  `HStack(alignment: .top, spacing: 12)`. It currently has
  `.frame(maxWidth: .infinity, alignment: .leading)`.
- Mirror the established pattern in `Scramble/Scramble/Components/PackingItemRow.swift`
  (`nameColumn`, around line 219), which adds `minHeight: 44` to the name frame:
  `.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)`. Because the
  name box then matches the checkbox's 44pt box height and both top-align inside
  the HStack, their vertical centres coincide while the name fits within 44pt.
  Taller names grow past 44pt and wrap as before.
- The `minHeight` is applied to the `Text(task.name)` box itself, which sits
  above the `WhyDisclosureView` in the same `VStack`. Growing the name's own box
  to a 44pt minimum changes only that box's height; the disclosure is a separate
  child laid out beneath it, so its top edge is unaffected.
- The existing row-level `.frame(minHeight: 44)` (around line 65) sizes the whole
  row for the tap target and is unrelated; leave it as-is.
- Dependencies: none beyond the existing SwiftUI layout already in the file. No
  data-model, rules-engine, or sync change.
- Out of Scope: any change to `PackingItemRow`; the `WhyDisclosureView` content
  or its inline placement; the assignee avatar; the row-level tap-target frame.

## Risks and Assumptions

- Assumption: the intended reference is the packing row's `minHeight: 44`
  treatment from T-1587. The ticket description says "like what we already fixed
  for the task list," but in the code it was the packing list that received the
  fix; the task row is the one still lacking it, consistent with the ticket
  title "Make the tasks text inline with the checkbox." Validated against the
  current source before writing this spec.
- Risk: with very large Dynamic Type sizes a single-line name could exceed 44pt,
  in which case `minHeight` is a no-op and alignment falls back to the current
  top-aligned behaviour. | Mitigation: this matches `PackingItemRow` exactly, so
  the two rows stay consistent at every type size; no special handling added.
- Risk: this is a visual-only change with no unit-testable logic, so a future
  refactor could silently drop `minHeight: 44` with no failing test. |
  Mitigation: accepted trade-off (see `decision_log.md`); verification is by
  build + lint passing and a visual check in the simulator that the task name
  centres with the checkbox and matches the packing row.
- Prerequisite: `PackingItemRow.nameColumn` (the reference treatment) exists and
  is unchanged — confirmed at `PackingItemRow.swift:219`.
