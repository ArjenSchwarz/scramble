# Decision Log: Phase 1 Foundation

## Decision 1: Scope cut for Phase 1

**Date**: 2026-05-11
**Status**: accepted

### Context

Scramble has a 10-step recommended implementation order in `docs/scramble-ui-design-doc.md`, but the project currently contains only Xcode template scaffolding. Before any of those 10 steps can begin, the data model, theme infrastructure, app shell, and basic trip CRUD have to exist. None of those four foundations are themselves on the recommended list — they are implicit prerequisites.

### Decision

Phase 1 covers data model, theme system, app shell with Trips and Master Lists tabs, Trip List with auto-open, Trip Detail scaffold (header + empty timeline spine), Master Lists scaffold (placeholder only), and trip CRUD with people management. PhaseNode visuals, accordion expansion, task rows, packing UI, rules engine, master-list editing, CKShare invitations, and notifications are deferred to later phases.

### Rationale

The cut produces a runnable app the user can navigate around, without committing to any UI component the design doc treats as substantive. Every later phase needs the model, container, theme env, and the ability to create a trip — without these, the recommended steps cannot start.

### Alternatives Considered

- **Smaller cut (model + theme + app shell only, no trip CRUD)**: Rejected — without trip CRUD there is nothing to render in the Trip Detail scaffold, so we'd ship a non-runnable foundation that can't be tested end-to-end.
- **Larger cut (include rules engine and PhaseNode component)**: Rejected — rules engine touches both master list editing and TripTask/TripPackingItem materialisation. Including it pulls in master-list editing UI, which the user's prompt explicitly defers.

### Consequences

**Positive:**

- Every later phase has a stable foundation; no model migrations expected for at least the next 2–3 phases.
- Phase 1 is end-to-end testable in the simulator (create trip, see it in list, edit, delete).

**Negative:**

- The Trip Detail scaffold ships without expandable phases, which may feel hollow when used standalone.
- Master Lists tab ships as a placeholder; users seeing this tab will expect content that arrives later.

---

## Decision 2: People are global entities, not per-trip

**Date**: 2026-05-11
**Status**: accepted

### Context

The design doc shows `Trip.people: [Person]` and `MasterPackingItem.person: Person`. If `Person` is per-trip, the master list cannot reference one. The design doc lists default per-person colors (Arjen → Cyan, Kelsey → Green, etc.) which only makes sense across trips.

### Decision

`Person` is a global SwiftData entity. Trips reference people via a SwiftData relationship. Master packing items reference a global person.

### Rationale

The master list is the single source of reusability and references `Person`. A per-trip Person would force re-entering the same family for every trip and would break master-list rules.

### Alternatives Considered

- **Per-trip Person**: Rejected — incompatible with master packing list and with default per-person colors.
- **Global Person plus per-trip nickname/color override**: Deferred — adds complexity that doesn't pay off until proven necessary.

### Consequences

**Positive:**

- Master list and rules engine work cleanly.
- Person colors are stable across trips.

**Negative:**

- Deleting a person requires checking references across trips — cannot just orphan the record.

---

## Decision 3: Date attributes — `Date` storage, day-granularity semantics

**Date**: 2026-05-11
**Status**: accepted

### Context

iOS `Date` includes a time component, but trips are inherently day-granular. The status line ("in 3 days", "Day 2 of 7") and phase-by-day computation must behave consistently regardless of when on a given day the user enters a date.

### Decision

Store `startDate` and `endDate` as `Date`. All comparisons normalize to the user's calendar day via `Calendar.current.startOfDay(for:)`. The trip editor uses a date-only picker (no time component shown).

### Rationale

`Date` is the lingua franca of CloudKit-backed schemas; introducing a custom day-only type would complicate sync. Day normalisation in computation is straightforward.

### Alternatives Considered

- **Custom `TripDate` struct**: Rejected — adds friction to CloudKit sync and forces every consumer to convert.
- **Storing midnight UTC**: Rejected — surprises users in non-UTC time zones (a trip "starting tomorrow" might display as today after a flight).

### Consequences

**Positive:**

- Native CloudKit/SwiftData support.
- No custom encoders.

**Negative:**

- Every comparison site must remember to use `startOfDay(for:)`; risk of bugs if a contributor forgets.

---

## Decision 4: Theme variant follows system appearance only

**Date**: 2026-05-11
**Status**: accepted

### Context

