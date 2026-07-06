# Implementation Explanation: Remove Task WhyDisclosure (T-1617)

Three-level explanation of the branch `worktree-remove-task-why-disclosure`
(`origin/main...HEAD`: the smolspec commit, the removal commit `ed39eb5`, the
changelog/overview commits, and the pre-push-review fix `e998c60`).

## Beginner Level

### What Changed / What This Does

Scramble used to have a "Why is this here?" feature on each task in a trip. If
you long-pressed a task, a little panel slid open explaining why that task was
on your list (for example, "because this is an international trip"). This change
**removes that feature entirely** from the task list.

It also deletes the behind-the-scenes machinery that produced those
explanations — three code files (collectively the "Explainability" subsystem)
and the tests that checked them — because nothing else in the app used them any
more.

Nothing about *which* tasks appear changes. The rules that decide what goes on
your list still run exactly as before; only the on-demand "why" pop-up is gone.

### Why It Matters

The feature was judged to add little and to make the interface worse ("It
doesn't add anything and makes for a lousy interface"). The same pop-up had
already been removed from the packing list earlier; the task list was the last
place still using it. Removing it makes each task row simpler and a little
faster (the app no longer looks up a justification for every row), and it
deletes roughly 1,500 lines of now-unused code.

### Key Concepts

- **Task row**: one line in a trip's task list — a checkbox, the task name, and
  (sometimes) a small coloured circle for who it's assigned to.
- **Long-press**: touch and hold. This used to open the "why" panel.
- **Explainability subsystem**: the shared helper code that figured out and
  formatted the "why this is here" text.
- **Rules engine**: the separate system that decides which tasks belong on a
  trip. Untouched by this change.

---

## Intermediate Level

### Changes Overview

Production code (`Scramble/Scramble/`):

- **`Components/TaskRow.swift`** — the core change. Removed the inline
  `WhyDisclosureView`, the `.onLongPressGesture` + haptic, the `resolvedReason`
  `@State` and its four `.onChange` recompute blocks, the `hasWhyJustification`
  helper, the `"Why is this here?"` custom accessibility action (the block now
  holds only Edit / Delete), and the `@Environment(\.modelContext)` /
  `@Environment(\.isParticipantViewingSharedTrip)` reads that only the resolver
  needed. `import SwiftData` is dropped. The name/disclosure `VStack` collapses
  to a bare `Text(task.name)`.
- **`Components/TaskListSection.swift`**, **`Features/Trips/AccordionTimeline.swift`**,
  **`Features/Trips/TripDetailView.swift`** — removed the `openDisclosureTaskID`
  state that was owned by `TripDetailView` and threaded down through the
  accordion into each row, including the "tap elsewhere to dismiss" background
  layer and the "collapse the open disclosure when a phase toggles" reset.
- **Deleted** `Scramble/Scramble/Explainability/{WhyDisclosure,WhyResolver,ConditionsFormatter}.swift`.
- **`Persistence/ParticipantViewingEnvironmentKey.swift`** — kept; only its doc
  comment updated. The `isParticipantViewingSharedTrip` flag still has real
  consumers in `PackingSheet` and `PackingItemForm`.

Tests: deleted the five Explainability suites, trimmed three
`hasWhyJustification` cases from `TaskRowAccessibilityTests` (keeping the three
label tests) and three disclosure UI tests from `TimelineAndTaskUITests`.

Docs: `CLAUDE.md` and four `docs/agent-notes/` files updated to describe the
surface as removed; `decision_log.md` records the rationale; `CHANGELOG.md` and
`specs/OVERVIEW.md` updated.

### Implementation Approach

This is a **subtractive** change. The guiding decision (decision_log Decision 1)
is that once the task row — the last production consumer — stops using the
Explainability stack, that stack becomes dead code kept alive only by its own
tests, so it is deleted outright rather than left as test-only code. This
mirrors the earlier packing-side removal (phase-4 Decision 10).

The one piece deliberately *kept* is the `isParticipantViewingSharedTrip`
environment key. It was originally introduced to let the resolver hide "why"
text for participants viewing a shared trip, but it also independently gates
packing behaviour (`PackingItemForm` uses it to make a master-derived item's
category read-only for participants). So it survives with an updated doc comment.

### Trade-offs

- **Delete the subsystem vs. keep it test-only** — keeping it would mean
  maintaining ~1,500 lines and five test suites for code no screen renders.
  Rejected as churn without benefit.
- **Keep the VoiceOver action, drop only the long-press** — rejected: the action
  surfaced the same panel via the same resolver fetch, so keeping it would be
  inconsistent with removing the visual affordance.
- **Rewrite the design docs** — rejected. Per Decision 1 (following the Decision
  10 precedent) the ADR is the authoritative override; the design docs'
  explainability sections are left as historical record rather than rewritten.

---

## Expert Level

### Technical Deep Dive

- **View-tree simplification.** `TaskRow`'s body drops from an `HStack` whose
  middle column was a `VStack { Text; conditional WhyDisclosureView }` to a flat
  `HStack { checkbox; Text; assignee }`. Beyond the deletion, this removes four
  `.onChange` observers — notably `.onChange(of: task.trip?.attributesData)`,
  which forced SwiftData observation of a potentially large serialized blob per
  row — and a per-row `WhyResolver.reason(...)` fetch that ran inside the
  accessibility-actions builder (`context.fetch(FetchDescriptor<MasterTaskItem>)`
  on every accessibility-tree build). Net effect on the timeline hot path is
  fewer environment dependencies, fewer observers, and no per-row store fetch.
- **State-chain removal.** `openDisclosureTaskID: UUID?` was a single source of
  truth owned by `TripDetailView`, passed as a `@Binding` through
  `AccordionTimeline` into `TaskListSection` into each `TaskRow`. All four hops
  are removed, along with the `.background { if openDisclosureTaskID != nil { … } }`
  dismiss-tap overlay and the `openDisclosureTaskID = nil` line inside the
  animated `withAnimation(.scrambleStandard)` phase-toggle block.
- **Merge-safety fix (`e998c60`).** `origin/main` advanced to include T-1619
  ("Centre task row name with its checkbox"), which added
  `.frame(minHeight: isDisclosureOpen ? nil : 44)` to the task-name `Text` so a
  single-line name vertically centres with the checkbox's 44pt box (both
  top-align in the `HStack`). This branch forked *before* T-1619 and collapsed
  the name to a bare `Text` with no `minHeight`. A naïve merge taking this
  branch's side would silently revert T-1619's centring. The fix re-adds
  `minHeight: 44` unconditionally (the `isDisclosureOpen` gate is moot now that
  the disclosure is gone) as a separate modifier on the `Text` itself — the
  row-level `.frame(minHeight: 44)` sizes the row, not the intrinsic-height text,
  so it does not centre the name on its own.
