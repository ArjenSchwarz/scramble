# Decision Log: Phase 2 Rules Engine

## Decision 1: Conditions editor exposes only the simple per-attribute table in v1

**Date**: 2026-05-11
**Status**: accepted

### Context

`ItemConditions` storage already admits nested `.all` / `.any` groups (Phase 1 design, AC 1.7). The Phase 2 conditions editor could either mirror the full tree shape (giving users a builder for nested groups) or expose only the simple shape the v1 evaluator semantics describe in `docs/scramble-design-doc.md` §3: OR within an attribute, AND across attributes.

### Decision

The v1 conditions editor presents one row per `TripAttribute` with a multi-select chip picker. Selected values within an attribute combine as OR; selections across attributes combine as AND. The persisted shape is either `.always` (no rows selected) or `.all([.match(...), ...])` (one match per non-empty attribute, canonical attribute order).

### Rationale

- Matches the v1 evaluation semantics the design doc commits to.
- No real user demand yet for nested groupings; building the tree builder UI now would dominate the Phase 2 budget without a use case.
- Storage already supports the more complex shape, so adding a tree builder later is purely additive (no migration).
- Round-trip on the simple shape is trivial; round-trip on arbitrary nested trees is a significant editor problem.

### Alternatives Considered

- **Full ItemConditions tree builder**: Rejected — no v1 user demand and adds a tree-building UI that has to handle drag-reorder, group/ungroup, and nested validation.
- **Per-attribute table now + tree builder behind a "Advanced" toggle**: Rejected — splits the editor surface and forces decisions about migrating between the two representations.

### Consequences

**Positive:**

- Editor stays small and focused.
- Round-trip is trivially testable (one `.all([.match, ...])` shape).
- The persisted shape relies on `TripAttribute` declaration order (AC 3.5); the enum is treated as append-only so persisted-condition Equatable comparisons remain stable when new attribute cases are added.

**Negative:**

