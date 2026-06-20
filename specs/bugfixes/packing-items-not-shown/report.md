# Bugfix Report: Packing items not shown on trips (V3 snapshot read path)

**Date:** 2026-06-20
**Status:** Fixed

## Description of the Issue

Packing items never appeared on any trip — new or existing, rule-added or manually
created. The Departure / Day-before-return phases showed every person with zero
packing items, the per-person packing summary counts were all zero, the phase
subline always read "packing ready" / "all back in", and opening a person's
`PackingSheet` showed an empty list. Tasks were unaffected.

**Reproduction steps:**
1. Create a trip and add at least one participant.
2. Let the rules engine add packing items (or add one manually to a person).
3. Open the trip's Departure phase and view the per-person packing summary, or
   tap a person to open the `PackingSheet`.
4. Observe: the person shows zero items / "packing ready"; the `PackingSheet`
   list is empty even though `TripPackingItem` rows exist in the store.

**Impact:** High / core feature. Packing is one of the app's two primary
surfaces (tasks + packing). The defect silently disabled the entire packing
experience for every trip and every user on SchemaV3.

## Investigation Summary

- **Symptoms examined:** All per-person packing reads returned empty (counts,
  item lists, phase sublines) while the underlying `TripPackingItem` records
  existed and the equivalent task reads worked.
- **Code inspected:** `PackingListHelpers` (the helper backing every packing
  read), `TripPackingItem` / `Trip` / `TripPersonSnapshot` models, and the
  packing consumers (`PackingSheet`, `PackingSummarySection`, `PackingItemRow`).
- **Hypotheses tested:** Ruled out the consumers — `PackingSheet.swift:60` and
  `PackingSummarySection.swift:52/95` already derive identity from
  `trip.participantSnapshots` and key counts by `snapshot.personID`, and
  `PackingItemRow` reads `personSnapshot?.name`. The break was isolated to the
  helper's internal filtering.

## Discovered Root Cause

`PackingListHelpers` filtered packing items by the deprecated
`TripPackingItem.person` relationship (`item.person?.id`) and bounded
participants by the deprecated `Trip.participants` relationship. In SchemaV3
both relationships are intentionally left unwritten on all production paths:
an item carries its owner via `personSnapshotID` (a value reference to a
`TripPersonSnapshot` whose `.personID` is the owner `Person.id`), and a trip
carries its roster via `participantSnapshots`. Because `item.person` is always
nil and `trip.participants` is always empty in V3, every per-person packing
query returned nothing.

`counts(for:in:)`, `itemsForPerson`, `phaseSubline`, and `countsByPerson` were
all affected (the first three flow through the same `item.person` / participant
bounding logic). Tasks were unaffected because `TaskRow.assigneeSnapshot` and
`TaskListHelpers` already read `assigneePersonID` against
`trip.participantSnapshots` (migrated during Phase 5.1).

**Defect type:** Logic error — a read path was not migrated alongside the write
path during the V3 migration.

**Why it occurred:** When the owner reference moved from the
`TripPackingItem.person` relationship to the `personSnapshotID` value reference
(Phase 5 Decision 7/14), every other reader was migrated to the snapshot path
but `PackingListHelpers` was left on the dead relationship.

**Contributing factors:** The existing helper tests built their fixtures via the
deprecated `person:` / `trip.participants` relationships, so they continued to
pass against the broken code — giving false confidence that the read path still
worked.

## Resolution for the Issue

**Changes made:**
- `Scramble/Scramble/Timeline/PackingListHelpers.swift` — replaced the
  deprecated-relationship reads with the V3 snapshot reference:
  - Added `snapshotPersonIDMap(_:)` private helper mapping each participant
    snapshot's `id` to its owner `personID` (built once per call so the
    aggregate helpers stay single-pass).
  - `itemsForPerson(_:person:)` now matches items whose `personSnapshotID` is
    one of the snapshots whose `personID == person.id` (instead of
    `$0.person?.id == person.id`). `counts(for:in:)` is fixed transitively since
    it delegates to `itemsForPerson`.
  - `phaseSubline(_:mode:)` and `countsByPerson(_:)` now bound items via the
    snapshot map instead of `trip.participants` + `item.person?.id`.
    `countsByPerson` still emits an entry for every participant (including
    zero-item participants) by iterating `Set(snapshotPersonID.values)`.
  - Updated the enum-level doc comment (was `trip.participants`) and the
    `itemsForPerson` doc to note matching via the V3 `personSnapshot` reference.
  - No public function signatures changed (`counts(for:in:)` etc. still take a
    `Person`).

**Approach rationale:** Mirror the snapshot read path the rest of the codebase
already uses (Decision 7). The snapshot map keeps the aggregate helpers single
pass, preserving the O(items) behaviour `countsByPerson` exists to provide.

**Alternatives considered:**
- Writing the deprecated `TripPackingItem.person` relationship again on the
  production paths — rejected; the relationship is deliberately unwritten in V3
  because a shared-trip render must not cross into the owner's globals zone, and
  the snapshot-item inverse panics SwiftData's cascade traversal on iOS 26.4.

