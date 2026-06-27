# Scramble — UI/UX Design Document

**Companion docs:**

- `scramble-design-doc.md` — functional spec.
- React prototype (`direction-a.jsx`, `data.jsx`, `Scramble Directions.html`) — visual and interaction reference. Not a port target. The Swift implementation should use real `Theme` struct + environment, SwiftData, native transitions (`.matchedGeometryEffect`, `.transition`), and proper iOS chrome.

-----

## Overview

Scramble’s UI is built around the idea that a trip *is* a timeline. The Trip Detail screen presents the trip as a single vertical timeline of phases, with phase-specific content expanding inline via accordion. Packing is reached by tapping a person row inside the relevant phase, opening a bottom sheet.

There are no tabs inside a trip. The only place tabs exist is the app-level bottom bar on the Trip List screen (“Trips” / “Master Lists”).

**Platform:** iOS 26+, SwiftUI, Liquid Glass design language used selectively.

-----

## Navigation Structure

```
Trip List ──┬── Trip Detail (timeline)
            │      └── Packing Sheet (per-person, bottom sheet)
            └── Master Lists (packing items / tasks)
```

### Auto-open behaviour

If exactly one trip is active (started or starting within ~2 days), the app opens directly to that trip’s Detail screen. Standard back navigation returns to the Trip List.

-----

## Trip List

The app’s entry point.

- Active trips at the top, previous trips collapsed below.
- Bottom tab bar with two items: “Trips” and “Master Lists.” This is the only tab bar in the app.
- Bottom tab bar uses Liquid Glass treatment — floating, translucent, detached from the bottom edge.
- “+ New Trip” as a dashed-border button below the active trips section.

-----

## Trip Detail — Timeline

A single scrollable view organised vertically as a timeline.

### Header

Sticky header that collapses on scroll using standard iOS large-title behaviour.

- Back-to-Trips affordance.
- Trip name + country flag emoji.
- Date range, e.g. “Jul 12 – 22”.
- Status line: “in 14 days” / “Day 3 of 10” / “Returning in 2 days”.
- Attribute chips row — tappable to edit (`international`, `plane`, `sun`, etc.).

### Timeline structure

Seven vertical nodes, one per phase, connected by a 2pt spine line.

#### Phase node visual states

|State                                        |Visual                                                                                                                       |
|---------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------|
|Past                                         |Filled circle in phase colour, white checkmark inside. Spine line above also in phase colour.                                |
|Current                                      |Filled circle with glow ring (`0 0 0 6pt phaseColour/22%`, `0 0 16pt phaseColour/55%`). Small “NOW” pill next to phase label.|
|Future                                       |Outlined circle, dim spine line.                                                                                             |
|Packing phase (Departure / Day-before-return)|Small 🧳 / 📦 glyph inside the node when not yet past.                                                                         |

#### Phase header (next to each node)

- Phase label (e.g., “Day before return”)
- Subline with counts: “3/5 tasks · 12 to repack”
- “Nothing here yet” in tertiary text if the phase has no tasks and is not a packing phase

### Accordion expansion

- Tap a node or phase header to toggle expansion.
- **Only one phase expanded at a time.** Tapping a new phase collapses the previous one.
- On launch, the current phase is auto-expanded.
- Expanded phase scrolls to the top of the visible area on expansion.
- Phases with no content (no tasks, not a packing phase) are not expandable — they render as a marker on the spine for completeness.
- Packing phases (Departure, Day-before-return) are always expandable, even if they have no tasks, because they always have a packing summary.

### Expanded phase content

#### Tasks list

- One row per task: checkbox + name + assignee avatar (if any).
- Checkbox colour = phase colour (per colour semantics rules below).
- Completed tasks: 50% opacity + strikethrough.
- Long-press a task to see why it appears (see Explainability).
- “+ Add task” dashed-border button at the end of the list. Adds a trip-specific task (`source: .manual`).

#### Packing block (Departure and Day-before-return only)

