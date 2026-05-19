# Decision Log: Phase 5.1 — Wire Trip CRUD through `tripsLocal`

## Decision 1: Feature scope and naming inherited from `docs/implementation-phases.md`

**Date**: 2026-05-17
**Status**: accepted

### Context

`docs/implementation-phases.md` describes a Phase 5.1 — Wire Trip CRUD through `tripsLocal` block that names the work needed to close the loop after Phase 5's infrastructure landed. The user asked for a spec for "phase 5.1" with no Transit ticket attached and no preference about an alternative name.

### Decision

Adopt the feature name `phase-5.1-wire-trip-crud-tripslocal` and treat the implementation-phases doc's bullet list as the inherited scope to translate into EARS-format requirements.

### Rationale

The implementation-phases doc is the existing source of truth for phase boundaries in the project and the user's request explicitly references it. Reusing the name keeps cross-references stable (`CLAUDE.md`, `specs/OVERVIEW.md` if added later) and signals continuity with the Phase 5 spec.

### Alternatives Considered

- **Roll the work into Phase 5 by appending tasks**: Rejected because Phase 5 is already merged on `main` (commit `9da896e`); reopening it would conflate "what shipped" with "what was deferred."
- **Name it `phase-6-wire-trip-crud`**: Rejected because Phase 6 is reserved in the same doc for Notifications + Polish; renumbering would invalidate references.

### Consequences

**Positive:**
- Continuity with existing planning artefacts.
- Future readers can trace why this work is separate from Phase 5.

**Negative:**
- Decimal phase numbers in spec dirs may surprise readers who assume sequential whole numbers; mitigated by the link from `implementation-phases.md`.

---

## Decision 2: Trip-domain entities live in `tripsLocal`; `Person` and `Master*` stay in `globals`

**Date**: 2026-05-17
**Status**: proposed

### Context

Phase 5's design split persistence into two `ModelContainer`s — `globals` (CloudKit-mirrored private DB) and `tripsLocal` (CloudKit-disabled, sync driven by `TripSyncEngine`). The SwiftUI view layer has remained bound to `globals` only, so the new `tripsLocal` container is empty in production and the sync engine has nothing to upload. Phase 5.1 must choose which entity classes live where for trip-domain reads and writes, and how cross-container references resolve.

### Decision

Trip-domain entities (`Trip`, `TripTask`, `TripPackingItem`, `TripPersonSnapshot`, `TripZoneState`) live in `tripsLocal`. `Person`, `MasterTaskItem`, and `MasterPackingItem` continue to live in `globals`. Cross-container references from trip-domain views resolve by UUID lookup, not by SwiftData relationship traversal.

### Rationale

- Trip-domain entities are the only ones that participate in `CKShare`; placing them in the container the sync engine owns keeps the dirty-flag chokepoint (`LocalWriteHook`) effective.
- `Person`, `MasterTaskItem`, and `MasterPackingItem` are explicitly user-private per Phase 5 Req 3 and must never be associated with a `CKShare`; mirroring them through CloudKit's automatic SwiftData integration in `globals` keeps them on the private DB only.
- The V2-era `Trip.participants → Person` and `TripPackingItem.person → Person` SwiftData relationships span containers under this split, which SwiftData cannot resolve; `TripPersonSnapshot` already carries the data trip-domain views need.
- UUID lookup avoids re-introducing cross-container relationship traversal that would re-couple the two stores.

### Alternatives Considered

- **Keep everything in `globals` and let `CKSyncEngine` operate over a single container**: Rejected because `globals` uses SwiftData's automatic CloudKit mirror (the private DB), which does not support custom zones or `CKShare`; this is the constraint that drove the dual-container split in the first place.
- **Move `Person` into `tripsLocal` too**: Rejected because `Person` is private per Req 3.1 and the master list editors need direct SwiftData relationships to `MasterPackingItem`, which must also stay private.
- **Use a third "trip masters" container**: Rejected as gratuitous complexity for the one cross-container link that actually matters.

### Consequences

**Positive:**
- Sharing pipeline becomes effective: writes from views reach the engine.
- Master lists and Person registry stay strictly private with no extra guards.
- `TripPersonSnapshot` becomes the canonical source for participant identity in trip views (already required by Phase 5 Req 2.5).

**Negative:**
- Trip-domain views that previously traversed `trip.participants` or `packingItem.person` must be rewritten to read from `TripPersonSnapshot` or to do UUID lookups against `globals`.
- The V2-era relationships persist in `SchemaV3` but become "do-not-use from trip views" — this is a convention without a compiler check until a future `SchemaV4` removes them.