- **Test-infra fix.** Five test helpers built a `ModelContainer` but returned
  only its `mainContext`, letting the container deallocate under the live
  context — the documented non-retained-`ModelContainer` anti-pattern
  (`rules/language-rules/swift.md`). The simulator's ARC timing masked it; the
  current runtime crashes the shared test host before any test runs. The helpers
  now retain the container. This is out of the smolspec's scope but disclosed in
  the commit body and CHANGELOG.

### Architecture Impact

- **Decouples the task UI from SwiftData reads.** `TaskRow` no longer needs a
  `ModelContext`; its inputs are now purely the `TripTask` model object, the
  theme, and colour scheme. This narrows the view's dependency surface.
- **`WhyResolver` / `ConditionsFormatter` are gone, not relocated.** Any future
  "why" surface would be a fresh implementation. The rules engine's
  `currentlyMatchesRules` dimming (a separate concern) is untouched, so the
  determinism guarantees the design relies on are unaffected.
- **Documentation authority.** Decision 1 becomes the canonical statement that
  the design docs' "explainability is computed on demand" sections no longer
  have a surface. The design docs are intentionally not rewritten.

### Potential Issues

- **Stale base / merge order (the main watch item).** The branch is based on
  `9855eab`; `origin/main` is now `84243bf` (T-1619 + an independently-applied
  copy of the same `ModelContainer`-retention fix in the six test helpers).
  Before pushing, rebase/merge onto `origin/main`. Expect trivially-resolvable
  conflicts in `TaskRow.swift` (take this branch's side — it already carries the
  centring), the container-retention test helpers (either side; semantically
  identical), and `CHANGELOG.md`. The `e998c60` fix pre-resolves the one
  conflict that carried a real regression risk.
- **Test verification is environment-limited.** On the current degraded
  simulator/test-host, the full `make test` is not green, but the failures were
  confirmed pre-existing and unrelated: two sharing/concurrency unit tests
  (`LocalWriteHookPBT.mixedZonePartition`, `TripSyncEventBusTests.stopCancelsIteration`)
  in untouched code, and UI timeouts that reproduce identically on the pre-change
  base commit. Build and swiftlint are clean. Re-run on a healthy runner for a
  clean green before merge.

---

## Completeness Assessment

**Fully implemented**

- Task-row WhyDisclosure UI removed (panel, long-press + haptic, orphaned
  `.contentShape`, VoiceOver "Why is this here?" action).
- `resolvedReason` state, its four `onChange` recomputes, the
  `hasWhyJustification` helper, and the resolver-only `modelContext` /
  `isParticipantViewingSharedTrip` reads removed from `TaskRow`.
- `openDisclosureTaskID` state chain and dismiss-tap layer removed from
  `TaskListSection`, `AccordionTimeline`, `TripDetailView`.
- `Explainability/` subsystem (3 sources) and its 5 test suites deleted; three
  `hasWhyJustification` unit tests and three disclosure UI tests trimmed;
  `labelBasic` / `labelCompleted` / `labelIncludesAssignee` retained.
- `isParticipantViewingSharedTrip` retained with live consumers; doc comments
  cleared in `ParticipantViewingEnvironmentKey.swift` and `UITestSeed.swift`.
- Docs updated: `CLAUDE.md`, `accessibility.md`, `packing-sheet.md`,
  `rules-engine.md`, `phase-5-ui-surfaces.md`; decision log, changelog, and
  specs overview in place.
- Single-line task-name centring preserved for the eventual merge with T-1619
  (`e998c60`).

**Partially implemented / caveats**

- Full-suite `make test` not verified green in this environment (failures are
  pre-existing and unrelated; build + lint clean). Needs a healthy-runner
  re-run before merge.
- The `ModelContainer`-retention test fix is out of the smolspec's stated scope
  (documented, justified, and redundant with an equivalent fix already on
  `origin/main`).

**Missing**

- Nothing required by the smolspec is missing. The only outstanding action is
  operational: rebase onto `origin/main` and re-run tests on a healthy runner
  before pushing/merging.
