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

- Per-person packing summary block on Day-before and Day-before-return phases (avatar + progress bar)
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

## Phase 5.1 — Wire Trip CRUD through `tripsLocal`

Phase 5 landed the CloudKit sharing infrastructure (dual containers, `TripSyncEngine`, translators, `CloudKitSharingService`, Stage A/B migration, UI surfaces) but the SwiftUI view layer still reads and writes against the `globals` container. `LocalWriteHook`, `SnapshotMaintenance`, `TripDeletion.delete`, and Stage B's record-relocation step are all code-complete and unit-tested but have no production call sites. `ScrambleApp.body` binds `.modelContainer(ModelStore.containers.globals)`, so every Trip-feature view's `modelContext.save()` runs against globals and `TripZoneState.pendingUploadFlags` never gets ORed.

The user-visible consequence today: the new Share toolbar and Participants UI render, but accepting a shared trip on the participant side never makes the trip appear in their Trip List, and owner-side edits never reach the trip's CK zone. Requirements 1.3, 4.1, 4.5, 6.2, and 11.2 are blocked on this wiring.

Scope:

- Decision-log entry stating "Trip CRUD relocates to `tripsLocal`; `Person` / `Master*` stay in `globals`; cross-container `Person` reads use UUID lookup, not SwiftData relationships."
- Drop or guard the V2 `Trip.participants → Person` and `TripPackingItem.person → Person` relationships in `@Query` paths — `TripPersonSnapshot` already does the participant work.
- Add Stage B's "move trip + dependents from globals to tripsLocal" step inside `ZoneMigrationCoordinator.startOrResume` (transactional per trip).
- Switch the Trip-tab subtree to `.modelContainer(tripsLocal)`; expose `globals` via a second environment key for views that need masters/persons.
- Route every Trip-feature `modelContext.save()` through `LocalWriteHook.commit(_:)`. Adopt a lint rule or wrapping helper so the chokepoint is enforced.
- Wire `SnapshotMaintenance` into `PersonEditor` save, `TripEditorView` roster removal, `PackingSheet` delete, and a post-engine-run trigger.
- Wire `TripDeletion.delete` into the owner trip-delete path; remove the inline `modelContext.delete(trip)` + `sharingService.deleteOwnedTrip` pair.
- Forward `TripSyncEngine` sent/fetched events to `ZoneMigrationCoordinator.handleZoneSaved` / `handleRecordsSaved` / `handleRecordsFailed` so journal entries advance past `.stageBInProgress`.
- "Network required to share" surface for `createShare` when offline (Req 11.2).
- Integration tests that exercise the SwiftUI environment-binding boundary end-to-end — at least one "create trip → save propagates to tripsLocal → engine queues upload" test plus a participant-side "accept share → trip appears in list" test.
- Update `CHANGELOG.md`, `CLAUDE.md` project-status sentence, and `specs/phase-5-cloudkit-sharing/implementation.md` Completeness Assessment once each requirement cluster flips to "fully implemented."
- Add the referenced-but-missing `specs/phase-5-cloudkit-sharing/manual-test-plan.md`.

This is roughly 3–6 days of careful work; the cross-cutting nature (six+ feature views, the migration coordinator, the rules engine cold-launch pass, and the test suite) is what makes it a phase of its own rather than a bug fix.

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

**Phase 5.1 between sharing and notifications.** The Phase 5 pivot from Decision 6 (one `ModelContainer` per zone) to Decision 13 (two `CKSyncEngine`s behind one façade) landed the persistence and sync rewrite but didn't propagate to the SwiftUI view layer. Phase 5.1 closes that loop so notifications in Phase 6 can deep-link into a working data flow.

## Open questions resolved by this plan

| Question (Phase 1 design doc) | Resolved in |
|---|---|
| Sheet detents configuration | Phase 4 |
| Short-trip phase compression rule | Phase 3 |
| Notification deep-link behaviour | Phase 6 |

## Out of scope across all phases

Per Phase 1's Non-Goals and the design doc's "Future Improvements" section: macOS app, copy-previous-trip, accommodation/activity attributes, user-configurable phases, App Store publishing, promote-to-master-list, linking Person to iCloud users, itinerary/activity planning, multi-leg trips, in-app theme picker, widgets.
