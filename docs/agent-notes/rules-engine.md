# Rules engine

Three-piece pipeline that keeps trip-level items in sync with master-list authoring: capture → compute → apply. The capture and apply steps are `@MainActor` and touch SwiftData; compute is `nonisolated`, pure, value-type-only and unit-testable without a `ModelContainer`.

## Files

- `Scramble/Scramble/RulesEngine/Snapshots.swift` — `TripSnapshot`, `TripTaskRef`, `TripPackingItemRef`, `MasterTaskSnapshot`, `MasterPackingSnapshot`. All `nonisolated`, `Sendable`, value types. Master snapshots are `Hashable`.
- `Scramble/Scramble/RulesEngine/Plan.swift` — `Plan` (four collections) and `TripItemRef` (kind + id). `Plan.init` enforces the AC 4.9 sort invariant (see Decision 8): callers pass unsorted arrays, the initializer sorts.
- `Scramble/Scramble/RulesEngine/Compute.swift` — `compute(trip:masterTasks:masterPacking:) -> Plan`. Pure function. Implements the 4-way `(currentlyMatchesRules, conditions-evaluate)` matrix and the asymmetric exclusion table.
- `Scramble/Scramble/RulesEngine/Apply.swift` — `@MainActor apply(plan:context:)`. Short-circuits empty plans before any fetch. Insertions, flag updates, and `context.save()` happen here.
- `Scramble/Scramble/RulesEngine/RulesEngineRunner.swift` — orchestrator. Two entry points: `runForTrip(_ trip:)` and `runForAllNonPastTrips(today:calendar:)`. The latter hoists master-list fetches once and reuses them across the trip loop (was the worst-case AC 5.5 bottleneck — see below).

## Compute is pure, container-free

`compute(...)` accepts only value-type inputs (no `@Model`, no `ModelContext`) and returns a value-type `Plan`. This makes the engine's core unit-testable without spinning up SwiftData. `ComputeTests` and `ComputeIdempotenceTests` exercise it directly by constructing snapshots; the integration tests live in `ApplyTests` and `RulesEngineRunnerTests`.

## Exclusion asymmetry — read carefully

Pin, completion, and engagement state protect items from **demotion** (`toFlagUnmatched`) but never from **re-matching** (`toFlagMatched`). The asymmetry is intentional: pinning means "don't take this away when the trip changes"; re-matching means "the master conditions match again, so the rule-driven flag is true again," which the user did not pin against. Tests assert each row of the asymmetry table in `ComputeTests`.

`source == .manual` is the one exception that's symmetric — manual items are invisible to the engine in both directions.

## `userDeletedOnThisTrip` carve-out (Phase 3, Decision 7)

A rule-driven `TripTask` whose user has tapped "Delete" on this trip is **not** removed from the store — it has `userDeletedOnThisTrip = true`. The engine treats such refs as already-handled in both directions:

- `Compute.classifyTaskRefs` guards `!ref.userDeletedOnThisTrip` at the top of the loop, so the ref is never reclassified into `toFlagMatched` or `toFlagUnmatched` regardless of the four-way `(currentlyMatchesRules, master-matches)` quadrant.
- `Apply.flagTasks` defensively skips records whose `userDeletedOnThisTrip == true` before writing `currentlyMatchesRules`. The Apply-side guard is belt-and-braces against a snapshot-vs-store race (e.g., a sync arrival flips the deletion flag after the snapshot was captured).
- `referencedMasterIDs(in:)` is **not** changed: deleted refs are already counted as referenced (they have a `masterItemID`), so they correctly suppress duplicate inserts in `toAddTasks`.

The flag is scoped to a single `TripTask` record — deleting on Trip A does not affect Trip B (verified by `PerTripScopeTests`).

## Compute hardening

- `Dictionary(uniquingKeysWith:)`, not `uniqueKeysWithValues`. A CloudKit sync race can briefly surface two masters with the same UUID; trapping in compute would crash the engine on every re-eval until the duplicate cleared. Tolerated, first-wins.
- `.match(_, anyOf: [])` evaluates `false`. The chip editor can't produce this shape, but a hand-edited blob could; defensive.

## Triggers

| AC | Trigger | Wiring site |
|---|---|---|
| 5.1 | Trip created | `TripListView.swift` `onSave` closure (create) calls `runner.runForTrip(newTrip)` after `context.save()` |
| 5.2 | Trip attributes edited | `TripDetailView.swift` `onSave` closure for the edit sheet, same pattern |
| 5.3 | Master item saved/deleted | `MasterTaskEditor.swift` / `MasterPackingEditor.swift` `runEngineAndDismiss()` calls `runner.runForAllNonPastTrips()` |
| 5.3 | Master packing item copied to other people | `MasterPackingList.swift` `performCopy(...)` also calls `runner.runForAllNonPastTrips()` after the copy save (copy-master-packing-items flow) |
| 5.4 | Cold launch | `ScrambleApp.init()` — runs after `UITestSeed.applyIfRequested(...)`, before `WindowGroup` mounts. Synchronous on purpose to satisfy the Phase 1 auto-open ordering invariant (Phase 1 AC 5.6). |
| 5.7 | Foreground transition | `RootView.swift` `onChange(of: scenePhase)` with a `hasBeenBackgrounded: Bool` latch (see Decision 9) |

