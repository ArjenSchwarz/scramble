# Design: Phase 3 — Timeline + Tasks

## Overview

Replaces the seven static phase markers in `TripDetailView` with an expandable accordion timeline. Adds per-phase task rows, manual task creation, edit/delete affordances, and the cross-phase `WhyDisclosure` component. Introduces `TripTask.assigneePersonID` and `TripTask.userDeletedOnThisTrip` via `SchemaV2`, and a small rules-engine carve-out so user-deleted rule tasks are not re-created.

## Architecture

### State ownership

All transient UI state lives in `TripDetailView`:

```swift
@State private var expandedPhase: Phase?     // accordion selection
@State private var openDisclosureTaskID: UUID?  // single open WhyDisclosure per timeline
@State private var pendingForm: TaskFormPresentation?

enum TaskFormPresentation: Identifiable {
  case add(phase: Phase)
  case edit(task: TripTask)
  var id: String {
    switch self {
    case .add(let phase): return "add-\(phase.rawValue)"
    case .edit(let task): return "edit-\(task.id.uuidString)"
    }
  }
}
```

`TripDetailView` provides a custom `init(trip: Trip, today: Date = .now)` so the initial `@State` values can be derived synchronously:

```swift
init(trip: Trip, today: Date = .now) {
  self.trip = trip
  self.today = today
  let initial = Self.autoExpandPhase(for: trip, today: today, calendar: .current)
  _expandedPhase = State(initialValue: initial)
}

private static func autoExpandPhase(for trip: Trip, today: Date, calendar: Calendar) -> Phase? {
  // Use existing TripDetailView.state(for:today:start:end:calendar) to find
  // the .current phase; return nil if it's non-expandable (no tasks AND not a
  // packing phase, or compressed per PhaseDateMapping.isCompressed).
}
```

