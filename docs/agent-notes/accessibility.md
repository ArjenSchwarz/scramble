# Accessibility

Phase 6 added the polish pass for VoiceOver and Dynamic Type. The aim is
to be fluent at AX2 (`accessibilityMedium`); AX5 is a documented sanity
pass, not a design target.

## VoiceOver labels

Conventions used by Phase 6 polish:

- `PhaseRow` — combined accessibility label of the form
  `"{phase display name}, {state}, {N of M tasks complete}"`.
  State is one of `past`, `current phase`, `upcoming`. Hint reflects
  expand/collapse state (`double tap to expand` / `double tap to
  collapse`).
- `TaskRow` — combined label includes task name + completion state +
  assigned person + phase. Default activation toggles completion.
  Custom action `"Why is this here?"` exposes the disclosure content
  without long-press; gated by `WhyResolver.reason(...)` (suppressed
  when the item has no rule justification).
- `PackingItemRow` — combined label includes item name + current
  `PackingState` + owning person name. Excluded items labelled
  `"not bringing"`; repack-mode Left Behind items labelled
  `"left behind"`. Same `"Why is this here?"` custom action, same
  gating.
- Per-person packing progress bar in `PackingSummarySection` —
  `accessibilityValue` reads `"{name}'s packing, {packed} of {total}
  packed"`.
- Country flag emoji on the Trip Detail header — `.accessibilityHidden(true)`
  because the destination is already part of the spoken trip name
  (Req 9.6).

`Why is this here?` accessibility action: presence is gated on the same
`WhyResolver.reason(...)` check the long-press uses. Rows whose items
have no rule justification (manual one-offs, items whose master was
deleted under certain conditions) do not expose the action.

## Dynamic Type

Targets:

- Text scales freely from `xSmall` through `AX2`
  (`accessibilityMedium`). All interactive elements remain fully
  visible — no clipping, no truncation that loses required content.
- Phase-node diameter is fixed; surrounding text scales around it
  (UI design doc §"Dynamic Type").
- `TaskRow` and `PackingItemRow` labels grow vertically rather than
  truncating when they exceed one line at the current category. The
  checkbox stays top-aligned with the first line.
- All interactive elements retain a 44 × 44 pt hit target via
  `.frame(width: 44, height: 44).contentShape(Rectangle())` (or
  invisible padding when the visual is smaller).
- AX5 sanity pass is recorded in
  `specs/phase-6-notifications-polish/implementation.md`. Layout
  issues at AX5 are recorded as known limitations rather than fixed
  in this phase.

## Haptics matrix

Five interactions fire haptics (Reqs 8.1–8.5):

| Interaction | Style | File |
|---|---|---|
| `TaskRow` checkbox toggle | `.light` | `Components/TaskRow.swift` |
| `PackingItemRow` checkbox toggle | `.light` | `Components/PackingItemRow.swift` |
| `PackingItemRow` skip / restore | `.light` | `Components/PackingItemRow.swift` |
| `PhaseRow` tap (expand/collapse) | `.medium` | `Components/PhaseRow.swift` |
| `PackingSheet` root `.onAppear` | `.soft` | `Features/Trips/PackingSheet.swift` |
| `WhyDisclosure` becoming visible (long-press) | `.light` | `Components/TaskRow.swift` / `PackingItemRow.swift` |

All use `UIImpactFeedbackGenerator(style:)` per Req 8.6. iOS's native
"reduce haptics" preference suppresses them automatically.

## Reduce Motion

`Animation.scrambleStandard` is the single shared constant (ease-in-out,
0.22 s) used by phase-row toggles and task/packing checkbox toggles.
Affected view trees use inert modifiers (`opacity`, `strikethrough`)
rather than geometric transitions, so the Reduce Motion swap is already
a cross-fade with no extra wiring needed.

## Known limitations

- Pre-existing `accessibilityLabel` strings on `PhaseRow`, `TaskRow`,
  `PackingItemRow`, and the per-person progress bar may not yet match
  the exact wording specified in Phase 6 Reqs 9.1–9.4. Phase 6's polish
  pass focuses on the structural pieces (combined-label `.accessibilityElement(children: .combine)`,
  custom-action presence, `Why is this here?` gating); the literal
  string-form refinement is tracked as a separate audit.
- AX5 sanity pass: see Req 10.5 / `specs/phase-6-notifications-polish/implementation.md`.