Mutate → save → run is the trigger-call ordering invariant. Reversing save and run leaves the engine reading stale state.

## scenePhase carve-out uses `hasBeenBackgrounded`, not `previousScenePhase`

iOS delivers backgrounding as `.background → .inactive → .active` — `.inactive` is the intermediary. `onChange(of: scenePhase)` never observes a direct `.background → .active` edge, so the design's original `previousScenePhase == .background` guard never fires. The implementation latches a `hasBeenBackgrounded: Bool` on `.background` and clears it after firing on the next `.active`. Cold-launch carve-out still holds: the initial `nil → .inactive → .active` sequence never sets the flag. See Decision 9 in the spec's decision log.

## Snapshot capture lives on `RulesEngineRunner`

`TripSnapshot.capture(from: Trip)` is the only place where `@Model` properties are read into snapshots. `@MainActor extension TripSnapshot` adds the factory; the struct itself stays `nonisolated`. Tests construct `TripSnapshot` directly (no `Trip`, no container) — the `@MainActor` decoration on the extension doesn't affect that path.

Master snapshot capture skips `MasterPackingItem.person == nil` and logs `[RulesEngine.skip-orphan-master]`. A nil-person master is a degenerate state with no observable user flow that creates it; the engine refuses to materialise it as a missing-personID snapshot.

## Performance — N×M fetch elimination

The original `runForAllNonPastTrips` shape re-fetched all masters per trip via `runForTrip`. With 20 non-past trips × 200 masters that was 8,000 model materialisations per run, on the main actor, against AC 5.5's 250ms budget. The current shape fetches masters once at the top and passes them into a private `runForTrip(_:masterTasks:masterPacking:)`. The single-trip public entry point keeps the original fetch-then-run shape for editor-driven calls.

`Apply.insertAddedPacking` batch-fetches `Person` with a single `idSet.contains` predicate, then resolves from a `[UUID: Person]` map. Same pattern as `flagTasks` / `flagPacking`.

## Error handling

- `apply` propagates `context.save()` failures (`[RulesEngine.save-failed]`) but logs-and-continues on missing trip / missing person / missing trip-level item.
- `runForAllNonPastTrips` wraps each trip in `do/catch` so one failure doesn't abort the fan-out. The aggregate `[Plan]` contains only successful entries.
- Cold-launch (`ScrambleApp.init`) and scenePhase trigger (`RootView`) both `do/catch` the outer runner call so the failure logs to Console (`[RulesEngine.cold-launch-failed]`, `[RulesEngine.scenePhase-failed]`). Silent `try?` was rejected during pre-push review — see review fix list.

## Why `nonisolated` is everywhere

The project compiles under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Value types inherit MainActor isolation by default, which makes them unusable from `nonisolated` compute. Every value type in `RulesEngine/` and the conditions-editor bridge is marked `nonisolated`; that's the cost of MainActor-default mode, not noise.

## What the engine doesn't do (yet)

- CloudKit sync as a re-evaluation trigger — deferred to the CKShare phase (Decision 4). The scenePhase trigger bounds the cross-device staleness window meanwhile.
- Background-thread execution — family-scale bounds keep all work on the main actor.

## Explainability (Phase 3)

`WhyDisclosure` introspection landed in Phase 3 as a separate two-piece chain that does **not** live in the engine:

- `Scramble/Scramble/Explainability/WhyResolver.swift` — `@MainActor static func reason(for task: TripTask, context: ModelContext) -> WhyDisclosure.Reason`. Fetches the `MasterTaskItem` by ID, evaluates `master.conditions.evaluate(against: trip.attributes)`, and maps to one of four `.manual / .ruleMasterDeleted / .ruleMatched(text) / .ruleNoLongerMatches` cases.
- `Scramble/Scramble/Explainability/ConditionsFormatter.swift` — `nonisolated static func format(_ conditions: ItemConditions, against: TripAttributes) -> String`. Walks the conditions tree, intersects per-attribute master-allowed values with trip-selected values, renders via `attributeValueDisplay`, joins with `" or "` within an attribute type and `" + "` across types in `TripAttribute.allCases` order.

Per Decision 8.9, the matched conditions are **computed on demand** by intersecting the master item's current conditions with the trip's current attributes — never snapshotted at task-creation time. The resolver runs on the main actor because `ModelContext.fetch` is `@MainActor`; the formatter is `nonisolated` because it operates on pure value types.