- Section label: “Packing” (Departure) or “Repack” (Day-before-return), with subtitle “tap a person”.
- One row per person: avatar (26pt) + name (13pt, weight 600) + thin progress bar in person colour + status label + chevron.
- Status label varies by mode:
  - Pack mode: “X to pack” or “✓ ready” when all packed.
  - Repack mode: “X to repack” or “✓ all back in” when all repacked, “—” when person has no packed items.
- Tap a person row → opens the Packing Sheet.

-----

## Packing Sheet

A bottom sheet, ~82% screen height, presented over the timeline. The timeline is **not unmounted** — its scroll position is preserved on dismissal. The sheet uses the full theme `background` gradient (not the surface colour) to feel substantial. A semi-transparent backdrop (`rgba(0,0,0,0.55)` with 2pt blur) covers the timeline behind it.

### Sheet header

- Drag handle.
- Person avatar (active state) + name.
- Counter: “5/14 packed” (pack mode) or “3/10 repacked” (repack mode).
- ✕ close button.

### Sheet body — grouped item lists

The sheet supports two modes determined by which phase node was tapped to open it. The two modes share a single SwiftUI view; the mode flag determines group definitions, available actions, and counter text.

#### Pack mode (opened from Departure node)

|Group             |Filter              |Header colour|
|------------------|--------------------|-------------|
|Still need to pack|`state == .unpacked`|warn         |
|Packed            |`state == .packed`  |check        |
|Not bringing      |`state == .excluded`|tertiary text|

Interactions:

- Toggle item checkbox: `unpacked ↔ packed`.
- Skip action (inline): `→ excluded`.
- Restore action (on excluded items): `→ unpacked`.

#### Repack mode (opened from Day-before-return node)

|Group            |Filter                           |Header colour                    |
|-----------------|---------------------------------|---------------------------------|
|Still in suitcase|`state == .packed`               |warn                             |
|Back in suitcase |`state == .repacked`             |check                            |
|Left behind      |`state == .unpacked OR .excluded`|tertiary text — read-only, dimmed|

Interactions:

- Toggle item checkbox (only on items in “Still in suitcase” or “Back in suitcase”): `packed ↔ repacked`.
- Items in “Left behind” are read-only — no checkbox, just a dashed placeholder. The return-packing list is not the place to fix what was or wasn’t packed before departure.

### Item row

- Checkbox (or read-only dashed placeholder).
- Item name.
- Condition tags in italic (e.g., *international, plane*) — lightweight context, not interactive.
- Inline action where applicable (“Skip” / “Restore”).
- Long-press to reveal why the item appears (see Explainability).

### Add item (pack mode only)

Dashed “+ Add item for {name}” button at the end of the sheet. Adds a trip-specific manual item, no master list changes.

### One component, two modes

The two modes share a single SwiftUI view. The mode flag determines:

1. Group definitions (titles, filters, colours)
1. Available actions per item
1. Header counter text

Forking pack and repack into divergent UIs is a deliberate non-goal — the constraint of one component prevents drift.

-----

## Explainability — “Why is this here?”

> **Superseded for packing (phase-4 Decision 10):** the long-press explainability described in this section was **removed from the packing sheet** — it now applies to **tasks only** (`TaskRow`). The packing-specific paragraphs below (packing long-press, the “Packing context” visual treatment, and the packing rotor action) are retained as historical design intent but no longer ship. See `specs/phase-4-packing-sheet/decision_log.md` Decision 10.

Every task and packing item supports a long-press gesture to reveal why it appears on this trip. There is no dedicated visual affordance — the gesture is discoverable through standard iOS conventions (long-press for context). This keeps row layouts uncluttered.

### Behaviour

Long-press a row to expand an inline disclosure beneath it. Two possible states:

- **Rule-driven:** “From rule: `weather: sun + scope: international`”.
  Conditions joined by “ + “ for AND across attributes; multi-value conditions within an attribute joined by “ or “.
- **Manual:** “You added this manually for this trip.”

A second long-press on the same row, or a tap elsewhere on the list, dismisses the disclosure. Only one disclosure open at a time within a list. A subtle haptic (light impact) confirms the long-press triggered.