This avoids the one-frame flash of `expandedPhase == nil` on cold launch. The `.task` modifier on the view re-runs `autoExpandPhase` on every appearance (Req [2.3](requirements.md#2.3)) so a user returning days later sees the new current phase. `today` defaults to `Date.now`; tests pass a fixed `today` for determinism.

SwiftUI's `.task` modifier fires on the view's appear lifecycle event — it does **not** re-fire when a presented `.sheet` is dismissed (the underlying view never disappears), so opening "+ Add task", saving, and dismissing does not reset the user's manual phase selection. The auto-expand only re-runs on a true navigation cycle (nav-out and nav-back, or app cold launch), which matches Decision 4's "on every appearance of Trip Detail" intent.

`openDisclosureTaskID` clears whenever `expandedPhase` changes (per Req [8.3](requirements.md#8.3) — disclosure dismissal on tap-elsewhere is realised as collapse-on-phase-change plus an explicit tap handler on the phase's task-list container). The disclosure reason itself is recomputed on every body evaluation by `WhyResolver`; an already-open disclosure reflects the current trip attributes immediately rather than holding a snapshot from open-time.

Persisted state — `isCompleted`, `pinnedByUser`, `assigneePersonID`, `userDeletedOnThisTrip`, and the row's `name` — is written directly to the `TripTask` instance through the `@Environment(\.modelContext)`. No view model layer; this matches `TripEditorView`'s convention.

### Integration with TripDetailView

`phaseSpine()` (lines 210–247) is replaced with `AccordionTimeline`, which renders one `PhaseRow` per `Phase.allCases`. The existing sticky header, chip row, and `state(for:today:start:end:calendar)` helper are unchanged. Debug accessibility markers (lines 100–131) are kept for UI-test stability and extended with new IDs for accordion state.

```
TripDetailView
├── Header (unchanged)
├── ChipRow (unchanged)
└── AccordionTimeline           ← NEW; replaces phaseSpine()
    └── PhaseRow × 7
        ├── PhaseNode | CompressedSpineDot
        ├── PhaseHeader (label, NOW pill, subline counts)
        └── PhaseContent (visible only when this phase == expandedPhase)
            ├── TaskRow × N (sorted per Req 5.1)
            └── AddTaskAffordance
```

`AccordionTimeline` wraps the rendering in a `ScrollViewReader`; when `expandedPhase` changes, it issues `proxy.scrollTo(phase, anchor: .top)` inside the same `withAnimation` block that mutates `expandedPhase` (Req [2.4](requirements.md#2.4)). Sequencing the scroll inside the animation block — rather than firing it after the state change settles — avoids the known iOS jank where `scrollTo` runs before the accordion's height delta is committed.

### Integration with rules engine

Three changes — the gate is in `classifyTaskRefs`, not in `referencedMasterIDs`:

| File | Change | Reason |
|---|---|---|
| `RulesEngine/Snapshots.swift` (`TripTaskRef`) | Add `userDeletedOnThisTrip: Bool` to the value snapshot, populate from `TripTask.userDeletedOnThisTrip` at every snapshot construction site | `compute` and any downstream consumer must see the flag |
| `RulesEngine/Compute.swift` `classifyTaskRefs` | At the top of the loop, `guard !ref.userDeletedOnThisTrip else { continue }` — deleted refs neither flip to unmatched nor flip to matched | This is the actual gate keeping deleted rule tasks inert; without it, a master that toggles match-state would re-surface a deleted row as either dimmed (false→true) or normal (true→false) |
| `RulesEngine/Apply.swift` `flagTasks` | After fetching by ID, skip any `TripTask` whose `userDeletedOnThisTrip == true` before writing `currentlyMatchesRules` | Race-safe against snapshot-vs-store divergence (e.g., a sync arrival flipped the deletion flag after the snapshot was captured) |

`referencedMasterIDs(in:)` is **not changed**: it already inserts every `masterItemID` from `trip.existingTasks` unconditionally, so deleted refs are already counted as "referenced" and never appear in `toAddTasks`. The previous draft of this section misframed `referencedMasterIDs` as the gate; the real gate is the `classifyTaskRefs` skip plus the `apply` belt-and-braces guard. `insertAddedTasks` is unaffected — the engine never creates new tasks with the flag set; the flag is set only by Phase 3 UI on existing records.

### Schema migration

SwiftData's `MigrationStage.lightweight` compares model metadata between versioned schemas; if both versions point at the same Swift type, there is no diff to migrate. Each `VersionedSchema` must therefore namespace its own model types. Phase 3 introduces `SchemaV2.TripTask` as a distinct `@Model` type (with the two new properties), with the existing class refactored into `SchemaV1.TripTask` and frozen there:

```swift
nonisolated enum SchemaV1: VersionedSchema {
  static var versionIdentifier: Schema.Version { .init(1, 0, 0) }

  @Model final class TripTask {
    // Pre-Phase-3 shape, frozen
    var id: UUID = UUID()
    @Relationship var trip: Trip?
    var masterItemID: UUID?
    var name: String = ""
    var phaseRaw: String = Phase.weeksBefore.rawValue
    var isCompleted: Bool = false
    var sourceRaw: String = ItemSource.manual.rawValue
    var currentlyMatchesRules: Bool = true
    var pinnedByUser: Bool = false
  }

  static var models: [any PersistentModel.Type] { [..., TripTask.self] }
}

nonisolated enum SchemaV2: VersionedSchema {
  static var versionIdentifier: Schema.Version { .init(2, 0, 0) }

  @Model final class TripTask {
    // Phase 3 shape — adds assigneePersonID and userDeletedOnThisTrip
    var id: UUID = UUID()
    @Relationship var trip: Trip?
    var masterItemID: UUID?
    var name: String = ""
    var phaseRaw: String = Phase.weeksBefore.rawValue
    var isCompleted: Bool = false
    var sourceRaw: String = ItemSource.manual.rawValue
    var currentlyMatchesRules: Bool = true
    var pinnedByUser: Bool = false
    var assigneePersonID: UUID? = nil
    var userDeletedOnThisTrip: Bool = false
  }

  static var models: [any PersistentModel.Type] { [..., TripTask.self] }
}

typealias TripTask = SchemaV2.TripTask

nonisolated enum AppMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
  static var stages: [MigrationStage] {
    [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
  }
}
```

The two other Phase-1 models touched by Phase 3 (`Trip`, `Person`, `MasterTaskItem`, `MasterPackingItem`, `TripPackingItem`) are unchanged at the schema-shape level, but each `VersionedSchema` must list them with its own model references. Migration of those is lightweight no-op.

Test containers run the migration against a real on-disk store (a temporary SQLite file) — not `isStoredInMemoryOnly`. In-memory containers initialise the schema fresh and would never exercise the V1 → V2 transition, so the migration test seeds a V1 store on disk, opens it with the `AppMigrationPlan` configured for `SchemaV2`, and asserts the new fields are present with their defaults.

## Components and Interfaces

### `PhaseNode` (replaces `PhaseNodeMarker`)

```swift
struct PhaseNode: View {
  let phase: Phase
  let state: PhaseNodeState
  let isPackingPhase: Bool
  let phaseColour: Color
}
```

`PhaseNodeState` already exists in `Models/Enums.swift` with cases `.past`, `.current`, `.future` (introduced in Phase 1 alongside `PhaseNodeMarker`); it is reused without change. The mapping from `(Trip, today, Phase)` to `PhaseNodeState` is computed by the existing `TripDetailView.state(for:today:start:end:calendar)` static helper. States and visuals follow UI doc §"Phase node visual states". Diameter: 24pt future, 28pt current (the 4pt delta accommodates the glow ring). The 44pt touch target (Req 1.7 / 10.4) is supplied by the surrounding `PhaseRow` and split across both columns: the left column wraps `PhaseNode` in a `44×44` frame with its own `TapToToggleModifier`, and the right column's header carries the same tap modifier. Tapping the circle and tapping the label are interchangeable; neither inflates the visible circle. `PhaseNodeMarker` is deleted; no other site references it.

### `CompressedSpineDot`

```swift
struct CompressedSpineDot: View {
  let phaseColour: Color  // rendered at reduced opacity per Req 3.4
}
```

A 4pt circle on the 2pt spine. No header, no tap target. Used by `PhaseRow` when `PhaseDateMapping.isCompressed(phase, trip:)` is true.

### `PhaseDateMapping` (helper, value type)

```swift
enum PhaseDateMapping {
  static func dateRange(_ phase: Phase, for trip: Trip, calendar: Calendar) -> ClosedRange<Date>?
  static func durationDays(_ phase: Phase, for trip: Trip, calendar: Calendar) -> Int  // -1 = open-ended
  static func isCompressed(_ phase: Phase, for trip: Trip, calendar: Calendar) -> Bool
}
```

Implements the canonical mapping in requirements.md §"Trip-date-to-phase-date mapping". `isCompressed` is true iff `phase == .duringTrip && durationDays == 0`. Unit-testable as a pure function over `Trip` (the function reads only `startDate`/`endDate`).

### `PhaseRow`

```swift
struct PhaseRow<Content: View>: View {
  let phase: Phase
  let state: PhaseNodeState
  let counts: PhaseCounts          // {completed: Int, total: Int, inactive: Int}
  let isExpanded: Bool
  let isCompressed: Bool
  let onToggle: () -> Void
  @ViewBuilder let content: () -> Content
}
```

`PhaseCounts` is a plain value type computed by a private helper on `TaskListSection` (`func counts() -> PhaseCounts`); there is no separate view-model layer. The row renders the spine segment, the node (or compressed dot), the header (label + NOW pill + subline), and conditionally the expanded content. Tap target on the row is gated by `isExpanded` rules in Req [2.5](requirements.md#2.5)/[2.6](requirements.md#2.6); a compressed row has no `.onTapGesture`. Generic `Content` parameter is used (not `AnyView`) per the project's Swift performance rules.

`PhaseRow` is also the owner of the VoiceOver label for the phase node per Req [10.1](requirements.md#10.1). The label string is built by a private helper `phaseAccessibilityLabel(phase, state, counts)` and attached via `.accessibilityElement(children: .combine)` plus `.accessibilityLabel(...)` on the tappable region. The trailing "double tap to expand" clause is appended only when the row is expandable (per Req [2.5](requirements.md#2.5) / [2.6](requirements.md#2.6) / [3.2](requirements.md#3.2)).

### `TaskListSection` (per-phase content)

```swift
struct TaskListSection: View {
  let trip: Trip
  let phase: Phase
  let openDisclosureTaskID: Binding<UUID?>
  let onAdd: () -> Void
  let onEdit: (TripTask) -> Void
}
```

Reads `trip.tasks` filtered to `phase == self.phase && userDeletedOnThisTrip == false`, sorts in memory per Req [5.1](requirements.md#5.1), and renders one `TaskRow` per task plus the `AddTaskAffordance`. In-memory sort (not a `@Query` predicate) because the ordering involves three booleans (`currentlyMatchesRules || pinnedByUser`, `isCompleted`, name) that SwiftData predicates cannot express cleanly. Sort comparators use `localizedCaseInsensitiveCompare` for the name tiebreaker (Req [5.2](requirements.md#5.2)).

`@Query` is intentionally not used because the natural filter (per-trip + per-phase + not-deleted + complex sort) is awkward to express, and `trip.tasks` is already observed by SwiftUI through the parent `Trip` instance's `@Relationship(deleteRule: .cascade)` collection. Verification task: confirm SwiftUI re-renders `TaskListSection` when `trip.tasks` is mutated (e.g., when a task is inserted or its `isCompleted` flips). If not, fall back to `@Query`.

Sort-induced row jumps when `isCompleted` toggles are suppressed by wrapping the sort-key recomputation outside the implicit `withAnimation` of the checkbox toggle: the checkbox calls `withAnimation(.none) { task.isCompleted.toggle() }`, so the row's place in the sort updates without an animated cross-fade. The fade-to-50%-opacity from Req [4.3](requirements.md#4.3) runs as a separate `.animation(.easeInOut(duration: 0.2), value: task.isCompleted)` modifier on the row body, isolating the visual fade from the layout sort.

### `TaskRow`

```swift
struct TaskRow: View {
  let task: TripTask
  let phaseColour: Color
  let isDisclosureOpen: Bool
  let onToggleComplete: () -> Void
  let onLongPress: () -> Void
  let onEdit: () -> Void
  let onDelete: () -> Void
}
```

Layout: 14pt avatar (right) reuses `PersonAvatar.compact`. Checkbox uses the existing project pattern (cf. UI doc §"Checkbox"). Long-press is attached to the row content (not the row container) and excludes the checkbox tap region per Req [8.1](requirements.md#8.1). `swipeActions(edge: .trailing)` exposes "Edit" and "Delete (destructive)"; the same actions are mirrored in a `contextMenu`. VoiceOver custom rotor actions are attached via `.accessibilityCustomContent`/`.accessibilityAction(named:)` for "Why is this here?", "Edit", "Delete".

Dimming for unmatched-non-pinned tasks is computed once in a `rowOpacity` property and applied as a single `.opacity` modifier: `0.5` when only `isCompleted`, `0.45` when only `currentlyMatchesRules == false && !pinnedByUser`, and `min(0.5, 0.45) = 0.45` when both apply. Earlier iterations chained two `.opacity` modifiers and ended up at `0.5 × 0.45 = 0.22` for the combined state, which read as broken rather than intentionally muted. `min` is preferred over multiplication because the UI doc only specifies the 50% completed dim; the combined state should not be more aggressive than the dimmer of the two single states, and strikethrough already distinguishes completed.

### `WhyDisclosure`

```swift
struct WhyDisclosure: View {
  enum Reason: Equatable {
    case ruleMatched(conditionsText: String)
    case ruleNoLongerMatches
    case ruleMasterDeleted
    case manual
  }
  let reason: Reason
  let phaseColour: Color
}
```

Visual treatment (background opacity, border, header text style) follows UI doc §"Visual treatment — Tasks context" verbatim; the component owns the rendering. The `Equatable` conformance on `Reason` is used by `.onChange(of: resolvedReason)` in `TaskRow` to trigger SwiftUI updates when the resolver re-runs.

The reason is computed by `WhyResolver`:

```swift
enum WhyResolver {
  static func reason(for task: TripTask, context: ModelContext) -> WhyDisclosure.Reason
}
```

Resolution rules (Req [8.4](requirements.md#8.4)–[8.7](requirements.md#8.7)):

| `task.source` | `masterItemID` lookup | `conditions.evaluate(against: trip.attributes)` | Reason |
|---|---|---|---|
| `.manual` | — | — | `.manual` |
| `.rule` | nil or not found | — | `.ruleMasterDeleted` |
| `.rule` | found, matches | true | `.ruleMatched(text)` |
| `.rule` | found, no match | false | `.ruleNoLongerMatches` |

`conditionsText` is built by `ConditionsFormatter.format(_ conditions: Conditions, against attributes: TripAttributes) -> String`. This is the function Phase 2 Decision 6 deferred to Phase 3. Formatting joins attribute-type groups with `" + "` and values within a group with `" or "` per UI doc §"Explainability — Behaviour". Attribute-type ordering follows `TripAttribute.allCases` (the canonical Phase 1 enum order) so output is deterministic across runs and devices.

To avoid a `ModelContext` lookup on every SwiftUI body evaluation, `WhyResolver` is called **once** when a disclosure opens. The resolved `Reason` is stored in a small per-row `@State`:

```swift
struct TaskRow: View {
  // ...
  @State private var resolvedReason: WhyDisclosure.Reason?
}
```

When `isDisclosureOpen` flips from `false` to `true` (`.onChange(of: isDisclosureOpen)`), `WhyResolver.reason(for:context:)` runs once and the result is cached in `resolvedReason`. The cached reason is invalidated by `.onChange(of: task.trip?.attributesData)` and `.onChange(of: task.name)` so that an open disclosure reflecting trip-attribute or rule-source edits refreshes promptly without polling. Closing the disclosure clears `resolvedReason`. This satisfies "open disclosure reflects current trip attributes" without per-body fetches.

### `AddTaskSheet` / `EditTaskSheet`

A single SwiftUI view `TaskForm` with a `Mode` enum (`.add(phase: Phase)` / `.edit(task: TripTask)`). Presented via `.sheet(item: $pendingForm)`. Fields: name (`TextField`, 200-char cap enforced by `.onChange`), assignee picker (`Picker` populated from `trip.participants`). The empty-participants state (Req [6.2](requirements.md#6.2)) renders a `Text` placeholder instead of the Picker. Save disabled when trimmed name is empty (Req [6.4](requirements.md#6.4)).

The form does not subscribe to `@Query`; trip task changes from a concurrent rules-engine run cannot mutate form state mid-edit (Req [6.7](requirements.md#6.7)).

### `AccordionTimeline`

```swift
struct AccordionTimeline: View {
  let trip: Trip
  let today: Date
  @Binding var expandedPhase: Phase?
  @Binding var openDisclosureTaskID: UUID?
  let onAddTaskInPhase: (Phase) -> Void
  let onEditTask: (TripTask) -> Void
}
```

Owns the `ScrollViewReader`. Each `PhaseRow.onToggle` calls back into `AccordionTimeline`, which is the single site that mutates `expandedPhase` and fires the medium-impact `UIImpactFeedbackGenerator(style: .medium)` (Req [2.7](requirements.md#2.7)) — `PhaseRow` itself emits no haptics. The current-phase auto-expand initialiser uses the existing `TripDetailView.state(for:today:start:end:calendar)` static helper to map `today` → `Phase`; the `.task` modifier re-runs the same logic on subsequent appearances. A non-expandable current phase (no tasks AND not a packing phase, or compressed) leaves `expandedPhase = nil`.

## Data Models

### `TripTask` additions

```swift
var assigneePersonID: UUID? = nil
var userDeletedOnThisTrip: Bool = false
```

Both fields default-safe for lightweight migration. `assigneePersonID` is a plain `UUID?` (Decision 9) — not a `@Relationship` — so dangling references are tolerated by construction (Req [4.8](requirements.md#4.8), Req [9.4](requirements.md#9.4)).

### `TripTaskRef` snapshot update

```swift
struct TripTaskRef: Hashable, Sendable {
  let id: UUID
  let masterItemID: UUID?
  let source: ItemSource
  let currentlyMatchesRules: Bool
  let pinnedByUser: Bool
  let isCompleted: Bool
  let userDeletedOnThisTrip: Bool   // NEW
}
```

Snapshot construction in the trigger call sites (per Phase 2 Decision 5) gains a single new field copy.

## Error Handling

| Failure mode | Surface | Behaviour |
|---|---|---|
| `assigneePersonID` references missing/removed `Person` | `TaskRow` | Avatar omitted; no error UI (Req [4.8](requirements.md#4.8)) |
| `masterItemID` points to deleted `MasterTaskItem` | `WhyDisclosure` | `.ruleMasterDeleted` reason; no error UI (Req [8.6](requirements.md#8.6)) |
| Manual task save with empty trimmed name | `AddTaskSheet` | Save button disabled; no error alert (Req [6.4](requirements.md#6.4)) |
| Subline cannot fit at AX2 | `PhaseHeader` | Wraps to second line; `+{N} inactive` may move independently (Req [5.4](requirements.md#5.4)) |
| Concurrent rules-engine run during edit | `TaskForm` | Form unaffected; task-list updates apply post-dismiss (Req [6.7](requirements.md#6.7)) |
| Compressed phase with attached tasks (e.g., after date edit) | `AccordionTimeline` | Tasks not surfaced; data preserved (Non-Goal: no recovery affordance) |

No new alert dialogs, no destructive-confirm flow for deletion (deletion is destructive but quick to redo via "+ Add task" — undo is explicitly Non-Goal).

## Testing Strategy

### Unit tests (Swift Testing, `ScrambleTests/`)

| Suite | Coverage |
|---|---|
| `PhaseDateMappingTests` | Mapping table: each `Phase` × representative `(start, end)` pairs; `isCompressed` true iff `phase == .duringTrip && (E − S) − 1 == 0`; PBT candidate: property "non-`duringTrip` phases are never compressed" over random `(start, end)` pairs |
| `TaskListOrderingTests` | Req [5.1](requirements.md#5.1) order over four groups; Req [5.2](requirements.md#5.2) case-insensitive name comparison verified with mixed-case fixtures including non-ASCII letters; PBT candidate over random task lists |
| `PhaseCountsTests` | Req [5.3](requirements.md#5.3) subline format including `+N inactive` clause; edge cases: zero matching, zero inactive, all completed |
| `WhyResolverTests` | All four `Reason` branches; uses in-memory `ModelContainer`. Includes a test that calls `WhyResolver.reason` repeatedly with the same `(task, context)` and asserts that fetching is not done in a tight loop (mutate a fixture and confirm the resolver picks up the new state on the next call) |
| `ConditionsFormatterTests` | Join behaviour: AND across types, OR within a type; iteration order matches `TripAttribute.allCases`; empty intersection returns empty string |
| `ComputeUserDeletedTests` (extends Phase 2's `ComputeTests`) | `userDeletedOnThisTrip == true` skips the ref in `classifyTaskRefs` regardless of `(currentlyMatchesRules, matches)` quadrant; `referencedMasterIDs` is unchanged behaviourally (deleted refs were already counted as referenced) |
| `ApplyUserDeletedTests` | A `toFlagMatched` entry whose target record has `userDeletedOnThisTrip == true` is no-op'd in `flagTasks` (snapshot/store divergence race) |
| `PerTripScopeTests` | Req [7.5](requirements.md#7.5): deleting a rule task on trip A leaves the same master matching and present on trip B; uses two `Trip` fixtures in one in-memory container |
| `RenameLocalScopeTests` | Req [7.6](requirements.md#7.6): renaming a rule-driven `TripTask` does not mutate the source `MasterTaskItem`'s `name` |
| `DanglingAssigneeTests` | Req [4.8](requirements.md#4.8) / Req [9.4](requirements.md#9.4): set `assigneePersonID`, delete the `Person`; `TripTask` survives; `TaskRow` snapshot (via `_printChanges` or a render harness) shows no avatar |
| `AutoExpandTests` | `TripDetailView.autoExpandPhase(for:today:calendar:)` returns the expected phase across the seven mapping rows, returns `nil` for non-expandable current phase, and returns `nil` for a compressed `duringTrip` |
| `SchemaV2MigrationTests` | Round-trip on a real on-disk SQLite store (not in-memory): seed a `SchemaV1` store with one or more pre-Phase-3 `TripTask` records, open with `AppMigrationPlan` configured for `SchemaV2`, verify `assigneePersonID == nil` and `userDeletedOnThisTrip == false` on every migrated record. Additionally assert that the persistent entity name resolved for `SchemaV1.TripTask` and `SchemaV2.TripTask` is identical (`"TripTask"`) — a defence against a future SwiftData behaviour change that would qualify entity names with the enclosing enum and orphan CloudKit records |

PBT framework: SwiftCheck is not currently a project dependency; the two PBT candidates are small enough to implement with hand-rolled randomised inputs in Swift Testing (`@Test(arguments: ...)`). If a future phase pulls in a PBT library, these tests are the migration target.

### UI tests (XCTest, `ScrambleUITests/`)

Accessibility IDs extend the existing `tripDetail.task.{matching|unmatched}.{name}` pattern with:

- `tripDetail.phaseNode.{phase}` — tap target for each phase
- `tripDetail.phaseHeader.{phase}` — subline text assertion
- `tripDetail.accordion.expanded` — value: the currently expanded phase rawValue (or empty)
- `tripDetail.addTaskButton.{phase}` — add affordance per phase
- `tripDetail.whyDisclosure.{taskName}` — visible iff disclosure open

Scenarios:

| Test | Path |
|---|---|
| `testAccordionAutoExpandsCurrentPhase` | Seed trip with `today` mid-trip; assert `accordion.expanded == "duringTrip"` |
| `testOnlyOnePhaseExpandedAtATime` | Tap two phases; assert previous collapses |
| `testCompressedDuringTripIsNotTappable` | Seed 1-day trip; tap the compressed marker; assert no expansion |
| `testCheckboxToggleAndStrikethrough` | Toggle; assert opacity + strikethrough via accessibility state |
| `testLongPressOpensWhyDisclosure` | Long-press; assert disclosure ID present |
| `testSwipeRevealsEditAndDelete` | Trailing-swipe on row; assert Edit + Delete buttons |
| `testManualTaskAddPersistsAcrossLaunch` | Add task; relaunch (existing launch-arg fixture pattern); assert task present and `source == .manual` (via debug marker) |
| `testRuleDeletionPersistsAcrossReevaluation` | Delete a rule-driven task; trigger re-evaluation via scenePhase fixture arg; assert task remains hidden |
| `testAssigneePickerEmptyParticipants` | Open AddTask on a trip with zero participants; assert placeholder message |
| `testOnlyOneDisclosureOpenAtATime` | Long-press task A, then task B; assert task A's disclosure is gone (Req [8.2](requirements.md#8.2)) |
| `testTapElsewhereDismissesDisclosure` | Long-press task A, tap an inert region within the phase; assert disclosure dismissed (Req [8.3](requirements.md#8.3)) |
| `testSublineWrapsAtAX2` | Set Dynamic Type to AX2 via launch arg; phase header with `+N inactive` subline; assert no truncation (Req [5.4](requirements.md#5.4), [10.5](requirements.md#10.5)) |

UI tests run serially per existing Makefile setting (`-parallel-testing-worker-count 1`).