The UI design doc states "Users select a theme; appearance follows iOS." V1 ships only one theme (Midnight Atlas), so theme selection is a no-op for v1. Whether to give users an in-app light/dark override remains a question.

### Decision

The active variant is selected from the SwiftUI `colorScheme` environment value. No in-app override.

### Rationale

The design doc explicitly defers this. iOS already provides system-level light/dark control. Adding an in-app toggle for v1 adds settings UI we don't otherwise need.

### Alternatives Considered

- **In-app appearance override (always dark / always light / follow system)**: Deferred — useful for future themes, but not load-bearing now.

### Consequences

**Positive:**

- No settings screen needed in Phase 1.
- Users get correct appearance automatically.

**Negative:**

- Users who prefer dark UI in light mode (or vice versa) cannot opt in — addressed when the theme picker ships.

---

## Decision 5: Country flag emoji in Trip Detail header is deferred

**Date**: 2026-05-11
**Status**: accepted

### Context

The UI design doc mentions "Trip name + country flag emoji" in the Trip Detail header. Implementing this requires either a country picker in the trip editor or auto-detection from text — both non-trivial.

### Decision

Phase 1 ships the trip name without a country flag. The flag is added in a later phase when the timeline content lands.

### Rationale

The flag is decorative; it does not affect the rules engine, packing, or any other Phase 1 deliverable. Adding a country picker now expands the editor scope without payoff.

### Alternatives Considered

- **Free-text country field**: Rejected — adds an unparsed string field to the schema with no current use.
- **Parse country from trip name**: Rejected — unreliable and not requested.

### Consequences

**Positive:**

- Trip editor stays minimal.
- No new schema field that we'd have to populate for existing trips later.

**Negative:**

- Trip Detail header looks plainer than the React prototype.

---

## Decision 6: Tab bar hidden inside Trip Detail

**Date**: 2026-05-11
**Status**: accepted

### Context

The UI design doc says: "There are no tabs inside a trip. The only place tabs exist is the app-level bottom bar on the Trip List screen." Implementation question: how is this enforced — by hiding the tab bar via `.toolbar(.hidden, for: .tabBar)` or by a custom navigation structure?

### Decision

Use `.toolbar(.hidden, for: .tabBar)` on the Trip Detail screen so that pushing into a trip removes the tab bar visually, while the underlying `TabView` remains the root.

### Rationale

Single root `TabView` is simpler and matches how iOS apps conventionally handle "hide tab bar on detail" scenarios. Avoiding a custom root container preserves Liquid Glass styling.

### Alternatives Considered

- **Custom root with conditional tab bar**: Rejected — re-implements behaviour that SwiftUI provides natively, and risks losing Liquid Glass treatment.

### Consequences

**Positive:**

- One root container; system handles glass treatment.
- Easy to revert per-screen.

**Negative:**

- Requires every Trip Detail child view to remember to apply the modifier; mitigated by setting it on the Trip Detail itself.

---

## Decision 7: Ship with no seeded people

**Date**: 2026-05-11
**Status**: accepted

### Context