### Visual treatment

- **Tasks context:** background uses phase colour at ~8% opacity, with a 1pt border at ~20% opacity. Small uppercase header “Why is this here?” in 9pt, weight 700, in the phase colour.
- **Packing context:** background uses person colour at ~6% opacity, no border (uses item card’s bottom border instead). Same uppercase header in 9pt, in the person’s colour.

### Implementation note

The matching conditions are computed on demand by intersecting the master item’s conditions with the trip’s current attributes. Master conditions are stable; trip attributes are the input. No snapshot needed.

-----

## Master Lists

Accessed from the Trip List bottom tab bar.

- Segmented control: “Packing Items” / “Tasks”.
- Person sub-header (for packing items) or phase sub-header (for tasks).
- Item list — each row shows item name, chevron for detail, condition chips below.
- Items with no conditions show “Always included” in dimmed text.
- “+ Add item” dashed button at the bottom.

-----

## Theming

### v1 ships one theme: Midnight Atlas (dark default)

Theme infrastructure (`Theme` struct + SwiftUI environment injection) is preserved so additional themes can be added later without refactoring. Multiple themes are planned soon after v1 ships — the architecture must support them, even though only one is shipped initially.

### Theme architecture

Themes are implemented as a `Theme` struct containing all colour values. The active theme is injected via SwiftUI’s environment. Each theme defines two variants — light and dark — with the active variant selected based on system appearance. Users select a theme; appearance follows iOS.

### Midnight Atlas — colour values

|Key              |Dark                                                             |Light                          |
|-----------------|-----------------------------------------------------------------|-------------------------------|
|`background`     |`#0A0E1A → #1A1F35`                                              |`#F2F6FA → #E4E9F2`            |
|`accent`         |`#64D2FF`                                                        |`#0A84FF`                      |
|`surface` (cards)|`rgba(255,255,255,0.05)`                                         |`rgba(255,255,255,0.7)`        |
|`surfaceBorder`  |`rgba(255,255,255,0.10)`                                         |`rgba(60,80,120,0.12)`         |
|`textPrimary`    |`#E8ECF4`                                                        |`#1C2333`                      |
|`textSecondary`  |`#7A8299`                                                        |`#6B7A8D`                      |
|`checkColour`    |`#30D158`                                                        |`#28A745`                      |
|`warnColour`     |`#FF9F0A`                                                        |`#E08600`                      |
|`phaseColours`   |`[#9B7EFF, #64D2FF, #30D158, #FFD60A, #FF9F0A, #FF6961, #7A8299]`|(slightly darkened equivalents)|

### Phase colour assignments

Phase colours are applied in order:

1. Weeks before
1. Day before
1. Departure day
1. During trip
1. Day before return
1. Return day
1. After trip

### Person colours

Each person has a colour used for their avatar, packing progress bar, and explainability disclosure background. Colours are configurable from a person’s settings — the user picks one from a fixed palette. This avoids hardcoded assignments and lets people choose their own colour.

#### Available palette

The palette is fixed (defined per theme) and offers around 8 distinct colours that read well against the theme background and are visually separable from each other.

Midnight Atlas palette:

|Colour|Dark     |Light    |
|------|---------|---------|
|Cyan  |`#64D2FF`|`#0A84FF`|
|Pink  |`#FF6EB4`|`#D9508E`|
|Yellow|`#FFD60A`|`#C09000`|
|Green |`#30D158`|`#28A745`|
|Purple|`#BF5AF2`|`#9B40D0`|
|Orange|`#FF9F0A`|`#E08600`|
|Red   |`#FF6961`|`#E04848`|
|Teal  |`#00C7BE`|`#00A0A0`|

#### Default assignments

Defaults are applied when a person is first added; the user can change them at any time from settings.

|Person  |Default colour                      |
|--------|------------------------------------|
|Arjen   |Cyan (matches accent — primary user)|
|Kelsey  |Green                               |
|Pacifica|Pink                                |
|Rigel   |Yellow                              |

