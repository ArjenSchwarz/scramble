# Remove Task WhyDisclosure

## Overview

The `WhyDisclosure` ("why is this here?") explainability panel on task rows is being removed — the owner finds it adds nothing and degrades the task-row interface (T-1617). The packing surface was already stripped in Phase 4 Decision 10, so the task row is the last production consumer of the shared explainability stack (`WhyResolver`, `WhyDisclosureView`, `ConditionsFormatter`). Removing it leaves that stack with zero production callers, so the whole `Explainability/` subsystem and its tests are deleted rather than left as dead code.

## Requirements

- The system MUST remove the task-row WhyDisclosure panel, its long-press trigger (and the long-press haptic), and the "Why is this here?" VoiceOver custom action from `TaskRow`.
- The system MUST remove the disclosure-open state chain (`openDisclosureTaskID`) threaded through `TripDetailView` → `AccordionTimeline` → `TaskListSection` → `TaskRow`, including the tap-to-dismiss background layer and the phase-change reset.
- The system MUST delete the `Explainability/` subsystem (`WhyDisclosure.swift`, `WhyResolver.swift`, `ConditionsFormatter.swift`) once it has no remaining references.
- The system MUST delete the now-orphaned explainability test suites and remove the WhyDisclosure-specific tests from `TaskRowAccessibilityTests` and `TimelineAndTaskUITests`. After the change `TaskRowAccessibilityTests` MUST retain exactly its three accessibility-label tests (`labelBasic`, `labelCompleted`, `labelIncludesAssignee`) and no `hasWhyJustification` tests; `TimelineAndTaskUITests` MUST retain its non-disclosure tests and lose only `testLongPressOpensWhyDisclosure`, `testOnlyOneDisclosureOpenAtATime`, and `testTapElsewhereDismissesDisclosure`.
- The system MUST leave no stale reference to the removed explainability concept anywhere in the tree — including the `TaskRow.swift` file-header doc comment, the `ParticipantViewingEnvironmentKey.swift` doc comment, and the `WhyDisclosure` mentions in `UITestSeed.swift`'s seed-case comments (already stale for packing since Decision 10).
- The system MUST keep the `isParticipantViewingSharedTrip` environment key (it has non-explainability consumers) and update its doc comment to drop the removed WhyDisclosure / WhyResolver / `TaskRow` references.
- The system MUST leave the rules engine (matching, diffing, `currentlyMatchesRules`) and all other task-list behaviour unchanged.
- The system SHOULD record the removal as a decision-log entry that authoritatively overrides the explainability sections of the source-of-truth design docs (following the Phase 4 Decision 10 precedent), and update `CLAUDE.md` plus the affected `docs/agent-notes/` to match the new code.
- The full unit + UI suite (`make test`) MUST pass after the change.

## Implementation Approach

Pure deletion cascade; no new logic. Pattern reference: Phase 4 Decision 10 (`specs/phase-4-packing-sheet/decision_log.md`) and PR #12 (commit `92f4479`) removed the same surface from packing — follow its shape, but go further by deleting the now-orphaned shared subsystem.

Key files to modify:
- `Scramble/Scramble/Components/TaskRow.swift` — remove the `resolvedReason` state, the `modelContext` + `isParticipantViewingSharedTrip` environment reads (used only by the resolver), the `.onLongPressGesture` (and its haptic) plus the now-pointless `.contentShape(Rectangle())` on the task-name `Text` that only existed to back that gesture, the `WhyDisclosureView` block, the four `resolvedReason` `onChange` recomputes, the "Why is this here?" accessibility action (the `.accessibilityActions` block retains only its `Edit` / `Delete` actions), the `hasWhyJustification` static func, and the `onLongPress` closure parameter from the view's interface. Update the file-header doc comment to drop the WhyDisclosure / `isDisclosureOpen` description.
- `Scramble/Scramble/Components/TaskListSection.swift` — remove the `openDisclosureTaskID` binding, the `isDisclosureOpen` / `onLongPress` wiring on `TaskRow`, `toggleDisclosure`, and the dismiss-tap background layer.
- `Scramble/Scramble/Features/Trips/AccordionTimeline.swift` — remove the `openDisclosureTaskID` binding, its forward to `TaskListSection`, and the `openDisclosureTaskID = nil` reset on phase change.
- `Scramble/Scramble/Features/Trips/TripDetailView.swift` — remove the `openDisclosureTaskID` `@State` and the binding passed to `AccordionTimeline`.
- `Scramble/Scramble/Persistence/ParticipantViewingEnvironmentKey.swift` — update the doc comment only; the key stays (consumers are now `PackingSheet` / `PackingItemForm` rule-edit gating and the "Rules last evaluated" subline).

Files to delete:
- `Scramble/Scramble/Explainability/WhyDisclosure.swift`, `WhyResolver.swift`, `ConditionsFormatter.swift`.
- `Scramble/ScrambleTests/Explainability/WhyDisclosureStyleTests.swift`, `WhyResolverTests.swift`, `WhyResolverPackingTests.swift`, `WhyResolverParticipantHideTests.swift`, `ConditionsFormatterTests.swift`.

Tests to edit (not delete):
- `Scramble/ScrambleTests/Components/TaskRowAccessibilityTests.swift` — remove the three `hasWhyJustification` tests; keep the three accessibility-label tests.
- `Scramble/ScrambleUITests/TimelineAndTaskUITests.swift` — remove `testLongPressOpensWhyDisclosure`, `testOnlyOneDisclosureOpenAtATime`, `testTapElsewhereDismissesDisclosure`; keep the rest.

Docs:
- Add the decision-log entry for this feature; update `CLAUDE.md` and the affected `docs/agent-notes/` (`accessibility.md`, `packing-sheet.md`, `rules-engine.md`, `phase-5-ui-surfaces.md`) where they describe the live WhyDisclosure / WhyResolver implementation. The stale `WhyDisclosure` mentions in `Scramble/Scramble/Persistence/UITestSeed.swift`'s seed-case comments MUST be corrected (covered by the no-stale-reference requirement above), since the type they name no longer exists.

Out of Scope: the rules engine matching/diffing logic; the `isParticipantViewingSharedTrip` key itself and the "Rules last evaluated" subline; any persistence/schema change; the packing surfaces (already removed in Decision 10); rewriting the source-of-truth design docs beyond the ADR override (the ADR is the authoritative record, matching the Decision 10 precedent).

## Risks and Assumptions

- Assumption: `WhyResolver`, `WhyDisclosureView`, and `ConditionsFormatter` have no production callers other than `TaskRow` after the task-row edit. Validation: `grep` for each symbol across `Scramble/Scramble` returns no non-test hits before deleting the files.
- Risk: a `#if DEBUG` accessibility identifier (`tripDetail.whyDisclosure.*`) or a `whyDisclosure` reference lingers in a UI test or seed and fails the build. Mitigation: `grep` for `whyDisclosure` / `WhyDisclosure` across the whole tree before finishing; `make test` exercises the UI tests.
- Risk: removing `@Environment(\.modelContext)` / `@Environment(\.isParticipantViewingSharedTrip)` from `TaskRow` while another line in the file still uses one causes a compile error. Mitigation: the compiler catches it; confirm those reads have no remaining use in `TaskRow` before deleting them.
- Assumption: the retained `TimelineAndTaskUITests` tests are independent of the three deleted disclosure tests (no shared mutable seed or launch ordering between them). Validation: the suite runs serially (per the Makefile) and each test launches its own seeded app; `make test` confirms the retained tests still pass after the deletions.
- Prerequisite: branched from current `main`, which already contains the packing-side removal (Decision 10, commit `92f4479`).