### Impact

Trip Detail, Trip Editor, Trip List, Packing Sheet, Task Form, Packing Item Form, and any place that today reads `trip.participants` or `packingItem.person` from a SwiftUI surface. The Migration Coordinator gains a per-trip move step that copies records from `globals` into `tripsLocal`.

---

## Decision 3: Enforce the `LocalWriteHook` chokepoint via a contract test

**Date**: 2026-05-17
**Status**: proposed

### Context

Phase 5.1 exists because the `LocalWriteHook.commit(_:)` chokepoint was bypassable and got bypassed: every SwiftUI Trip-feature surface called `modelContext.save()` directly, so dirty flags were never set and CloudKit uploads never happened. The agent notes (`sync-infrastructure.md`) record the current state as "code-review checklist item." Without a durable enforcement mechanism, the same regression can recur on the next feature added to the Trips subtree.

The peer review surfaced this as the one explicit decision Phase 5.1 needs to make: enforce or non-goal, but do not stay silent.

### Decision

Add a `ScrambleTests` contract test (Req [2.5](requirements.md#2.5)) that scans production source files under `Scramble/Scramble/` (excluding `LocalWriteHook.swift` itself) for direct `modelContext.save()` invocations against a `ModelContext` belonging to `tripsLocal`. The test fails the build if any are found. Do not adopt a SwiftLint rule.

### Rationale

- A contract test runs as part of the regular `make test` cycle that pre-push review already enforces; no new tooling, configuration, or CI changes are required.
- The detection is precise enough for the Phase 5.1 wiring: every call site this phase touches is removed from production code; the test guards against re-introduction.
- SwiftLint is not part of the current `make lint` pipeline (the Makefile no-ops if SwiftLint is absent) and adding it now would expand the linting story beyond Phase 5.1's scope.
- The cost of a future false positive (a legitimate direct save outside the dirty-marking path) is low: the test failure points the contributor at the chokepoint and the test allowlist can be widened deliberately if such a case is justified.

### Alternatives Considered

- **SwiftLint custom rule**: Rejected because SwiftLint is not currently a hard project dependency and adding it for one rule expands scope.
- **Code-review discipline only**: Rejected. This is what Phase 5 had; it failed once and Phase 5.1 exists as a consequence.
- **Wrapping helper that physically prevents direct save**: Rejected because `ModelContext.save()` is a public API on a framework type that cannot be hidden behind a wrapper without giving up the SwiftUI `@Environment(\.modelContext)` injection model.

### Consequences

**Positive:**
- Bug class is closed durably; the same regression cannot ship undetected.
- No new dependencies or CI infrastructure.

**Negative:**
- The test relies on source-pattern scanning, which is fragile against refactors (e.g., a future renaming of `tripsLocal` will need the test allowlist updated) and may produce false positives that contributors silence with the `// LocalWriteHookContract: allow` escape — the escape is intentional but the policy needs review at each future schema bump.
- The test is a static check at compile time on the test target; runtime composition (e.g., a `ModelContext` injected from a hidden location) could in principle slip past, though no such pattern exists today.

---

## Decision 4: V2-era `Trip.participants` and `TripPackingItem.person` relationships persist as latent landmines

**Date**: 2026-05-17
**Status**: accepted

### Context

`SchemaV3` retains the V2-era relationships `Trip.participants → Person` and `TripPackingItem.person → Person` for migration compatibility. Phase 5.1's container split places `Trip` and `TripPackingItem` in `tripsLocal` and `Person` in `globals`, so any code path that traverses these relationships from a `tripsLocal` context tries to cross containers — unsupported by SwiftData and likely to trap. The peer review flagged the silence on this as dishonest non-goaling.

### Decision

Phase 5.1 forbids reads of these relationships from trip-domain views via constraint [C3](requirements.md#C3) and enforces the prohibition with a code-level test (Req [10.3](requirements.md#10.3)). The relationships themselves remain on the schema; schema-level removal is deferred to a future `SchemaV4` cleanup phase.

### Rationale

- Removing the V2-era relationships from `SchemaV3` would require a `SchemaV4` bump and a custom migration; this is more invasive than the bug Phase 5.1 is fixing and would block shipping the wiring loop.
- The relationships are still needed at the model level so the Phase 5 migration plan can compile and the V1 → V2 lightweight diff remains valid for the schema-version policy (per `persistence.md` § "Versioned schema policy").
- A code-level test prevents accidental re-introduction without requiring a schema bump.

### Alternatives Considered

- **Bump to `SchemaV4` now and remove the relationships**: Rejected because it doubles the scope of Phase 5.1 and the relocation step in Req [4](requirements.md#4-existing-trips-relocate-from-globals-to-tripslocal-on-first-phase-51-launch) is already the riskiest part of the phase.
- **Leave the relationships and trust code review**: Rejected for the same reason as Decision 3: silent failure mode, regression-prone.

### Consequences

**Positive:**
- Phase 5.1 ships without a schema bump.
- The hazard is documented and test-enforced.

**Negative:**
- The schema carries dead relationships until `SchemaV4`; the persistence layer becomes harder to reason about for future readers.
- The code-level test in Req [10.3](requirements.md#10.3) is a pattern check, not a type-system guarantee; non-trivial future code transformations could bypass it.

---

## Decision 5: Documentation and deliverables are tracked in the tasks document, not requirements

**Date**: 2026-05-17
**Status**: accepted

### Context

The first requirements draft included a Section 10 covering updates to `CLAUDE.md`, `CHANGELOG.md` (if added), `phase-5-cloudkit-sharing/implementation.md`, and the addition of `phase-5-cloudkit-sharing/manual-test-plan.md`. Both reviewers flagged this as task-tracking material miscategorised as user-observable acceptance criteria.

### Decision

The documentation updates move out of the requirements document. They will appear as explicit tasks in `tasks.md` and as deliverables in the Definition of Done. The requirements document keeps only behavioural and persistence-invariant acceptance criteria.

### Rationale

Acceptance criteria are properties the running system exhibits; doc updates are properties of the repository at PR merge time. Conflating them weakens both.

### Alternatives Considered

- **Keep them as a "Deliverables" section in `requirements.md`**: Rejected because requirements.md is the input to the design and tasks phases; adding non-requirement content invites confusion.
- **Move them only to the tasks document and drop the deliverables tracking**: Rejected because the missing `manual-test-plan.md` is referenced by Phase 5's implementation document and would silently rot.

### Consequences

**Positive:**
- Cleaner separation of "what the system does" from "what the repo contains."

**Negative:**
- Approval of the requirements does not automatically commit the team to the doc updates; they must be carried into `tasks.md` explicitly during Phase 4 of the spec workflow.

---

## Decision 6: `\.localWriteHook` default value is a no-op hook, not `fatalError`

**Date**: 2026-05-17
**Status**: accepted

### Context

The design specified the default value of the new `\.localWriteHook` SwiftUI environment key as a `fatalError`-only stub on the grounds that previews / tests without explicit injection should never commit. In practice this crashed the host app at launch: SwiftUI's `.environment(\.localWriteHook, _:)` modifier reads the keypath's current value via `WritableKeyPath._projectMutableAddress(from:)` to obtain a writable address before overwriting it, so the fatal stub fires *before* production injection in `ScrambleApp.rootContent()` can take effect. The crash surfaces as `_assertionFailure → static LocalWriteHookKey.defaultValue.getter → ChildEnvironment.updateValue` during the first `_UIHostingView.layoutSubviews()` pass.

### Decision

The default value of `\.localWriteHook` is a `LocalWriteHook` whose notifier is a private `FallbackPendingChangeNotifier`. The fallback notifier behaves in two modes:

- **Test / UI-test / preview surroundings** (detected via `EnvironmentProbe.production`): discards signals silently. Previews and tests that read the environment without injecting one still save locally; they simply do not signal the sync engine.
- **Production**: emits a `fault`-level `modelLogger` entry naming the unreached injection and (in DEBUG builds) trips an `assertionFailure`. The signal surfaces a misconfigured production view path at the first commit rather than the first missed sync.

Production continues to inject the real hook (notifier = `TripSyncEngine`) from `ScrambleApp.rootContent()`.

### Rationale

- SwiftUI's environment-propagation machinery touches `defaultValue.getter` even when the modifier above it would supply a concrete value. A fatal default is therefore incompatible with the SwiftUI environment lifecycle; the design's stated intent ("fail fast in previews") is unreachable as written.
- A benign-in-test, loud-in-production fallback satisfies SwiftUI's lifecycle without weakening the production contract. It pairs with the contract test in Req [2.5](requirements.md#2.5) to close both halves of the silent-failure mode Phase 5.1 exists to eliminate: the contract test catches direct `modelContext.save()` call sites; the fallback notifier catches the inverse — a `hook.commit(modelContext)` whose env-resolved hook is the default because injection didn't propagate.
- The behavioural difference for previews / tests is small and acceptable: a preview that triggers a "save" will succeed locally (matching the existing `try modelContext.save()` behaviour previews already see) and emit no sync signals.

### Alternatives Considered

- **Optional environment value (`LocalWriteHook?`)**: Rejected because every Trip-domain view would have to unwrap on every call site, expanding the call-site footprint of the chokepoint refactor.
- **Lazy / boxed value that only fatals on `commit`**: Rejected for the same reason as the original fatal stub — the SwiftUI environment getter still has to materialise a concrete value to overwrite, and any indirection that resolves to fatal at construction time crashes identically.
- **Pure no-op notifier (no production signal)**: Rejected on review (see Decision 6 in this log's review history) because a `hook.commit()` call site that resolved to the default would silently update `TripZoneState.pendingUploadFlags` without notifying the engine — the same silent-failure mode Phase 5.1 exists to eliminate, reintroduced through a different door.
- **Skip the env key and pass `LocalWriteHook` explicitly through view initialisers**: Rejected because Trip-feature surfaces are deep (Trip List → Trip Detail → AccordionTimeline → PackingSheet → PackingItemForm) and threading a parameter through each layer adds boilerplate proportional to the refactor's surface area.

### Consequences

**Positive:**
- App launches cleanly under the dual-container split.
- Previews / tests that incidentally touch the hook do not crash.
- Production injection contract is unchanged; the contract test in Req [2.5](requirements.md#2.5) carries the static-source enforcement and the fallback notifier carries the runtime enforcement, together covering both halves of the silent-failure mode.

**Negative:**
- A preview that incorrectly relies on the env-injected hook for sync behaviour would observe silent no-ops. This is bounded — the only views that read `\.localWriteHook` are Trip-feature surfaces, and their preview suites do not assert sync behaviour.
- Detection of the misconfigured-injection case is at first commit, not at view mount; a view that never commits could still ship with a broken injection chain. Tolerable: the same view that never commits also never causes data loss.

---

## Decision 7: `SignInResumeCoordinator.init` drops the `CKContainer` parameter

**Date**: 2026-05-18
**Status**: accepted

### Context

The design document (`design.md` § "SignInResumeCoordinator (new)") gave the production init signature as `init(migrationCoordinator: ZoneMigrationCoordinator, container: CKContainer)`. The intent was for the resume coordinator to perform an independent `CKContainer.accountStatus()` re-check distinct from `ZoneMigrationCoordinator.isCloudAvailable()`. During Phase 5 implementation it became clear that the only check `runResumeIfNeeded` needs is `migrationCoordinator.isCloudAvailable()` — the coordinator already encapsulates the account-status probe, and adding a second probe inside `SignInResumeCoordinator` would duplicate the logic and risk drift between two answers to the same question.

### Decision

The production `SignInResumeCoordinator.init` takes only `migrationCoordinator: ZoneMigrationCoordinator`. The `CKContainer` parameter is removed. The immediate re-check on `start()` calls `runResumeIfNeeded`, which gates on `migrationCoordinator.isCloudAvailable()`.

### Rationale

- One source of truth for "is iCloud available right now" prevents the two-probes-can-disagree race the original design quietly accepted.
- The coordinator's `isCloudAvailable` closure is already test-injectable; `SignInResumeCoordinator` inherits that testability for free.
- The unused parameter would have invited future bugs ("why is this here? let me find a use for it") that the lint pass would not catch.

### Alternatives Considered

- **Keep the `CKContainer` parameter and call `accountStatus()` directly**: Rejected because it duplicates `migrationCoordinator.isCloudAvailable()` and forces tests to mock CloudKit through a second seam.
- **Pass a closure `accountStatusProvider` instead of `CKContainer`**: Rejected as gratuitous indirection; the test init already accepts an `isCloudAvailable: () -> Bool` closure that covers the same need.

### Consequences

**Positive:**
- Single source of truth for the availability check.
- Production init signature matches the test-friendly init's intent (one closure does the gating).
- No drift between the design's two CloudKit probes.

**Negative:**
- The design document's signature is now stale; readers reaching for the spec see a parameter that no longer exists in the code. Mitigated by this decision-log entry — the design document is not edited retroactively per the project's convention of preserving as-shipped specs.

---