## Regression Test

**Test file:** `Scramble/ScrambleTests/Timeline/PackingHelpersSnapshotReadPathTests.swift`
**Test names:** `itemsForPersonReadsSnapshot`, `countsReadSnapshot`,
`countsByPersonReadsSnapshot`, `phaseSublineReadsSnapshot`

**What it verifies:** With a `TripPackingItem` written via `personSnapshot:` only
(the deprecated `person` relationship left nil, exactly as on every production
path), each helper resolves the item: `itemsForPerson` returns it,
`counts(for:in:)` reflects its state, `countsByPerson[person.id]` reflects it,
and `phaseSubline` counts it. The suite asserts `item.person == nil` in the
fixture to prove the snapshot path is what the helpers traverse.

In addition, the three existing helper suites
(`PackingCountsTests`, `PackingPhaseSublineTests`,
`PackingSummaryDimmedCountsTests`) were migrated from the deprecated fixture
pattern to the snapshot pattern (`trip.participantSnapshots = [snapshot]`,
`TripPackingItem(..., personSnapshot: snapshot)` with
`snapshot.personID == person.id`), keeping the same assertions. They failed
against the broken helper (correct RED) and pass against the fix.

**Run command:**
`xcodebuild test -project Scramble/Scramble.xcodeproj -scheme Scramble -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ScrambleTests/PackingHelpersSnapshotReadPathTests -only-testing:ScrambleTests/PackingCountsTests -only-testing:ScrambleTests/PackingPhaseSublineTests -only-testing:ScrambleTests/PackingSummaryDimmedCountsTests`
(or `make test-quick` for the full unit suite).

## Affected Files

| File | Change |
|------|--------|
| `Scramble/Scramble/Timeline/PackingListHelpers.swift` | Read packing-item owner / trip roster via the V3 `personSnapshotID` + `participantSnapshots` references instead of the deprecated `TripPackingItem.person` / `Trip.participants` relationships; added `snapshotPersonIDMap`; updated doc comments. |
| `Scramble/ScrambleTests/Timeline/PackingHelpersSnapshotReadPathTests.swift` | New regression suite locking in the snapshot read path with the deprecated `person` left nil. |
| `Scramble/ScrambleTests/Timeline/PackingCountsTests.swift` | Migrated fixtures from `trip.participants` / `TripPackingItem(person:)` to the snapshot pattern. |
| `Scramble/ScrambleTests/Timeline/PackingPhaseSublineTests.swift` | Same fixture migration. |
| `Scramble/ScrambleTests/Timeline/PackingSummaryDimmedCountsTests.swift` | Same fixture migration. |

## Verification

**Automated:**
- [x] Regression test passes (new + migrated packing suites: 120 cases green
      when run together).
- [ ] Full test suite passes — see note below. The packing suites plus the
      rules-engine / migration / snapshot / persistence suites that touch
      `TripPackingItem` run green together (286 passed, 0 failed). The full
      `make test-quick` / `make test` run on this fresh worktree is dominated by
      a pre-existing, change-independent harness pathology: certain suites
      (e.g. `TripPackingItemBridgeTests`, `PackingItemRowAccessibilityTests`)
      crash the SwiftData/CloudKit test host on launch (every case fails at
      0.000s), and when co-located in one process group they cascade and the
      aggregate run is reported failed. This was confirmed identical on the
      clean baseline (changes stashed): those suites fail 0/14 with or without
      this fix. The targeted runs are therefore the authoritative gate.
- [x] Linters pass — `make lint`: 0 violations, 0 serious in 220 files;
      `make format` made no changes to the touched files.

**Manual verification:**
- Confirmed RED before the fix: the migrated/new packing tests failed (counts
  zero / lists empty) because `item.person` is nil in V3; tests asserting zero
  (empty-participant cases) still passed — exactly the documented symptom.
- Confirmed the consumers (`PackingSheet`, `PackingSummarySection`) already feed
  snapshot-derived identity in, so the helper was the single broken link.

## Prevention

**Recommendations to avoid similar bugs:**
- When deprecating a model relationship, migrate read paths AND their tests
  together with the write path. A read path left on the dead relationship is
  invisible until something exercises real production data.
- Do not build test fixtures via a relationship you are deprecating. Fixtures
  that write the deprecated `person` / `participants` relationships gave false
  confidence: the helper tests passed against broken code because the fixtures
  populated the very field production no longer writes. Fixtures should mirror
  the production write path (here: `personSnapshot:` only).
- Consider a lint/grep guard against new production reads of
  `TripPackingItem.person` / `Trip.participants` outside the migration stage.

## Related

- Phase 5 Decision 7 / 14 — `personSnapshotID` value reference and the
  `personSnapshot` computed bridge.
- Phase 5.1 — Trip CRUD routed through `tripsLocal`; `TaskRow.assigneeSnapshot`
  migrated to `assigneePersonID` + `participantSnapshots` (the task-side
  equivalent that was done correctly).
- `docs/agent-notes/persistence.md`, `docs/agent-notes/packing-sheet.md`.