The design doc lists default colors for Arjen, Kelsey, Pacifica, and Rigel. Phase 1 needs to decide whether to insert those four `Person` records on first launch (so the trip editor's people picker has options immediately) or to ship empty and rely on the inline-create affordance.

### Decision

Phase 1 ships with no seeded `Person` records. The user creates each person via the trip editor's inline create affordance.

### Rationale

The user explicitly chose this option. Empty first-run is honest about the app's state and avoids shipping personal data baked into the binary; the design's default colors still apply when those names are entered.

### Alternatives Considered

- **Seed Arjen / Kelsey / Pacifica / Rigel on first launch**: Rejected — bakes the personal household into the shipped app and creates an awkward first-run for any non-household user.
- **Seed only in DEBUG / Simulator builds**: Rejected — adds build-config branching that is easy to forget; preview/test fixtures are a cleaner place to provide seeded people for development.

### Consequences

**Positive:**

- Production first-run is clean.
- No coupling between the app binary and a specific household.

**Negative:**

- The very first trip creation requires the user to add at least one person inline — slight friction.
- Test/preview code must build its own person fixtures rather than relying on a seeded set.

---

## Decision 8: One CloudKit custom zone per trip

**Date**: 2026-05-11
**Status**: superseded by Decision 9

### Context

`CKShare` requires the shared records to live in a custom CloudKit zone (the default zone cannot be shared). Phase 1 must choose between (a) writing trips into the default private zone now and migrating them into per-trip zones when sharing lands, (b) provisioning a custom zone per trip up front, or (c) skipping CloudKit entirely until sharing arrives.

### Decision

Each `Trip` and its owned entities (`TripTask`, `TripPackingItem`) live in a dedicated CloudKit custom zone whose identifier is derived deterministically from the trip's stable `id`. Globally shared entities (`Person`, `MasterTaskItem`, `MasterPackingItem`) stay outside per-trip zones (default zone or a single dedicated globals zone — design phase decides).

### Rationale

The user explicitly chose this option. Provisioning the per-trip zone up front means the eventual `CKShare` work is purely additive; no records have to be moved between zones, which is the painful path with CloudKit.

### Alternatives Considered

- **Default private zone now, migrate later**: Rejected — moving records between CloudKit zones is non-trivial and error-prone, especially across devices that have already synced. Avoiding this rework justifies the upfront cost.
- **Skip CloudKit entirely until sharing arrives**: Rejected — would lose cross-device sync for the user's own devices in the interim and contradicts the design's emphasis on shared coordination.

### Consequences

**Positive:**

- `CKShare` integration in a later phase becomes purely additive (attach a share to the existing zone).
- Per-trip zones make per-trip subscriptions and selective sync simpler when those features land.

**Negative:**

- Phase 1 must include zone-creation and zone-deletion logic (on trip create / trip delete) that won't be visibly exercised until sharing ships.
- Slight increase in CloudKit operations and quota usage per trip.

---

## Decision 9: Defer per-trip CloudKit zones to the CKShare phase (supersedes Decision 8)

**Date**: 2026-05-11
**Status**: accepted

### Context

Decision 8 committed Phase 1 to one CloudKit custom zone per trip on the assumption that this is achievable while staying on SwiftData. Independent peer review (Gemini, Kiro) flagged that SwiftData's `cloudKitDatabase: .private(...)` mirrors all records into a single zone (`com.apple.coredata.cloudkit.zone`) and exposes no public API to route records into per-trip custom zones based on a property value. Achieving the per-trip zone goal would require either dropping SwiftData for trip-owned entities (and using raw `CKRecord`), running multiple `ModelContainer` instances (one per trip with dynamic store mounting), or relying on an undocumented iOS 26 SwiftData feature that we cannot confirm exists.

### Decision

Phase 1 uses standard SwiftData CloudKit mirroring with all entities in the default zone. The per-trip-zone strategy is deferred to the same phase that introduces `CKShare` invitations. When that phase begins, we will move trip-owned records from the default zone into per-trip custom zones as a one-time per-device migration step; this is a CloudKit data move, not a SwiftData schema migration.

### Rationale

- Avoids burning Phase 1 budget on architectural plumbing that may not be feasible without leaving SwiftData behind.
- Keeps Phase 1 small enough to ship a runnable foundation quickly.
- Preserves the option to do the right thing later, with full information.
- The cost of the future zone migration is real but bounded: a one-time per-device move of trip records, scriptable as a one-shot CloudKit operation.

### Alternatives Considered

- **Stay on Decision 8 and spike SwiftData zone routing**: Rejected — adds an unbudgeted research week with high failure probability.
- **Drop SwiftData for trip-owned entities, use raw CKRecord now**: Rejected — doubles the persistence-layer surface area for the most-edited entities and abandons SwiftData's ergonomics where they matter most.
- **Keep Decision 8 as-written**: Rejected — peer review identified a likely-blocking architectural gap; the safe move is to defer.

### Consequences

**Positive:**

- Phase 1 stays tractable and uses well-trodden SwiftData + CloudKit defaults.
- No bespoke zone-management code that we can't actually exercise in Phase 1.

**Negative:**

- The CKShare phase will need a one-time data move on each user device when trips are first imported into per-trip zones. This is non-trivial but well-bounded.
- Until per-trip zones land, we cannot offer per-trip selective sharing — a non-issue given CKShare itself is not in Phase 1.

---

## Decision 10: Mandate id, inverses, cascade rules, and Codable blobs from day one

**Date**: 2026-05-11
**Status**: accepted

### Context

Peer review identified four data-model risks: undeclared `id: UUID` on entities (the rules engine and explainability surface depend on stable IDs); missing inverse relationships (SwiftData/CloudKit prefer them, and integrity checks like "is this person referenced?" become fragile without them); no cascade-delete from `Trip` to `TripTask` / `TripPackingItem` (default nullify orphans local records); and `Trip.attributes` storage left unspecified (typed properties would force a SwiftData migration when adding an attribute category).

### Decision

The schema mandates: `id: UUID` (client-assigned, immutable) on every entity, explicit inverse relationships for every cross-entity reference, cascade-delete from `Trip` to its owned `TripTask` / `TripPackingItem` records, and Codable-blob storage for `Trip.attributes` (matching the storage strategy already adopted for `MasterTaskItem.conditions` and `MasterPackingItem.conditions`).

### Rationale

Each of these is free or near-free to do now and expensive to retrofit. Schema decisions have the highest blast radius in Phase 1; documenting them as accepted decisions here prevents drift during implementation.

### Alternatives Considered

- **Defer to design phase**: Rejected — these are requirements-level commitments that downstream consumers (rules engine, packing, CKShare) depend on. Documenting them now anchors design.
- **Typed properties for `Trip.attributes`**: Rejected — adding a sixth attribute category later would force a SwiftData migration; the Codable-blob path stays migration-free.

### Consequences

**Positive:**

- Adding new attribute categories or condition shapes later requires no migration.
- Person-deletion integrity check has an O(1) inverse-relationship traversal.
- Cascade rules eliminate a class of orphan-record bugs.

**Negative:**

- Codable blobs cannot be queried by SwiftData predicates — attribute-based filtering must happen in memory after fetch. Acceptable given the small dataset (a household's trips).
- Inverse relationships add slight schema complexity in the model definition.

---

## Decision 11: Establish VersionedSchema and SchemaMigrationPlan from day one

**Date**: 2026-05-11
**Status**: accepted

### Context

SwiftData supports schema versioning via `VersionedSchema` and `SchemaMigrationPlan`. Setting these up after data is already in production requires careful migration handling. Setting them up in Phase 1 — when the data model is empty — costs nearly nothing.

### Decision

Phase 1 wraps the schema in a `VersionedSchema` and provides an empty `SchemaMigrationPlan`. The first version is declared with no migration steps; future versions can register stages without restructuring the container code.

### Rationale

Free insurance. Adopting it now means the first real migration is a routine addition rather than a refactor of the container bootstrap.

### Alternatives Considered

- **Adopt only when first migration is needed**: Rejected — the cost of doing it now is trivial; the cost of adopting it later (with live data) is meaningfully higher.

### Consequences

**Positive:**

- First schema migration is a routine addition, not a container refactor.
- Forces clear thinking about which `Schema` corresponds to which app version.

**Negative:**

- Slight upfront verbosity in the schema definition.

---

## Decision 12: Test/preview container is a behavioural rule, not a prescribed mechanism

**Date**: 2026-05-11
**Status**: accepted

### Context

The earlier draft of AC 2.4 prescribed `XCTestConfigurationFilePath` env-var sniffing or `NSClassFromString("XCTestCase")` as the test-detection mechanism. Both reviewers flagged this as fragile (Swift Testing isn't reliably detected) and as not covering SwiftUI Previews (which also need the in-memory container). Prescribing a specific mechanism in requirements also conflates what (no CloudKit in tests/previews) with how.

### Decision

The requirement is behavioural: tests, UI tests, and SwiftUI Previews use an in-memory `ModelContainer` with `cloudKitDatabase: .none`. The detection mechanism is a design-phase concern. Note that XCUITest does NOT load `XCTest` into the host-app process, so `NSClassFromString("XCTestCase")` and `XCTestConfigurationFilePath` only cover unit-test-target hosts; UI-test detection in the host app typically requires a launch-argument convention (e.g., the UI test runner passes `-uitest 1` and the app reads it from `ProcessInfo`). Acceptable design-phase mechanisms include: build-config flags, `ProcessInfo.isSwiftUIPreview`, host-app launch-argument convention for UI tests, the standard XCTest env var for unit tests, or a combination — design picks and documents the chosen mechanism, plus a smoke test that all three contexts (unit, UI, preview) get the in-memory container.

### Rationale

Requirements should describe observable behaviour, not implementation mechanism. The "no CloudKit in any of these contexts" contract is what tests can verify; the trigger is internal.

### Alternatives Considered

- **Keep the prescribed env-var mechanism**: Rejected — fragile across Swift Testing and previews, and pollutes requirements with implementation detail.

### Consequences

**Positive:**

- Design has freedom to pick the sturdiest detection approach.
- Requirements stay testable (the contract is observable).

**Negative:**

- Design phase must explicitly document the chosen mechanism and a smoke test that it works for tests, UI tests, and previews.

---

## Decision 13: Phase node renders past/current/future visual states in Phase 1

**Date**: 2026-05-11
**Status**: accepted

### Context

The earlier draft of AC 6.4 required computing each phase's past/current/future state without mandating any rendering. That produces dead computation: code runs but its result is unobservable, which is a smell and untestable.

### Decision

Phase 1 ships the minimum visual treatment that distinguishes past, current, and future phases — for example, filled vs outlined node circles. The full glow-ring treatment from the UI design doc remains deferred to a later phase.

### Rationale

Pairs the computation with an observable outcome (the requirement becomes testable as a snapshot or visual-regression check). Keeps Phase 1 visually honest about the timeline structure without committing to the full PhaseNode component.

### Alternatives Considered

- **Defer all visual state to the phase that ships PhaseNode**: Rejected — produces dead code in Phase 1 and leaves the timeline scaffold visually flat.
- **Ship the full glow-ring PhaseNode now**: Rejected — overshoots Phase 1 scope and pulls in animation work that belongs with accordion expansion.

### Consequences

**Positive:**

- Computation has an observable contract; testable in Phase 1.
- Trip Detail scaffold reads as a real timeline, not a list of dots.

**Negative:**

- Slight visual polish work in Phase 1 that will be replaced when the full PhaseNode lands.

---

## Decision 14: Persist enums as `String` raw values with computed bridges

**Date**: 2026-05-11
**Status**: accepted

### Context

`Phase`, `ItemSource`, and `PackingState` are well-defined enums that could in principle be stored directly as `@Model` properties (SwiftData supports `RawRepresentable` enum properties). In practice, native enum properties on `@Model` classes have produced CloudKit schema-promotion issues in Xcode releases earlier than 26 — adding a new enum case requires the production CloudKit schema to be re-promoted, and existing records can't be backfilled from the type system alone.

### Decision

Each enum-valued property on a `@Model` class is stored as `String` (the raw value), with a computed property bridge providing the typed enum API: `var phaseRaw: String = Phase.weeksBefore.rawValue` plus `var phase: Phase { get set }` as an extension.

### Rationale

Storing strings sidesteps the schema-promotion friction entirely. Adding a new enum case becomes a string-validation concern rather than a schema migration. The bridge is trivial and documented in one place.

### Alternatives Considered

- **Store the typed enum directly**: Rejected — even when it works, it makes adding cases more painful than it needs to be.
- **Custom `Codable` on each enum**: Rejected — needless complexity for a small fixed set of enums.

### Consequences

**Positive:**

- Adding enum cases requires no CloudKit schema action.
- Decode failure (unknown raw value from a future device) gracefully degrades to a default rather than a crash.

**Negative:**

- Slight indirection at every read/write of an enum value.
- A typo in raw-value defaults silently produces wrong-but-decodeable data.

---

## Decision 15: Tolerate cross-device person-delete races

**Date**: 2026-05-11
**Status**: accepted

### Context

`Person → TripPackingItem` uses a `.deny` delete rule. This protects against local deletion of a referenced person but does nothing for the cross-device case: device A deletes a `Person`, device B writes a `TripPackingItem.person` reference, both sync. The result is a `TripPackingItem.person == nil` orphan once the deletes mirror.

### Decision

Orphaned `TripPackingItem.person == nil` is a valid runtime state. Read sites render the orphan with a placeholder avatar/name ("Unknown person"). The packing item retains its snapshot `name` and continues to function. The system does not surface the orphan as a user-visible error.

### Rationale

There is no defensible way to forbid the race short of synchronous CKShare conflict resolution, which is out of scope for Phase 1. Tolerating the orphan is consistent with AC 1.9's tolerance for dangling `masterItemID` references and matches CloudKit's eventual-consistency model.

### Alternatives Considered

- **Block person delete via subscription**: Rejected — requires CloudKit subscriptions and online-only semantics; impractical.
- **Refuse to render orphaned items**: Rejected — the user loses access to their own data because of a sync race.
- **Re-create the deleted person locally**: Rejected — implicit data restoration is surprising and breaks the user's stated intent.

### Consequences

**Positive:**

- No code path can produce an unrecoverable state from this race.
- Aligns with the `masterItemID` dangling-reference policy (AC 1.9).

**Negative:**

- A "ghost" packing item with no person owner can appear in the UI; the placeholder treatment must be explicit at every render site.

---

