---
references:
    - smolspec.md
    - decision_log.md
---
# Remove Task WhyDisclosure

- [x] 1. Task rows render with no WhyDisclosure surface or disclosure-open state <!-- id:605qzb4 -->
  - Remove from TaskRow: the WhyDisclosure panel, the long-press gesture + haptic, the now-orphaned .contentShape on the task-name Text, the four resolvedReason onChange recomputes, the resolvedReason state, the "Why is this here?" accessibility action (leaving only Edit/Delete in the block), the hasWhyJustification static func, and the modelContext + isParticipantViewingSharedTrip reads (resolver-only).
  - Remove the onLongPress/isDisclosureOpen interface and the openDisclosureTaskID state chain + dismiss-tap layer from TaskListSection, AccordionTimeline, and TripDetailView.
  - Delete the three hasWhyJustification tests in TaskRowAccessibilityTests; keep labelBasic/labelCompleted/labelIncludesAssignee.
  - Verify: app builds; make test-quick passes; the Explainability subsystem is untouched and still compiles.
  - References: smolspec.md

- [x] 2. Explainability subsystem is gone from the codebase with no remaining references <!-- id:605qzb5 -->
  - After confirming via grep that WhyResolver, WhyDisclosureView, and ConditionsFormatter have no remaining production references (only doc comments), delete Scramble/Scramble/Explainability/{WhyDisclosure,WhyResolver,ConditionsFormatter}.swift.
  - Delete the five dedicated suites: WhyDisclosureStyleTests, WhyResolverTests, WhyResolverPackingTests, WhyResolverParticipantHideTests, ConditionsFormatterTests.
  - Verify: app builds; make test-quick passes; grep for the three symbols returns only doc-comment hits (cleared in task 4).
  - Blocked-by: 605qzb4 (Task rows render with no WhyDisclosure surface or disclosure-open state)
  - References: smolspec.md

- [x] 3. Task-disclosure UI tests are removed and the full test suite passes <!-- id:605qzb6 -->
  - Remove testLongPressOpensWhyDisclosure, testOnlyOneDisclosureOpenAtATime, and testTapElsewhereDismissesDisclosure from ScrambleUITests/TimelineAndTaskUITests.swift; keep every other test in that file.
  - Verify: full make test (unit + UI) passes and the retained timeline/task UI tests are green.
  - Blocked-by: 605qzb5 (Explainability subsystem is gone from the codebase with no remaining references)
  - References: smolspec.md

- [x] 4. No stale WhyDisclosure/WhyResolver references remain in code comments or docs <!-- id:605qzb7 -->
  - Clear stale references: TaskRow.swift file-header doc comment, ParticipantViewingEnvironmentKey.swift doc comment, and the WhyDisclosure mentions in UITestSeed.swift seed-case comments.
  - Update CLAUDE.md and the affected docs/agent-notes (accessibility.md, packing-sheet.md, rules-engine.md, phase-5-ui-surfaces.md); confirm the decision_log.md entry reads correctly.
  - Verify: a tree-wide grep for WhyDisclosure/WhyResolver/ConditionsFormatter returns hits only inside specs/remove-task-why-disclosure/.
  - Blocked-by: 605qzb6 (Task-disclosure UI tests are removed and the full test suite passes)
  - References: smolspec.md, decision_log.md
