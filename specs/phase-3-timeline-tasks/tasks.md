---
references:
    - specs/phase-3-timeline-tasks/requirements.md
    - specs/phase-3-timeline-tasks/design.md
    - specs/phase-3-timeline-tasks/decision_log.md
---
# Phase 3 — Timeline + Tasks

- [x] 1. Write failing tests: SchemaV2 migration, dangling assignee, rename local scope <!-- id:je6ekkz -->
  - New test file Scramble/ScrambleTests/Persistence/SchemaV2MigrationTests.swift — seed real on-disk SQLite store with SchemaV1.TripTask records, open with AppMigrationPlan configured for SchemaV2, assert new fields default to nil/false, assert persistent entity name resolves identically across versions
  - Add DanglingAssigneeTests to Scramble/ScrambleTests/Models/ — set assigneePersonID, delete Person via context.delete, refetch TripTask and assert it survives
  - Add RenameLocalScopeTests to Scramble/ScrambleTests/Models/ — rename a rule-driven TripTask and assert source MasterTaskItem.name unchanged
  - Use Swift Testing (@Suite/@Test/#expect)
  - Stream: 1
  - Requirements: [7.6](requirements.md#7.6), [9.1](requirements.md#9.1), [9.2](requirements.md#9.2), [9.4](requirements.md#9.4), [4.8](requirements.md#4.8)
  - References: specs/phase-3-timeline-tasks/design.md, Scramble/Scramble/Models/Schema.swift, Scramble/Scramble/Models/TripTask.swift

- [x] 2. Refactor TripTask into SchemaV1/SchemaV2 namespaces, add migration stage and typealias <!-- id:je6ekl0 -->
  - Move existing TripTask declaration into SchemaV1.TripTask (frozen pre-Phase-3 shape)
  - Add SchemaV2.TripTask with assigneePersonID: UUID? = nil and userDeletedOnThisTrip: Bool = false
  - Add typealias TripTask = SchemaV2.TripTask so app code is unaffected
  - Update both VersionedSchema models arrays
  - Add MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self) to AppMigrationPlan.stages
  - Update AppMigrationPlan.schemas to include both versions
  - Ensure ModelContainer initialisation references SchemaV2
  - Blocked-by: je6ekkz (Write failing tests: SchemaV2 migration, dangling assignee, rename local scope)
  - Stream: 1
  - Requirements: [9.1](requirements.md#9.1), [9.2](requirements.md#9.2), [9.3](requirements.md#9.3)
  - References: specs/phase-3-timeline-tasks/design.md, Scramble/Scramble/Models/Schema.swift, Scramble/Scramble/Models/TripTask.swift

- [x] 3. Write failing tests: rules engine respects userDeletedOnThisTrip <!-- id:je6ekl1 -->
  - Extend ScrambleTests/RulesEngine/ComputeTests.swift with cases where TripTaskRef has userDeletedOnThisTrip == true across all four (currentlyMatchesRules, masterMatches) quadrants — assert ref is skipped in classifyTaskRefs regardless of quadrant
  - Extend ScrambleTests/RulesEngine/ApplyTests.swift — fixture where TripTask has userDeletedOnThisTrip == true and is targeted by toFlagMatched; assert flagTasks does not write currentlyMatchesRules on the deleted record
  - Add PerTripScopeTests case: two trips A and B share the same rule-driven master; delete on trip A only, re-run engine; assert trip B unchanged
  - Blocked-by: je6ekl0 (Refactor TripTask into SchemaV1/SchemaV2 namespaces, add migration stage and typealias)
  - Stream: 1
  - Requirements: [7.4](requirements.md#7.4), [7.5](requirements.md#7.5)
  - References: specs/phase-3-timeline-tasks/design.md, Scramble/Scramble/RulesEngine/Compute.swift, Scramble/Scramble/RulesEngine/Apply.swift

- [x] 4. Implement engine carve-out for userDeletedOnThisTrip <!-- id:je6ekl2 -->
  - Add userDeletedOnThisTrip: Bool to TripTaskRef in RulesEngine/Snapshots.swift and populate at all snapshot construction sites
  - Add guard !ref.userDeletedOnThisTrip else { continue } at top of classifyTaskRefs loop in Compute.swift
  - In Apply.swift flagTasks, skip records whose userDeletedOnThisTrip == true before writing currentlyMatchesRules
  - Do NOT change referencedMasterIDs(in:) — it already includes deleted refs by virtue of masterItemID presence
  - Blocked-by: je6ekl1 (Write failing tests: rules engine respects userDeletedOnThisTrip)
  - Stream: 1
  - Requirements: [7.4](requirements.md#7.4), [7.5](requirements.md#7.5)
  - References: specs/phase-3-timeline-tasks/design.md, Scramble/Scramble/RulesEngine/Compute.swift, Scramble/Scramble/RulesEngine/Apply.swift, Scramble/Scramble/RulesEngine/Snapshots.swift

- [x] 5. Write PhaseDateMapping tests <!-- id:je6ekl3 -->
  - New ScrambleTests/Timeline/PhaseDateMappingTests.swift
  - Cover each Phase × representative (start, end) pairs from canonical mapping table in design.md
  - Property-style test: only duringTrip can be zero-duration when end > start + 1 day; duringTrip is zero-duration when end - start <= 1 day
  - Assert isCompressed returns true iff phase == .duringTrip && durationDays == 0
  - Stream: 2
  - Requirements: [3.1](requirements.md#3.1), [3.3](requirements.md#3.3)
  - References: specs/phase-3-timeline-tasks/design.md, specs/phase-3-timeline-tasks/requirements.md

- [x] 6. Implement PhaseDateMapping helper <!-- id:je6ekl4 -->
  - New Scramble/Scramble/Timeline/PhaseDateMapping.swift with dateRange, durationDays, isCompressed static functions
  - Pure value-type, nonisolated where possible
  - Blocked-by: je6ekl3 (Write PhaseDateMapping tests)
  - Stream: 2
  - Requirements: [3.1](requirements.md#3.1), [3.3](requirements.md#3.3)
  - References: specs/phase-3-timeline-tasks/design.md

- [x] 7. Write ConditionsFormatter tests <!-- id:je6ekl5 -->
  - New ScrambleTests/Explainability/ConditionsFormatterTests.swift
  - Cover: AND across attribute types joined by ' + '; OR within attribute type joined by ' or '; iteration order matches TripAttribute.allCases (test with reversed insertion order); empty intersection returns empty string
  - Stream: 2
  - Requirements: [8.4](requirements.md#8.4)
  - References: specs/phase-3-timeline-tasks/design.md, Scramble/Scramble/Models/Conditions.swift

- [x] 8. Implement ConditionsFormatter <!-- id:je6ekl6 -->
  - New Scramble/Scramble/Explainability/ConditionsFormatter.swift
  - Static format(_ conditions: Conditions, against attributes: TripAttributes) -> String
  - Iterate TripAttribute.allCases for deterministic order
  - Blocked-by: je6ekl5 (Write ConditionsFormatter tests)
  - Stream: 2
  - Requirements: [8.4](requirements.md#8.4)
  - References: specs/phase-3-timeline-tasks/design.md

- [x] 9. Write task ordering and PhaseCounts tests <!-- id:je6ekl7 -->
  - New ScrambleTests/Timeline/TaskListOrderingTests.swift covering Req 5.1 four-group order and Req 5.2 case-insensitive name sort (include mixed-case + non-ASCII fixtures)
  - New ScrambleTests/Timeline/PhaseCountsTests.swift covering Req 5.3 subline format including +N inactive; zero-matching, zero-inactive, all-completed edge cases
  - Stream: 2
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3)
  - References: specs/phase-3-timeline-tasks/design.md

- [x] 10. Implement task ordering and PhaseCounts helpers <!-- id:je6ekl8 -->
  - Add ordering and counts as static helpers in Scramble/Scramble/Timeline/TaskListHelpers.swift (or as TaskListSection private static funcs)
  - Sort comparator uses localizedCaseInsensitiveCompare for name tiebreaker
  - PhaseCounts is struct { let completed: Int; let total: Int; let inactive: Int }
  - Blocked-by: je6ekl7 (Write task ordering and PhaseCounts tests)
  - Stream: 2
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3)
  - References: specs/phase-3-timeline-tasks/design.md

- [x] 11. Write WhyResolver tests <!-- id:je6ekl9 -->
  - New ScrambleTests/Explainability/WhyResolverTests.swift
  - In-memory ModelContainer; cover all four Reason branches (manual, ruleMasterDeleted, ruleMatched, ruleNoLongerMatches)
  - Regression case: call resolver twice with mutated trip attributes between calls; assert second call reflects new state
  - Blocked-by: je6ekl0 (Refactor TripTask into SchemaV1/SchemaV2 namespaces, add migration stage and typealias)
  - Stream: 2
  - Requirements: [8.4](requirements.md#8.4), [8.5](requirements.md#8.5), [8.6](requirements.md#8.6), [8.7](requirements.md#8.7)
  - References: specs/phase-3-timeline-tasks/design.md

- [x] 12. Implement WhyResolver <!-- id:je6ekla -->
  - New Scramble/Scramble/Explainability/WhyResolver.swift
  - Static reason(for task: TripTask, context: ModelContext) -> WhyDisclosure.Reason
  - Use ConditionsFormatter for the ruleMatched conditionsText
  - Blocked-by: je6ekl6 (Implement ConditionsFormatter), je6ekl9 (Write WhyResolver tests)
  - Stream: 2
  - Requirements: [8.4](requirements.md#8.4), [8.5](requirements.md#8.5), [8.6](requirements.md#8.6), [8.7](requirements.md#8.7), [8.9](requirements.md#8.9)
  - References: specs/phase-3-timeline-tasks/design.md

- [x] 13. Write TripDetailView.autoExpandPhase tests <!-- id:je6eklb -->
  - New ScrambleTests/Trips/AutoExpandTests.swift
  - Cover: returns .current phase for normal trip; returns nil when current phase is non-expandable (no tasks, not packing); returns nil when current phase is compressed (.duringTrip + zero duration)
  - Blocked-by: je6ekl4 (Implement PhaseDateMapping helper), je6ekl8 (Implement task ordering and PhaseCounts helpers)
  - Stream: 2
  - Requirements: [2.3](requirements.md#2.3), [2.5](requirements.md#2.5), [3.2](requirements.md#3.2)
  - References: specs/phase-3-timeline-tasks/design.md

- [x] 14. Implement TripDetailView.autoExpandPhase static helper <!-- id:je6eklc -->
  - Add static func autoExpandPhase(for trip: Trip, today: Date, calendar: Calendar) -> Phase? to TripDetailView
  - Uses existing state(for:today:start:end:calendar) to find .current phase, then checks expandability via PhaseDateMapping.isCompressed and task presence
  - Blocked-by: je6eklb (Write TripDetailView.autoExpandPhase tests)
  - Stream: 2
  - Requirements: [2.3](requirements.md#2.3)
  - References: specs/phase-3-timeline-tasks/design.md, Scramble/Scramble/Features/Trips/TripDetailView.swift

- [x] 15. Implement PhaseNode and CompressedSpineDot; delete PhaseNodeMarker <!-- id:je6ekld -->
  - New Scramble/Scramble/Components/PhaseNode.swift with full PhaseNode (24/28pt diameter, glow ring on .current via dual shadow, packing glyphs for departure/repack inside .future/.current when isPackingPhase)
  - New Scramble/Scramble/Components/CompressedSpineDot.swift (4pt dot at reduced opacity)
  - NOW pill owned by PhaseRow header, not by PhaseNode
  - Reuse existing PhaseNodeState enum from Models/Enums.swift
  - Delete Scramble/Scramble/Components/PhaseNodeMarker.swift only after task 22 has removed its caller in phaseSpine()
  - Blocked-by: je6ekl2 (Implement engine carve-out for userDeletedOnThisTrip), je6ekla (Implement WhyResolver), je6eklc (Implement TripDetailView.autoExpandPhase static helper)
  - Stream: 3
  - Requirements: [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [3.1](requirements.md#3.1), [3.4](requirements.md#3.4)
  - References: specs/phase-3-timeline-tasks/design.md, Scramble/Scramble/Components/PhaseNodeMarker.swift, docs/scramble-ui-design-doc.md

- [x] 16. Implement WhyDisclosure view <!-- id:je6ekle -->
  - New Scramble/Scramble/Explainability/WhyDisclosure.swift
  - Renders four Reason cases per UI doc §Visual treatment — Tasks context (phase colour 8% bg, 1pt border at 20%, 9pt 700 uppercase header in phase colour)
  - Equatable conformance on Reason for .onChange usage in TaskRow
  - Blocked-by: je6ekla (Implement WhyResolver)
  - Stream: 3
  - Requirements: [8.4](requirements.md#8.4), [8.5](requirements.md#8.5), [8.6](requirements.md#8.6), [8.7](requirements.md#8.7), [8.8](requirements.md#8.8)
  - References: specs/phase-3-timeline-tasks/design.md, docs/scramble-ui-design-doc.md

- [x] 17. Implement TaskRow and TaskListSection <!-- id:je6eklf -->
  - New Scramble/Scramble/Components/TaskRow.swift and TaskListSection.swift
  - TaskRow: 14pt PersonAvatar via existing component; checkbox per UI doc §Checkbox colour rules (tasks context); long-press on body region (excluding checkbox/avatar) triggers WhyResolver lookup cached in @State, refreshed on .onChange(of: task.trip?.attributesData) and .onChange(of: task.name); swipe trailing reveals Edit and Delete (destructive); contextMenu mirrors both; opacity stacking 0.5 (completed) × 0.45 (unmatched-non-pinned)
  - TaskListSection: filters trip.tasks by phase and userDeletedOnThisTrip == false, sorts via helper from task 10, renders TaskRow per task plus AddTaskAffordance; checkbox toggle wrapped in withAnimation(.none) to prevent sort-jump; .animation(.easeInOut(0.2), value: task.isCompleted) for fade
  - Accessibility: custom rotor actions 'Why is this here?', Edit, Delete on each row
  - Blocked-by: je6ekl8 (Implement task ordering and PhaseCounts helpers), je6ekla (Implement WhyResolver), je6ekle (Implement WhyDisclosure view)
  - Stream: 3
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.7](requirements.md#4.7), [4.8](requirements.md#4.8), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3), [10.2](requirements.md#10.2), [10.3](requirements.md#10.3), [10.4](requirements.md#10.4)
  - References: specs/phase-3-timeline-tasks/design.md, Scramble/Scramble/Components/PersonAvatar.swift, docs/scramble-ui-design-doc.md

- [x] 18. Implement PhaseRow <!-- id:je6eklg -->
  - New Scramble/Scramble/Components/PhaseRow.swift, generic over Content: View (no AnyView)
  - Composes PhaseNode or CompressedSpineDot, header (label + NOW pill + subline using PhaseCounts), conditional expanded content
  - Owns VoiceOver label via private phaseAccessibilityLabel(phase, state, counts); appends 'double tap to expand' only when expandable
  - Phase tap target 44pt min; compressed row has no .onTapGesture
  - Blocked-by: je6ekl8 (Implement task ordering and PhaseCounts helpers), je6ekld (Implement PhaseNode and CompressedSpineDot; delete PhaseNodeMarker), je6eklf (Implement TaskRow and TaskListSection)
  - Stream: 3
  - Requirements: [1.1](requirements.md#1.1), [1.6](requirements.md#1.6), [1.7](requirements.md#1.7), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6), [3.2](requirements.md#3.2), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [5.4](requirements.md#5.4), [10.1](requirements.md#10.1), [10.4](requirements.md#10.4)
  - References: specs/phase-3-timeline-tasks/design.md, Scramble/Scramble/Theme/MidnightAtlas.swift

- [x] 19. Implement AccordionTimeline <!-- id:je6eklh -->
  - New Scramble/Scramble/Features/Trips/AccordionTimeline.swift
  - Owns ScrollViewReader; renders PhaseRow per Phase.allCases
  - Per toggle: mutate expandedPhase inside withAnimation block, emit medium-impact haptic, call proxy.scrollTo(phase, anchor: .top) inside same withAnimation
  - Auto-expand on .task re-runs autoExpandPhase (Req 2.3); no persistence
  - Blocked-by: je6eklc (Implement TripDetailView.autoExpandPhase static helper), je6eklg (Implement PhaseRow)
  - Stream: 3
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.7](requirements.md#2.7)
  - References: specs/phase-3-timeline-tasks/design.md

- [x] 20. Implement TaskForm (add + edit modes) <!-- id:je6ekli -->
  - New Scramble/Scramble/Features/Trips/TaskForm.swift with Mode enum (.add(phase) / .edit(task))
  - Fields: TextField (200-char cap via .onChange), Picker over trip.participants
  - WHEN trip.participants is empty: render non-interactive 'No participants yet — add people on the trip details screen' message; form remains submittable with assignee unset
  - Save disabled when trimmed name is empty
  - On submit (.add): create TripTask with source: .manual, currentlyMatchesRules: true, userDeletedOnThisTrip: false, masterItemID: nil; (.edit): update name + assigneePersonID on existing record
  - Does NOT use @Query
  - Blocked-by: je6ekl0 (Refactor TripTask into SchemaV1/SchemaV2 namespaces, add migration stage and typealias)
  - Stream: 3
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5), [6.6](requirements.md#6.6), [6.7](requirements.md#6.7), [7.2](requirements.md#7.2)
  - References: specs/phase-3-timeline-tasks/design.md

- [x] 21. Write UI tests: accordion, task interactions, forms, accessibility <!-- id:je6eklj -->
  - Extend Scramble/ScrambleUITests/ with: testAccordionAutoExpandsCurrentPhase, testOnlyOnePhaseExpandedAtATime, testCompressedDuringTripIsNotTappable, testCheckboxToggleAndStrikethrough, testLongPressOpensWhyDisclosure, testOnlyOneDisclosureOpenAtATime, testTapElsewhereDismissesDisclosure, testSwipeRevealsEditAndDelete, testManualTaskAddPersistsAcrossLaunch, testRuleDeletionPersistsAcrossReevaluation, testAssigneePickerEmptyParticipants, testSublineWrapsAtAX2
  - New accessibility IDs: tripDetail.phaseNode.{phase}, tripDetail.phaseHeader.{phase}, tripDetail.accordion.expanded, tripDetail.addTaskButton.{phase}, tripDetail.whyDisclosure.{taskName}
  - Use existing launch-arg fixture pattern (-uitest, seed args)
  - Reuse existing serialized-runner setting (-parallel-testing-worker-count 1)
  - Blocked-by: je6eklh (Implement AccordionTimeline), je6ekli (Implement TaskForm (add + edit modes))
  - Stream: 4
  - Requirements: [1.3](requirements.md#1.3), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.2](requirements.md#3.2), [4.3](requirements.md#4.3), [4.7](requirements.md#4.7), [5.4](requirements.md#5.4), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.5](requirements.md#6.5), [7.1](requirements.md#7.1), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3), [10.4](requirements.md#10.4), [10.5](requirements.md#10.5)
  - References: specs/phase-3-timeline-tasks/design.md, Scramble/ScrambleUITests/

- [x] 22. Wire AccordionTimeline and TaskForm into TripDetailView <!-- id:je6eklk -->
  - Replace phaseSpine() body in TripDetailView with AccordionTimeline(trip:today:expandedPhase:openDisclosureTaskID:onAddTaskInPhase:onEditTask:)
  - Add @State: expandedPhase, openDisclosureTaskID, pendingForm (with TaskFormPresentation enum)
  - Add custom init(trip: Trip, today: Date = .now) initialising _expandedPhase via State(initialValue: Self.autoExpandPhase(...))
  - .sheet(item: $pendingForm) presents TaskForm
  - Delete obsolete phaseSpine() and helpers; delete PhaseNodeMarker.swift
  - Make all UI tests from task 21 pass
  - Blocked-by: je6eklj (Write UI tests: accordion, task interactions, forms, accessibility)
  - Stream: 4
  - Requirements: [1.1](requirements.md#1.1), [2.3](requirements.md#2.3), [6.1](requirements.md#6.1)
  - References: specs/phase-3-timeline-tasks/design.md, Scramble/Scramble/Features/Trips/TripDetailView.swift