#### Notes

- Two people may share a colour if the user chooses, but the UI offers a gentle warning when this happens.
- Person colours overlap with phase colours by design (the palette draws from the same theme colour space). Context (which screen/section you’re in) makes the meaning clear.

### Liquid Glass usage

Liquid Glass treatment is reserved for **floating chrome only**:

- The bottom tab bar on the Trip List screen.
- The Packing Sheet’s header/handle area.

**Content cards do not use glass.** They use the `surface` colour as a solid (or near-solid) tinted fill with a 1pt `surfaceBorder`. Glass-on-glass kills hierarchy, especially in light mode, so content surfaces are flat.

-----

## Avatars

Person avatars are **circles with the person’s initial** rendered in the person’s colour (e.g., “A”, “K”, “P”, “R”). No emoji.

- Size: 26pt (standard, in person rows), 36pt (sheet header), 14pt (compact, e.g., assignee in task row).
- Background: person’s colour at ~16% opacity (e.g., `${color}28` hex).
- Initial: person’s colour at full opacity, weight 800, sized to ~42% of the circle diameter.
- Border: 1.5pt of the person’s colour at 33% opacity (inactive) or full opacity (active/selected).

Rationale: emoji don’t reliably identify specific people, and family disagreement over “which emoji is mine” is a real problem.

-----

## Colour Semantics

Colour communicates *context* (where you are in the app). State (done/not done) is communicated through fill vs. outline, opacity change, and strikethrough — not through colour shifts.

### Checkbox colour rules

|Context                     |Unchecked                          |Checked                       |
|----------------------------|-----------------------------------|------------------------------|
|Tasks (timeline)            |Phase colour at ~67% opacity       |Phase colour solid            |
|Packing Sheet (pack mode)   |Person colour at ~67% opacity      |Check colour solid            |
|Packing Sheet (repack mode) |Check colour at ~67% opacity       |Check colour solid            |
|Excluded / Left-behind items|Dashed border, tertiary text colour|(no checked state — read-only)|

The pack-mode pattern is deliberate: an unchecked item shows the person’s colour (reinforcing whose item it is), but the *act* of completion turns it green to confirm action regardless of person.

### Section header colour rules

Section headers within the Packing Sheet use semantic colours:

- “Still need to pack” / “Still in suitcase” → warn colour
- “Packed” / “Back in suitcase” → check colour
- “Not bringing” / “Left behind” → tertiary text colour

-----

## Component Specifications

### Phase node

- Diameter: 24pt (future), 28pt (current — accounts for glow).
- Spine line: 2pt width, vertical, connecting nodes.
- Glow on current: dual box-shadow as specified in node visual states.
- Tappable target: 44pt minimum (extends beyond visual circle).

### Task / packing row

- Min height: 44pt for accessibility.
- Padding: 10–12pt vertical, 12–14pt horizontal.
- Layout: checkbox, content (name + metadata), trailing affordances (assignee avatar, action buttons).
- Long-press anywhere on the row reveals the explainability disclosure.

### Checkbox

- Size: 20pt (default), 22pt larger contexts.
- Border radius: 5pt.
- Unchecked: 1.5pt border in the contextual colour at 50% opacity.
- Checked: solid fill with white checkmark.

### Progress indicators

Per-person packing progress uses a thin horizontal bar:

- Height: 3pt.
- Track: person colour at 12% opacity.
- Fill: person colour at full opacity, transitions to check colour when 100%.
- Border radius: 2pt.

-----

## Typography

- Screen titles: 22pt, weight 800, letter-spacing -0.3.
- Section headers: 10pt, weight 700, uppercase, letter-spacing 0.5.
- Phase labels: 14–16pt, weight 700.
- List item names: 13–14pt, weight 500.
- Metadata/captions: 9–11pt, secondary text colour.
- All text uses the system font (-apple-system / SF Pro).

-----

## Transitions and Animations

