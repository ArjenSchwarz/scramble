# Decision Log: Remove Task WhyDisclosure

## Decision 1: Delete the whole Explainability subsystem, not just the task UI

**Date**: 2026-06-29
**Status**: accepted — supersedes the task-side explainability carve-out preserved by Phase 4 Decision 10, and overrides the "Explainability is computed on demand" sections of `docs/scramble-design-doc.md` and the WhyDisclosure UI sections of `docs/scramble-ui-design-doc.md`

### Context

T-1617 removes the `WhyDisclosure` panel from task rows ("It doesn't add anything and makes for a lousy interface"). Phase 4 Decision 10 had already removed the same surface from packing, but deliberately *kept* the shared `WhyResolver` / `WhyDisclosureView` / `ConditionsFormatter` code and its packing test-only overload because the task surface still used it. The task row is the only remaining production consumer of that stack; removing it leaves `WhyResolver`, `WhyDisclosureView`, and `ConditionsFormatter` with zero production callers — alive only to satisfy their own test suites.

### Decision

Delete the entire `Scramble/Scramble/Explainability/` subsystem (`WhyDisclosure.swift`, `WhyResolver.swift`, `ConditionsFormatter.swift`) and its test suites, rather than leaving them as test-only code. The `isParticipantViewingSharedTrip` environment key is retained (it has independent packing and subline consumers); only its doc comment is updated.

### Rationale

The only reason Decision 10 retained the shared explainability code was to avoid churning a subsystem the task surface still depended on. That dependency is now gone, so the retention rationale evaporates. Keeping three source files plus five test suites alive purely to test code nothing ships would be dead weight a future reader could mistake for a live feature — exactly the "do not mistake for dead code" hazard Decision 10 had to footnote. A clean delete is the honest end state.

### Alternatives Considered

- **UI-only removal (mirror Decision 10)**: Remove only the task-row WhyDisclosure UI and state chain, keep `WhyResolver` / `WhyDisclosureView` / `ConditionsFormatter` and their tests as test-only code — Rejected: Decision 10 kept that code *because tasks used it*; with tasks gone it is dead code retained solely to keep its own tests green, which is churn without benefit.
- **Keep the VoiceOver action, drop only the long-press**: Rejected — the action surfaces the same panel and pays the same `WhyResolver` fetch; keeping it is inconsistent with removing the visual affordance (same reasoning as Decision 10).

### Consequences

**Positive:**
- No dead/test-only subsystem left behind; `Explainability/` is gone entirely.
- Task rows lose the long-press gesture, the per-row resolver fetches, and the disclosure state chain (`openDisclosureTaskID` through four views) — simpler rows and less plumbing.

**Negative:**
- Tasks lose in-app "why is this here?" explainability (sighted and VoiceOver). Accepted per owner request.
- The `docs/scramble-design-doc.md` "explainability is computed on demand" principle and the `docs/scramble-ui-design-doc.md` WhyDisclosure UI sections no longer have a surface; this ADR is the authoritative override (the design docs are not rewritten, matching the Decision 10 precedent).

### Impact

`Scramble/Scramble/Components/TaskRow.swift`, `TaskListSection.swift`, `Scramble/Scramble/Features/Trips/AccordionTimeline.swift`, `TripDetailView.swift`, `Scramble/Scramble/Persistence/ParticipantViewingEnvironmentKey.swift` (doc comment); deletes the `Explainability/` source folder and its test suites; trims the WhyDisclosure tests from `TaskRowAccessibilityTests.swift` and `TimelineAndTaskUITests.swift`; notes updated in `CLAUDE.md` and `docs/agent-notes/`.

---
