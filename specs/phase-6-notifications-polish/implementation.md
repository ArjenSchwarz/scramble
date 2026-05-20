# Implementation: Phase 6 — Notifications + Polish

Notes that didn't belong in `decision_log.md` (no architectural choice
involved) or `tasks.md` (not actionable as a task).

## Shipped vs. deferred at completion

Phase-by-phase status against the spec:

| Phase | Tasks | Status |
|---|---|---|
| 1 — `SchemaV4` + `Trip.countryCode` | 3 | done |
| 2 — Notification primitives | 7 | done |
| 3 — Service + router + broadcaster | 8 | done |
| 4 — App wiring | 7 | done |
| 5 — Routing | 2 | done (minimum viable; see "Deferred details") |
| 6 — Country flag UI | 5 | done |
| 7 — Animations | 5 | done |
| 8 — Haptics | 4 | done |
| 9 — VoiceOver labels | 8 | done |
| 10 — Dynamic Type | 3 | done (AX2 reflow already in place; see below) |
| 11 — Documentation | 3 | done |

## Deferred details

### Phase 5 — full routing state machine

The `design.md` § "Consumer state machine" describes a four-state machine
`.idle → .dismissingSheets → .navigating → .idle` that dismisses every
known SwiftUI sheet binding and calls `dismiss(animated: false)` on the
`UICloudSharingController` host before navigating, bridged by a single
`Task.yield()`. The shipped consumer in `RootView.consumeActivationRoute`
flips the tab, resets `tripsPath` to root, and pushes the trip — this
delivers correct end-state navigation but does not actively dismiss any
sheet that was already up. Sheet-dismissal-before-routing is a polish
item, not a correctness blocker: the trip detail still becomes the
front-most screen once the user dismisses the sheet themselves.

### NotificationsService is not `@Observable`

`@Observable` was prepared on the class then removed. Marking it
`@Observable` while it owns a SwiftData `ModelContext`-returning closure
crashes SwiftUI's AttributeGraph layout-descriptor traversal
(`Test crashed with signal trap`) under Swift Testing's parameter
machinery — every `NotificationsServiceTests` case fails before its
body runs. `authStatus` remains `private(set) var` and is read at body
re-evaluation time, which is sufficient for the "Open Settings"
affordance to flip with the status. If a future surface needs reactive
binding (e.g. a settings screen), this trade-off can be revisited.

## Known limitations at AX5

Phase 6 ships AX2-correct reflow (Req 10.1–10.4) on the listed
surfaces. An AX5 sanity pass over the same surfaces against an iPhone
SE 3rd gen simulator surfaces these known issues, recorded per
Req 10.5:

- **Trip Detail header at AX5** — the trip name, phase chips, dates,
  and status caption stack vertically. The country flag emoji (Phase 6
  Req 6) does not scale (UI emoji), so it appears small relative to
  the title. Cosmetic only; no clipping.
- **Phase row task subline at AX5** — the long-form subline
  (`"3 of 5 complete · 2 inactive · Alice 2 / 3 packed"`) overflows
  the right column at AX5 with `lineLimit(2)` truncation. The combined
  accessibility label still reads the full string aloud so the data
  is recoverable via VoiceOver.
- **Packing sheet group section headers at AX5** — the section header
  ("Still need to pack", "Left behind") wraps to two lines. Headers
  remain readable; no actions are obscured.
- **Trip Editor "Destination" section flag preview at AX5** — the
  trailing flag emoji and the text field share a single line; the
  field truncates at AX5 if the user has typed only one of two
  expected letters. Saving still works.
- **`PackingItemRow` checkbox/skip combination row at AX5** — the
  trailing `Skip` button can shrink to two lines on long packing-item
  names. Hit target stays ≥ 44 pt per the wrapping `.frame(minHeight: 44)`.

None of the observed issues block use of the screen at AX5 — every
interactive element remains tappable and every required piece of
information is recoverable via VoiceOver. A follow-up phase (post
Phase 6) can pick these up as targeted layout fixes if AX5 becomes a
formal target.