- Phase node selection (current state, glow): 0.2s ease.
- Accordion expand/collapse: matched-geometry-style transition with a fade-in for content.
- Checkbox state change: 0.15s ease on background and border.
- Task/item completion fade: 0.2s ease to 50% opacity.
- Packing Sheet present/dismiss: standard `.presentationDetents` behaviour (large detent), swipe-down to dismiss.
- Explainability disclosure expand: 0.2s ease, height-based.

Use SwiftUI `.transition`, `.matchedGeometryEffect`, and `.animation` modifiers — not manual animation code.

-----

## Accessibility

### VoiceOver

- Phase nodes: combined label like “Day before return, current phase, 3 of 5 tasks complete, double tap to expand”.
- Rows: include a custom rotor action “Why is this here?” so VoiceOver users can access explainability without needing the long-press gesture.
- Progress bars: include numeric values (“Pacifica’s packing, 5 of 9 packed”).
- Excluded/Left-behind items: labelled as such (“not bringing” / “left behind”).

### Dynamic Type

- Timeline content must reflow gracefully up to AX2.
- Test at AX5 (largest accessibility size) and at minimum size.
- Phase node diameter remains fixed; text scales independently around it.

### Touch targets

All interactive elements minimum 44pt × 44pt, even when visual element is smaller (use invisible padding).

### Contrast

All theme colour pairings must pass WCAG AA. The Midnight Atlas dark variant has been spot-checked; light variant requires verification across all phase colours when implemented.

-----

## Haptics

|Interaction                           |Haptic       |
|--------------------------------------|-------------|
|Checkbox toggle (task or packing item)|Light impact |
|Phase node tap                        |Medium impact|
|Sheet present                         |Soft impact  |
|Item skip / restore                   |Light impact |
|Long-press to reveal explainability   |Light impact |

-----

## Engineering Decisions and Open Questions

### Decided

- Trip Detail = single timeline, no tabs.
- One-at-a-time accordion for phase expansion.
- Packing reached via Sheet from a person row inside the relevant phase.
- One SwiftUI view shared by Pack and Repack modes.
- Single theme (Midnight Atlas) for v1; theme architecture preserved.
- Initial-in-coloured-circle avatars; person colours configurable from settings.
- Explainability ships in v1, triggered by long-press (no dedicated button).
- Focus Mode is removed.

### Open

1. **Sheet detents:** confirm `presentationDetents` configuration. Single large detent or `.large` with custom? Swipe-down dismisses in addition to ✕.
1. **Short-trip phase compression:** 1-day trips have empty “weeks before” and degenerate “during trip”. Suggested rule: collapse phases with empty/zero-length date ranges to a thin spine marker (visible in the timeline but not expandable). Confirm before implementation.
1. **Notification deep-link:** notifications fire on phase activation. Tapping a notification opens the trip with that phase auto-expanded.

-----

## Implementation Order (Recommended)

1. Trip Detail scaffold + sticky header with attribute chips.
1. `PhaseNode` component (circle + spine line + glow states).
1. Timeline composition with one-at-a-time accordion expand.
1. Task row + checkbox + assignee avatar.
1. `WhyDisclosure` component (used by tasks AND packing items).
1. Packing summary block (per-person rows w/ progress bar) on Departure / Day-before-return phases.
1. `PackingSheet` — pack mode (groups, item rows, skip/restore, add).
1. `PackingSheet` — repack mode (filter swap, read-only Left Behind group).
1. Rules engine: expose per-item matching conditions for explainability strings.
1. Polish: SwiftUI transitions on expand/collapse, haptics, VoiceOver labels, Dynamic Type pass.

-----

## Future Considerations

- **Additional themes:** Warm Wanderer, Tropical Scramble, Vivid Voyage. Theme picker in settings, planned soon after v1.
- **App icon:** Liquid Glass icon style per iOS 26 guidelines.
- **Widgets:** Lock screen and home screen widgets showing trip countdown and urgent task count.
- **iPad layout:** Master-detail split view with timeline on the right, trip list/sidebar on the left.
- **Suitcase-grouped packing view:** alternative to person-first when packing.
- **Trip templates / named attribute presets.**