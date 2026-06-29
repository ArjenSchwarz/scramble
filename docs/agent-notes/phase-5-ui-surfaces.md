# Phase 5 — UI surfaces (tasks 30–35)

The Trip Detail share affordance, Participants section, Trip List
migration banner + Syncing badge, and the participant-only "Rules last
evaluated" subline. Tests live under `ScrambleUITests/Phase5*UITests`
and `ScrambleTests/Sharing/RulesLastEvaluatedTrackerTests`.

## Files

- `Scramble/Scramble/Features/Trips/ShareToolbarButton.swift` — Trip
  Detail trailing toolbar item. Visible only when
  `SharingService.ownerIdentity(forTrip:) == .currentUser`. Tapping
  calls `createShare` then mounts `UICloudSharingControllerRepresentable`
  in a sheet. Errors surface via `TransientToast`.
- `Scramble/Scramble/Features/Trips/ParticipantsSection.swift` — Lives
  between the chip row and the timeline on Trip Detail. Async-loads
  `[ShareParticipant]` from the sharing service, distinguishes pending
  vs accepted via the `acceptanceLabel` string, and exposes per-row
  manage-buttons for owners only (participant-side rows are read-only
  plain content). The owner tap target uses
  `.accessibilityLabel("Manage <name>")` because Buttons collapse
  descendants into a single accessibility element.
- `Scramble/Scramble/Features/Trips/MigrationRetryBanner.swift` — Inline
  banner above the Active section in the Trip List that surfaces every
  `.failed` `MigrationJournalEntry`. The retry callback is wired to
  `ZoneMigrationCoordinator.retry(tripID:)` through the
  `\.zoneMigrationCoordinator` environment key. The banner section
  short-circuits when the @Query returns no failed rows so it doesn't
  introduce stray spacing into the list.
- `Scramble/Scramble/Features/Trips/TripListView.swift` — Now owns two
  additional `@Query`s for `MigrationJournalEntry` (in-progress + failed).
  `syncingTripIDs` is computed once and passed down to `TripRow` so the
  per-row badge logic is a simple `Set.contains`. The previous
  per-`TripRow` `@Query` approach produced flaky results in UI tests
  (the dual-predicate `tripID == … && stateRaw == …` filter intermittently
  matched too broadly inside a `NavigationLink`-wrapped row).
- `Scramble/Scramble/Sharing/RulesLastEvaluatedTracker.swift` — `@Observable`
  per-trip timestamp tracker. `RulesEngineTriggerOrchestrator` writes
  via `record(tripID:at:)` on each non-self-originated
  `.zoneChanged`; Trip Detail reads via `time(forTrip:)` when
  `sharingService.ownerIdentity` reports `.otherUser`.
- `Scramble/Scramble/Sharing/UITestSharingService.swift` — DEBUG-only
  `SharingService` stub used in UI-test mode. Returns hard-coded
  participants and ownership from static dictionaries populated by
  `UITestSeed`. Selected at launch by `ScrambleApp.init` when
  `EnvironmentProbe.isUITestHost == true`.
- `Scramble/Scramble/Persistence/RulesLastEvaluatedTrackerEnvironmentKey.swift`,
  `ParticipantViewingEnvironmentKey.swift`,
  `MigrationCoordinatorEnvironmentKey.swift` — small environment keys
  shared between `ScrambleApp` and the new view code.
- `docs/release-prep.md` — release checklist (Phase 5 Req 13: promote
  CloudKit schema from Development to Production).

## Conventions

- **Owner check is synchronous** —
  `sharingService.ownerIdentity(forTrip:)` reads `TripZoneState` only
  (Req 10.4). Safe to call per render.
- **`isParticipantViewingSharedTrip` flag** — set by `TripDetailView`
  and consumed by `PackingSheet` / `PackingItemForm` to gate
  participant-side read-only category rule-edits, plus the
  "Rules last evaluated" subline. (It formerly also drove the
  participant-side "why is this here?" disclosure hide behaviour, removed
  with the explainability subsystem in T-1617.)
- **MigrationGate in tests** — `ScrambleApp` skips
  `enqueueAll() + runStageB() + syncEngine.start()` whenever
  `EnvironmentProbe.isUITestHost`, `isTest`, or `isPreview` is true.
  Otherwise the coordinator would mark seeded `.stageBInProgress`
  fixtures as `.failed` because the in-memory `tripsLocal` store is
  empty (the fixture inserts the trip into globals only).
- **UITestSharingService.reset()** runs at the top of
  `UITestSeed.applyIfRequested(globalsContainer:tripsLocalContainer:)`
  so fixtures don't leak ownership/participant maps across launches.
- **Phase 5 fixtures use the dual-container `applyIfRequested`** so
  trips land in globals (where existing `@Query<Trip>` reads from) and
  `TripZoneState` lands in `tripsLocal` (where the sharing service
  reads from). The legacy single-container `applyIfRequested` is a
  no-op for the new Phase 5 fixtures.