- Items authored in conditions shapes the v1 editor cannot represent (nested groups, top-level `.any`, `.match` values outside the attribute's current value domain) are read-only in the v1 editor (AC 3.7a/b). Until a future "advanced conditions" editor ships, the only path to re-author is "Reset to simple" (AC 3.7c), which discards the advanced shape and replaces it with `.always`. We accept this trade because no v1 user can produce an advanced shape — the input source is either the v1 editor itself, a future v2 editor, or a hand-crafted JSON blob synced from another device — and the explicit reset affordance is more honest than silently mangling the user's intent.

---

## Decision 2: Master rename / phase change / person change does not propagate to existing trip-level items

**Date**: 2026-05-11
**Status**: accepted

### Context

`TripTask.name` and `TripPackingItem.name` are snapshotted from the master item at creation (Phase 1 AC 1.8). Phase 2 must commit to whether `phase` (on tasks) and `person` (on packing items) follow the same snapshot rule, or live-link to the master.

### Decision

`name`, `phase` (on tasks), and `person` (on packing items) are all snapshotted at creation and are not retroactively updated by subsequent master edits. Subsequent re-evaluations create new trip-level items if and only if the master is not already referenced by `masterItemID` on the trip.

### Rationale

- Matches the design doc's explicit "snapshot — not live-linked" rule for `name`.
- Avoids surprise: a user who completed "Charge Kindle" on a trip should not see that task spontaneously rename to "Charge tablet" because the master was edited.
- Consistent with AC 1.9 (dangling `masterItemID` references are tolerated).
- Live-linking would also entangle CloudKit sync ordering: a rename arriving from device B should not racily rewrite items already shown on device A.

### Alternatives Considered

- **Live-link `phase` and `person` while snapshotting `name`**: Rejected — mixed semantics are confusing, and live-linking `phase` would jump completed tasks between phase sections.
- **Live-link everything**: Rejected — contradicts the design's stable-snapshot rule and the offline/sync story.

### Consequences

**Positive:**

- Trip-level items are stable across master edits; user-completed work doesn't shift.
- Re-evaluation logic stays simple (snapshot once, never rewrite).

**Negative:**

- A user editing a master to "fix a typo" or "move to the right phase" must understand that the fix applies only to future trips. The "Why is this here?" surface in Phase 3 can clarify this.

---

## Decision 3: No seeded master items in Phase 2; sample / demo data deferred without prework

**Date**: 2026-05-11
**Status**: accepted

### Context

Phase 1 Decision 7 established that the app ships with no seeded `Person` records. Phase 2 adds master items. The user asked whether a sample-trip + sample-items dataset should ship as part of Phase 2 (so users can see what the app does) and whether deferring requires any Phase 2 prework.

### Decision

Phase 2 ships with empty master lists on first launch, matching Phase 1's no-seeding stance. A future onboarding / sample-data phase can introduce sample `Trip`, `MasterTaskItem`, and `MasterPackingItem` records as ordinary records using existing CRUD paths. No Phase 2 prework is required.

### Rationale

- Sample data is just records; deleting them is normal CRUD. No data-model flag, no special "demo mode" branch, no wipe path needed.
- Empty first-run is honest about state and avoids baking household-specific opinions into the binary (consistent with Phase 1 Decision 7).
- A later onboarding phase can decide whether to seed, prompt the user, or import from a starter pack — none of those decisions are constrained by Phase 2's data model.

### Alternatives Considered

- **Seed a small starter set in Phase 2**: Rejected — bakes opinions into the binary and creates an awkward "delete the stuff that doesn't apply to me" first-run.
- **Add a `isSample: Bool` flag to entities now**: Rejected — speculative, no Phase 2 use case, and a flag with no enforcement is just noise.

### Consequences

**Positive:**

- Phase 2 stays focused on the rules engine and editor surface.
- Future sample-data work has full freedom (curated starter pack, onboarding wizard, import-from-friend, etc.).

**Negative:**

- First-time users see an empty Master Lists tab. The empty state in AC 1.2 / 2.2 must communicate what to do next.

---

## Decision 4: Re-evaluation triggers for Phase 2 — five event sources, sync-arrival deferred

**Date**: 2026-05-11
**Status**: accepted

### Context

The design doc lists four re-evaluation triggers: trip attributes changed, master list edited, app launch, and CloudKit sync arrival. Phase 1 left CloudKit sync stubbed; Phase 2 must commit to which triggers fire and how. Peer review of the first-draft decision (cold-launch only) flagged that a user on device B who edits a master on device A but stays in the app for hours after the cross-device sync arrives would see stale trip output until the next cold launch. That window was unbounded.

### Decision

Phase 2 wires five triggers: trip created (AC 5.1), trip attributes edited (AC 5.2), master item created / edited / deleted (AC 5.3), cold-launch scan over non-past trips (AC 5.4), and `scenePhase` `.background → .active` scan (AC 5.7). CloudKit sync arrival as a direct trigger is still deferred to the CKShare phase.

### Rationale

- The five wired triggers cover every observable input change a user can produce on a single device, plus the foreground-transition catch-up that bounds the cross-device staleness window to "user-perceived seconds, not days."
- Sync-arrival callbacks require subscribing to `NSPersistentCloudKitContainer` notifications; that infrastructure is the same one needed for CKShare and is best built once in that phase.
- `scenePhase` is a free signal SwiftUI already publishes; the foreground-transition trigger costs essentially nothing and is idempotent.
- Idempotency (AC 5.6) means an extra re-evaluation is never harmful; we err on the side of running too often rather than too rarely.

### Alternatives Considered

- **Wire sync-arrival trigger now**: Rejected — duplicates CKShare-phase work and pulls notification plumbing into Phase 2.
- **Skip cold-launch scan and rely on foreground-transition only**: Rejected — a fresh process attach is a different lifecycle event from `background → active` and the foreground trigger does not fire on first launch.
- **Skip foreground-transition scan (first-draft decision)**: Rejected on peer review — the cross-device staleness window was unbounded and would produce "this app feels weird on my second device" feedback without a reproducible bug report.
- **Only re-evaluate when attributes actually change, not on every editor save**: Rejected — AC 5.2's "regardless of whether attributes actually changed" simplifies the call site and is harmless due to idempotency.

### Consequences

**Positive:**

- Single-device coverage is complete; the user can never observe stale rule output on the device that made the change.
- Cross-device staleness is bounded by the next foreground transition rather than the next cold launch.
- Adding sync-driven recompute later is purely additive — same engine, new call site.

**Negative:**

- A change synced in from another device while the app is already foregrounded is not picked up until the user backgrounds and re-foregrounds. Acceptable: a user actively in the app on device B is unlikely to be racing edits with device A in the same minute.

### Known Limitation: Cross-Device "today" Skew

The "non-past trip" predicate (`endDate ≥ today` in `Calendar.current` on the device) is evaluated independently on each device. Two devices in different timezones, or with material clock drift, may briefly disagree about whether a trip is non-past around the day-boundary on the trip's end date. The resulting flag-state disagreement is temporary — it resolves as soon as both devices agree the trip is past (and from that point on, neither device re-evaluates that trip). The engine remains deterministic *per device, given a value of "today"*; cross-device convergence depends on devices agreeing about what day it is, which they do almost everywhere except at the day boundary. This is documented rather than fixed; a global "trip-local timezone" attribute is out of scope.

---

## Decision 5: `compute` is pure over value-type snapshots; `apply` mutates separately

**Date**: 2026-05-11
**Status**: accepted

### Context

The rules engine could either (a) fold compute + diff + apply into one function that reads and writes the `ModelContext`, (b) split into a `compute(...)` step that reads `@Model` instances and an `apply(...)` step that writes them, or (c) split into a `compute(...)` step that operates only over value-type snapshots and an `apply(...)` step that bridges the snapshots back to SwiftData mutations.

Peer review of the first-draft "pure function" claim flagged that taking `@Model` references as inputs makes the "unit-testable without a container" promise false — `@Model` instances cannot exist without a `ModelContainer`, and reading their properties touches SwiftData's observation machinery.

### Decision

Split into three pieces and pin them to value-type contracts:

1. **Snapshot capture** — a thin step at each trigger call site reads from the `ModelContext` and constructs `TripSnapshot`, `[MasterTaskSnapshot]`, `[MasterPackingSnapshot]` value types. `TripSnapshot` includes the trip's identity, attributes, and refs to existing trip-level items (`id`, `masterItemID`, `currentlyMatchesRules`, `pinnedByUser`, plus engagement state — `isCompleted` for tasks, `state` for packing items).
2. **Pure compute** — `compute(trip: TripSnapshot, masterTasks: [MasterTaskSnapshot], masterPacking: [MasterPackingSnapshot]) -> Plan` is a pure function. `Plan` carries value-type entries that contain every field `apply` needs to insert or update — `toAdd` entries are the master snapshots themselves; `toFlagUnmatched` and `toFlagMatched` entries are trip-level item ids. AC 4.8 codifies the snapshot-only input contract.
3. **Apply** — `apply(plan:context:)` resolves ids back to `@Model` instances and performs the SwiftData mutations. It is the only step that touches the `ModelContext`.

`Plan` collections iterate in deterministic order (sorted by id, per AC 4.9).

### Rationale

- Snapshot capture is the only step that needs a `ModelContext`. Compute is pure value-type code, unit-testable without spinning up a container.
- The split makes a future "dry-run / preview the diff" feature trivial: capture, compute, present `Plan` to the user, defer `apply`.
- Deterministic iteration (AC 4.9) prevents snapshot-test flake and makes the in-memory `Plan` a useful diagnostic artifact during investigations.
- Value-type snapshots also sidestep the question of whether `compute` accidentally faults `@Model` properties or interacts with CloudKit merge mid-flight.

### Alternatives Considered

- **One function that does it all**: Rejected — hard to test, hard to extend.
- **Two-step split with `@Model` inputs to `compute`** (first draft): Rejected on peer review — the "pure, container-free testability" claim breaks at the type boundary.
- **Three functions (capture, compute, diff, apply)**: Rejected — `compute` already produces the diff by construction; there is no intermediate "raw matches" stage worth modelling. The three pieces above (capture / compute / apply) are the minimum.
- **Sets instead of ordered arrays in `Plan`**: Rejected for the public iteration shape — sets are unordered, which produces non-deterministic mutation order and breaks snapshot tests. Internally `compute` can build sets and sort on emit; the published shape is ordered arrays (AC 4.9).

### Consequences

**Positive:**

- Unit tests cover the engine without a `ModelContainer`.
- `Plan` is a useful diagnostic artifact when investigating user-reported issues, and is stable across re-runs.
- The three-piece split mirrors the natural surface area for a future "dry-run" feature without rework.

**Negative:**

- Two snapshot type families to maintain (`TripSnapshot` + refs, master snapshots). Acceptable: each is a flat value type with no behaviour.
- Three-step call sites; callers must remember to do snapshot → compute → apply in order. Mitigated by a thin convenience wrapper at trigger call sites.

---

## Decision 6: `WhyDisclosure` "which clauses matched" function is Phase 3

**Date**: 2026-05-11
**Status**: accepted

### Context

The UI design doc commits Phase 3 to a `WhyDisclosure` surface (long-press a row to reveal "From rule: weather: rain or cold + scope: international"). Building that string requires a function that walks an `ItemConditions` tree against a `TripAttributes` value and returns the matched `.match(...)` clauses — distinct from the existing `evaluate(against:) -> Bool`. The question is whether to build that function in Phase 2 (alongside the evaluator it parallels) or defer to Phase 3 (where the UI consumer lands).

### Decision

Defer to Phase 3. Phase 2 ships the evaluator alone. Phase 3 adds the parallel "matching clauses" walk on the same file.

### Rationale

- Both peer reviews agreed deferral is correct: the function is a ~30-minute add when Phase 3 needs it, and building it in Phase 2 means writing a function with no caller (which makes the contract harder to lock down).
- Keeping it out of Phase 2 limits the engine's public surface to what the engine actually consumes (`evaluate(...) -> Bool`).
- Phase 3 already touches the conditions evaluator file for `WhyDisclosure` UI work; the cross-file coupling cost is paid once.

### Alternatives Considered

- **Build in Phase 2 alongside the evaluator**: Rejected — produces a function with no caller and risks locking the wrong API shape.
- **Build a single unified function that returns `(Bool, [Clause])`**: Rejected — the engine's hot path (re-eval over all non-past trips) needs only the `Bool`; allocating a clause array for every evaluation is wasteful.

### Consequences

**Positive:**

- Phase 2 stays focused; the engine surface is minimal.
- Phase 3's UI work and the parallel walk land together with their contract validated by the consumer.

**Negative:**

- Phase 3 starts by reopening the evaluator file; small cost, called out so reviewers don't flag it as scope creep at the time.

---

## Decision 8: `Plan.init` enforces sort order; `compute` no longer sorts before construction

**Date**: 2026-05-12
**Status**: accepted

### Context

The original design.md (§Compute algorithm step 5) assigned sort responsibility to `compute(...)`: "Sort each collection by id ascending. Construct `Plan`." During implementation, the natural place to enforce AC 4.9's deterministic-ordering invariant turned out to be the `Plan` initializer itself: every `Plan` value is sorted by construction, regardless of caller.

### Decision

`Plan.init(...)` sorts `toAddTasks` / `toAddPacking` by master id ascending and `toFlagUnmatched` / `toFlagMatched` by `(kind.rawValue, id)` ascending. `compute(...)` passes unsorted arrays; the initializer enforces the invariant.

### Rationale

- AC 4.9's invariant becomes a type-level guarantee — there is no way to construct a `Plan` that breaks it. Future callers (a hypothetical dry-run preview, a test fixture, a CloudKit sync handler) cannot produce an unsorted `Plan`.
- Compute stays focused on the classification logic; sort is mechanical and lives at the value-type boundary.
- The cost is one redundant pass for callers who already pass sorted data, which is negligible against the bounded dataset (≤200 master items per AC 5.5).

### Alternatives Considered

- **Keep sort inside `compute(...)` per the original design**: Rejected — caller must remember the invariant, and `Plan` could otherwise be constructed unsorted (e.g., in tests).
- **Add a `debugAssert(isSorted)` in `Plan.init` and keep sort in compute**: Rejected — debug-only check disappears in release builds, leaving the invariant unenforced where it matters most.

### Consequences

**Positive:**

- Sort invariant is type-enforced; no caller can violate AC 4.9.
- `compute(...)` body is one line shorter (no `.sorted` calls at construction).

**Negative:**

- `Plan` doing work beyond pure value carrying. Acceptable because the work is mechanical (sort, not classification) and lives at the construction boundary.

---

## Decision 9: scenePhase carve-out uses `hasBeenBackgrounded: Bool`, not `previousScenePhase: ScenePhase?`

**Date**: 2026-05-12
**Status**: accepted (corrects design.md §scenePhase carve-out)

### Context

The original design.md (§scenePhase carve-out, AC 5.7) committed to a `previousScenePhase: ScenePhase? = nil` pattern with the guard `previousScenePhase == .background, newPhase == .active`. During implementation, this guard was found to **never fire**: iOS delivers backgrounding as `.background → .inactive → .active`, with `.inactive` as an intermediary. By the time `onChange(of: scenePhase)` sees `.active`, the previous observed phase is `.inactive`, not `.background`. The guard fails and the trigger never runs.

### Decision

Replace the `previousScenePhase: ScenePhase?` pair with a `hasBeenBackgrounded: Bool` latch. Set the flag to `true` whenever the new phase is `.background`; on the next `.active` transition, fire the runner and reset the flag. The cold-launch carve-out is preserved: the initial `nil → .inactive → .active` sequence never observes `.background`, so the flag stays `false` and the runner is not invoked.

### Rationale

- Correctness: the `.inactive` intermediary makes the design's direct edge unobservable. The latch approach matches what iOS actually delivers.
- Idempotence (AC 5.6) protects against any unexpected scene-phase sequence the system might deliver.
- Symmetry: a `Bool` flag mirrors the cold-launch invariant (which is also a one-shot "have we initialised yet" flag).

### Alternatives Considered

- **Track every prior phase in a fixed-size buffer and check for a `.background` entry**: Rejected — over-engineered; the latch captures the single bit that matters.
- **Use `applicationDidEnterBackground` / `applicationWillEnterForeground` lifecycle notifications**: Rejected — the `scenePhase` SwiftUI signal is the project-conventional source of truth (see Phase 1 patterns) and these notifications are not scene-aware on multi-scene platforms.

### Consequences

**Positive:**

- AC 5.7 trigger fires correctly on real `.background → .active` cycles.
- Cold-launch carve-out remains intact.

**Negative:**

- design.md §scenePhase carve-out code snippet is now stale; this decision supersedes it. The CHANGELOG entry under "Fixed" records the same.

---

## Decision 7: Foreground-transition trigger added on peer-review feedback

**Date**: 2026-05-11
**Status**: accepted

### Context

The first-draft AC list had four re-evaluation triggers: trip create, trip attributes save, master save, cold launch. Peer review and design-critic review both flagged that this leaves a "cross-device sync arrived while the app was foregrounded" gap — device A edits a master, the sync mirrors to device B while device B's user is staring at the app, and device B's trip-level state remains stale until next cold launch (which could be days).

### Decision

Add AC 5.7: re-evaluate every non-past trip on `scenePhase` transition from `.background` to `.active`. This trigger fires regardless of how long the app was backgrounded.

### Rationale

- `scenePhase` is a SwiftUI-published signal with no setup cost.
- Re-evaluation is idempotent (AC 5.6), so an extra firing is harmless.
- The user-visible staleness window is bounded by "next time the user puts the app in background and comes back" rather than "next cold launch."
- Avoids the full `NSPersistentCloudKitContainer` notification plumbing that belongs in the CKShare phase.

### Alternatives Considered

- **Subscribe to CloudKit sync notifications**: Rejected — belongs in the CKShare phase per Decision 4.
- **Periodic timer-based re-eval**: Rejected — wasteful, and the device is most likely to be active when the user is actively using the app, so foreground transition is a better proxy.
- **Skip the trigger and accept the staleness window**: Rejected on peer review — the staleness was unbounded, and the cost of the trigger is near zero.

### Consequences

**Positive:**

- Cross-device staleness is bounded by user activity, not by app lifecycle.
- No CloudKit notification plumbing in Phase 2.

**Negative:**

- A user who stays in the app for hours without backgrounding won't pick up syncs from other devices. Acceptable: this is the same as the cold-launch-only behaviour was supposed to be, but bounded by minutes-to-hours rather than days.

---
