# Scramble — Implementation Phases

Plan for the work remaining after Phase 1 Foundation. Each phase is shaped to ship something observable and to be roughly comparable in scope to Phase 1.

Source material:

- `docs/scramble-design-doc.md` — functional spec
- `docs/scramble-ui-design-doc.md` — UI/UX spec
- `specs/phase-1-foundation/` — what shipped in Phase 1

## What landed in Phase 1

SwiftData + CloudKit-aware container, theme system (Midnight Atlas dark/light), two-tab app shell, Trip List with auto-open, Trip Detail scaffold (sticky header + seven static phase markers), Trip editor with attributes and inline person creation, Master Lists tab placeholder.

Nothing inside a trip is functional yet — no rules engine, no tasks, no packing, no sharing, no notifications.

## Phase 2 — Master Lists + Rules Engine

The headline feature of Scramble. Ships the data layer's intelligence before any UI consumes it, so the timeline/packing surfaces in later phases are wired to the complete contract (rule-driven *and* manual items) from day one rather than retrofitted.

Scope:

- Master Lists tab: replace placeholder with real editors — packing items grouped per person, tasks grouped per phase, conditions editor (AND across attribute types, OR within an attribute type)
- Rules engine: `compute → diff → apply` per design doc §3, with `currentlyMatchesRules` flagging (no deletion) and `pinnedByUser` override
- Re-evaluation triggers: trip created, trip attributes edited, master item edited, app launch; CloudKit sync trigger stubbed for later
- Snapshot-`name` semantics on `TripTask` / `TripPackingItem` (model already supports it)
- Dangling `masterItemID` tolerance verified end-to-end

## Phase 3 — Timeline + Tasks

The trip detail screen becomes usable. UI surface for everything the rules engine writes into `TripTask`.

Scope:

- Full `PhaseNode` (glow ring, "NOW" pill, 🧳 / 📦 glyphs for packing phases — UI doc §"Phase node visual states")
- One-at-a-time accordion with auto-expand of current phase on launch
- Task row: checkbox (phase colour), name, assignee avatar, completed-state opacity + strikethrough
- "+ Add task" dashed-border affordance for manual one-offs
- `WhyDisclosure` (long-press) component — used here for tasks, reused in Phase 4 for packing
- **Resolves open question 2**: short-trip phase compression rule

## Phase 4 — Packing Sheet

The other UI surface for rules-engine output.

Scope:

- Per-person packing summary block on Departure and Day-before-return phases (avatar + progress bar)
- `PackingSheet` — one SwiftUI view, two modes (pack / repack) per UI doc §"One component, two modes"
- Pack mode groups: unpacked / packed / excluded with skip + restore actions
- Repack mode groups: still in suitcase / back in suitcase / left behind (read-only)
- "+ Add item for {name}" manual affordance
- `WhyDisclosure` reuse for packing items
- **Resolves open question 1**: `presentationDetents` configuration

## Phase 5 — CloudKit Sharing

Activates the multi-device coordination story.

Scope:

- Per-trip `CKShare` invitations + share-acceptance UI
- One-time data move: trip-owned records (`TripTask`, `TripPackingItem`) from the default zone into per-trip custom zones (per Decision 9, deferred from Phase 1)
- Strategy for global entities (`Person`, `MasterTaskItem`, `MasterPackingItem`) — default zone vs dedicated globals zone
- Participant management surface on Trip Detail
- Cross-device race handling (consistent with Decisions 15 and 16 from Phase 1)

## Phase 6 — Notifications + Polish

Closing the design docs.

Scope:

- Phase activation notifications ("5 outstanding tasks for 'weeks before'")
- Notification deep-link: open trip with that phase auto-expanded — **resolves open question 3**
- Country flag emoji on Trip Detail header (deferred Decision 5)
- `matchedGeometryEffect` and transitions on accordion expand, checkbox toggles, sheet present
- Haptics matrix from UI doc §Haptics
- VoiceOver: combined phase-node labels, custom rotor "Why is this here?", progress-bar numeric values
- Dynamic Type pass up to AX2, sanity check AX5

## Ordering rationale

**Rules engine before its UIs** (Phase 2 first). The alternative — ship task and packing UIs as manual-only, then add rules engine later — means each UI gets retrofitted with rule-source branches and `WhyDisclosure`-rule strings. Doing rules first means UIs land with both branches wired and `WhyDisclosure` testable end-to-end.

The cost: Phase 2 only changes the Master Lists tab from the user's perspective. Trips don't visibly auto-populate until Phase 3 lands. If immediate auto-populate feedback in trips matters more, a thin trip-tasks-list view could be folded into Phase 2.

**Sharing before notifications** (Phase 5 then 6). Sharing affects the data model paths that notifications need to deep-link into, so doing it first means notifications can target the final URL/state shape.

## Open questions resolved by this plan

| Question (Phase 1 design doc) | Resolved in |
|---|---|
| Sheet detents configuration | Phase 4 |
| Short-trip phase compression rule | Phase 3 |
| Notification deep-link behaviour | Phase 6 |

## Out of scope across all phases

Per Phase 1's Non-Goals and the design doc's "Future Improvements" section: macOS app, copy-previous-trip, accommodation/activity attributes, user-configurable phases, App Store publishing, promote-to-master-list, linking Person to iCloud users, itinerary/activity planning, multi-leg trips, in-app theme picker, widgets.
