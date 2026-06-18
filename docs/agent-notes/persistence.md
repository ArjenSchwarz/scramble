# Persistence layer

## Files

- `Scramble/Scramble/Models/Schema.swift` — `SchemaV1` (pre-Phase-3 frozen), `SchemaV2` (Phase 3 — `TripTask.assigneePersonID` + `TripTask.userDeletedOnThisTripRaw` added), `SchemaV3` (Phase 5 — adds `TripPersonSnapshot`, `TripZoneState`, `MigrationJournalEntry` plus `Trip.participantSnapshots`/`tripZoneID`/`ckRecordSystemFields`, `TripPackingItem.personSnapshotID`/`ckRecordSystemFields`, and `TripTask.ckRecordSystemFields`). **`SchemaV3` is the current schema — there is no `SchemaV4`.** Phase 6's `Trip.countryCode` and the `personSnapshot` → `personSnapshotID` value-reference change both ride on V3 via automatic lightweight inference (see "Shared top-level classes can't express property-only schema bumps" below). `AppMigrationPlan` runs `.lightweight V1 → V2` then `.custom V2 → V3` (whose `didMigrate` calls `SchemaV3MigrationStage.backfillSnapshots(in:)`). Top-level `TripTask` is the single class shared by V2 and V3 — see "Why TripTask is no longer forked" below. `typealias TripPersonSnapshot = SchemaV3.TripPersonSnapshot` and similar for `TripZoneState`/`MigrationJournalEntry`.
- `Scramble/Scramble/Persistence/Migrations/SchemaV3MigrationStage.swift` — Phase 5 Stage A custom step. Backfills `TripPersonSnapshot` rows from V2 `Trip.participants` and links `TripPackingItem.personSnapshotID`. Idempotent and offline-safe (no CloudKit).
- `Scramble/Scramble/Models/{Trip,Person,MasterTaskItem,MasterPackingItem,TripPackingItem}.swift` — `@Model` entities with Codable-bridge extensions for `attributes`, `conditions`, `state`, `source`. `Trip` and `TripPackingItem` carry the V3 additive fields directly; `TripTask` now lives inside `Schema.swift` as a single top-level class.
- `Scramble/Scramble/Persistence/EnvironmentProbe.swift` — value type wrapping `environment` + `arguments`; `production` reads `ProcessInfo.processInfo`. Branches: `isTest`, `isUITestHost`, `isPreview`.
- `Scramble/Scramble/Persistence/ModelStore.swift` — `@MainActor enum`. `shared` evaluates `makeContainer(probe: .production)` once. `configuration(probe:)` is `nonisolated` and unit-tested.

## Relationship layout (SwiftData)

Inverse pairs:

| Owning side (declares `inverse:`) | Non-owning side |
|---|---|
| `Trip.participants` → `inverse: \Person.trips`, `deleteRule: .nullify` | `Person.trips` |
| `Trip.tasks` → `inverse: \TripTask.trip`, `deleteRule: .cascade` | `TripTask.trip` |
| `Trip.packingItems` → `inverse: \TripPackingItem.trip`, `deleteRule: .cascade` | `TripPackingItem.trip` |
| `Person.tripPackingItems` → `inverse: \TripPackingItem.person`, `deleteRule: .nullify` | `TripPackingItem.person` |
| `Person.masterPackingItems` → `inverse: \MasterPackingItem.person`, `deleteRule: .nullify` | `MasterPackingItem.person` |

Inverse and deleteRule are colocated on the same `@Relationship`. The non-owning side is a plain `@Relationship var` with no arguments; SwiftData resolves the inverse automatically.

To-many relationships on `Trip` and `Person` are declared as Optional arrays (`[T]? = []`). CloudKit integration requires every relationship to be Optional — non-Optional to-many arrays trigger `NSCocoaErrorDomain Code=134060` (`"CloudKit integration requires that all relationships be optional"`) at `ModelContainer` construction, blocking app launch on a real device. Read sites consequently coalesce via `?? []`.

## Person delete-guard lives in the UI (req 9.7 / Decision 16)

CloudKit does not support the `.deny` delete rule, so `Person.tripPackingItems` and `Person.masterPackingItems` use `.nullify`. SwiftData's `.deny` rule did not throw on `context.save()` on iOS 26.4 either, so even when the schema declared `.deny` the actual enforcement always lived in the UI guard at the delete affordance via `PersonDeleteBlocker`. The `SchemaTests` verify the inverse-traversal reads (`person.tripPackingItems`, `person.masterPackingItems`) that the UI uses.

## Codable-bridge contract

- `TripAttributes` (blob) and `ItemConditions` (blob) round-trip via `JSONEncoder/Decoder`. Decode failures fall back to defaults (`TripAttributes()`, `.always`) and log via `modelLogger.error(...)` — never crash.
- Enum-valued properties (`Phase`, `ItemSource`, `PackingState`) are stored as `String` rawValues with `*Raw` storage and computed-property bridges. Unknown raw values fall back to the documented default. This pattern sidesteps CloudKit schema-promotion friction (Decision 14).
- `TripTask.userDeletedOnThisTrip` (Phase 3, Decision 7) is exposed as non-Optional `Bool` via a computed bridge, but the underlying column `userDeletedOnThisTripRaw` is `Bool?`. The nullable storage is mandatory on iOS 26.4: SwiftData/CoreData asserts (`Code=1570 ... is a required value`) when a lightweight-migrated column has a non-Optional Swift default — see Phase 3 decision log Decision 12. Treat the `userDeletedOnThisTrip` computed property as the canonical surface; the `*Raw` storage exists only because the migration path requires it.

## Versioned schema policy

- Phase 3 (Decision 11) established versioned schemas as policy going forward. Each schema change — additive or not — gets a new `SchemaV<N>` and an explicit `MigrationStage` in `AppMigrationPlan`, even when SwiftData would tolerate in-place edits.
- `SchemaV1.TripTask` is the only forked variant in the binary; from V2 onwards `TripTask` is a single top-level `@Model`. Other models (`Trip`, `Person`, `MasterTaskItem`, `MasterPackingItem`, `TripPackingItem`) are top-level and referenced by V1/V2/V3.
- Each `VersionedSchema.models` array must list every entity its model graph reaches via relationships. Phase 5: top-level `Trip` declares `participantSnapshots: [TripPersonSnapshot]?`, so V1.models and V2.models must include `SchemaV3.TripPersonSnapshot.self` (otherwise SwiftData crashes during schema construction). Pre-V3 stores leave the snapshot table empty.
- `MigrationStage.lightweight` compares metadata between versions; if both versions point at the same Swift type there is no diff and the migration is a no-op for that entity. The V2 → V3 lightweight diff is metadata-identical for `Trip`/`TripTask`/`TripPackingItem`. SwiftData's automatic column inference adds the V3 fields to V2-era stores at first open because every new column is `Optional` with a `nil` default.

## Why TripTask is no longer forked (Phase 5 update)

Phase 3 froze `SchemaV1.TripTask` as a separate class so the V1 → V2 lightweight diff was a real diff. Phase 5 was originally written the same way (a frozen `SchemaV2.TripTask` alongside a new `SchemaV3.TripTask` carrying `ckRecordSystemFields`), but two `@Model` types with the same simple name `"TripTask"` coexisting in one test process panics SwiftData's cascade traversal on iOS 26.4. The crash is order-dependent — `cascadeTripToTasks` (Trip-with-tasks delete + save) deterministically traps in suite mode while passing in isolation — but cascade-traversal panics in SwiftData internals are not safely workaroundable from the model side.

The compromise: `TripTask` is a single top-level class shared by V2 and V3. The V2 → V3 lightweight diff for `TripTask` becomes metadata-identical (no-op), and SwiftData adds the new `ckRecordSystemFields` column on first V3 open via Core Data's automatic column inference. This is safe because the column is `Optional` with `nil` default. `SchemaV1.TripTask` remains forked so the V1 → V2 lightweight diff has real columns to add (`assigneePersonID`, `userDeletedOnThisTripRaw`).

If a future schema bump needs a non-additive column change on `TripTask`, the forked-class trick is no longer available. Options at that point: (a) gain coverage by switching to a `MigrationStage.custom` that hand-writes the column transition, (b) defer the change until Apple's resolution of the iOS 26.4 cascade panic, or (c) accept that one-process tests can't exercise both old and new shapes simultaneously and isolate the migration test.

## SchemaV3 + Stage A migration test deferral

- `SchemaV3MigrationTests` verifies plan shape (`schemas` includes V3, `stages` declares V2→V3 custom) and V3-default behaviour against a V3 container. It does not exercise on-disk V2 → V3 round-trip.
- `SchemaV3MigrationStageTests` exercises `SchemaV3MigrationStage.backfillSnapshots(in:)` directly against a V3 container seeded with V2-shaped data (trips with `participants` set, packing items with `person` set, no V3 snapshot rows). This is the production code path the `.custom` `didMigrate` closure calls — it just runs against a V3-shaped store created in-memory rather than a freshly-migrated one.
- `SchemaV2MigrationTests` is now a single plan-shape assertion. The Phase-3 `freshV2RecordsDefaultCorrectly` test was removed because it constructed a `SchemaV2` container in the same process as Phase-5 tests using V3 containers — see "Why TripTask is no longer forked" above. The defaults that test verified are now covered by the equivalent `SchemaV3MigrationTests` checks.

## Trip.participantSnapshots is one-way (no inverse)

`Trip.participantSnapshots` is declared as `@Relationship(deleteRule: .nullify) var participantSnapshots: [TripPersonSnapshot]? = []` — no `inverse:` keypath. The companion `TripPersonSnapshot.trip` is a one-way `@Relationship var trip: Trip?`. The two are not paired; setting one does not auto-update the other. The design (Decision 7) called for a paired cascade, but SwiftData's cascade traversal on iOS 26.4 panics when the trip-deletion path reaches the snapshot ↔ packing-item nullify chain — the same crash class that drove the `TripTask` consolidation above. Snapshot lifetime is therefore enforced by the snapshot-maintenance routine and an explicit trip-deletion sweep instead of relying on the relationship rule. Code that needs the back-collection on `Trip` can use `participantSnapshots` for reads but must maintain both sides on writes.

SwiftData auto-pairs `participantSnapshots` ↔ `TripPersonSnapshot.trip` by type (one unambiguous candidate on each side), so CloudKit accepts them as a valid inverse pair even without an explicit `inverse:` keypath.

## TripPackingItem.personSnapshot is a value reference, not a relationship (phase 5/6 bugfix — supersedes Decision 7's relationship form)

`TripPackingItem` stores `personSnapshotID: UUID?` (a value reference, like `TripTask.assigneePersonID`), **not** a `@Relationship var personSnapshot`. The `personSnapshot` computed property (in the `extension TripPackingItem` bridge block) resolves the ID in-memory via `trip?.participantSnapshots`, falling back to a `modelContext` fetch by ID when the trip-side array isn't wired (e.g. a freshly decoded `CKRecord`, or a snapshot reachable only via the one-way `TripPersonSnapshot.trip` back-link). The computed bridge lives in an extension so the `@Model` macro never treats it as a stored relationship.

Why it had to change: the original `@Relationship var personSnapshot: TripPersonSnapshot?` had no inverse (`TripPersonSnapshot` has no `[TripPackingItem]` collection, and adding one re-creates the iOS 26.4 snapshot↔item cascade panic). The `globals` container mirrors the *full* model list to CloudKit (`cloudKitDatabase: .private`), and SwiftData's CloudKit mirror **rejects any relationship without an inverse** at store load (`NSCocoaErrorDomain 134060 ... requires that all relationships have an inverse: TripPackingItem: personSnapshot`). That fired only on a real device with an iCloud account (tests and the simulator use `cloudKitDatabase: .none`), where it dropped `globals` to the local-only fallback and silently disabled iCloud sync for `Person`/master lists. A value reference has no inverse requirement, satisfies CloudKit, and sidesteps the cascade panic. Predicates must use the stored `personSnapshotID` (computed properties can't appear in `#Predicate`); writers set `personSnapshotID` (or pass a snapshot to the `init`, which stores `.id`); readers use the `personSnapshot` bridge.

## Shared top-level classes can't express property-only schema bumps (no SchemaV4)

Adding a property to a top-level `@Model` shared across versions (`Trip`, `TripTask`, `TripPackingItem`) changes *every* version's view of that class simultaneously, because they all reference the one live class. A new `SchemaV<N>` whose only difference from `V<N-1>` is such a property is **byte-identical at the metadata level** — SwiftData computes the version checksum purely from structure, not from `versionIdentifier`. Registering both in the migration plan fails with `NSInvalidArgumentException: Duplicate version checksums across stages detected` the moment an older on-disk store forces the plan to traverse that stage (a fresh store at the current version short-circuits the check, which is why the in-memory tests didn't catch it).

Phase 6 originally added `SchemaV4` for `Trip.countryCode` and hit this on-device. The fix: `countryCode` lives on the current `Trip` and is part of `SchemaV3`; SwiftData adds the column via automatic lightweight inference (Optional, `nil` default), the same mechanism already used for `ckRecordSystemFields`. The `personSnapshot` → `personSnapshotID` change rides on V3 the same way. **A schema change that only adds/alters properties on a shared top-level class is NOT a new version — only changes to the `models` array (new/removed entity types, as in V2 → V3) produce a distinct checksum and a valid stage.** A property change that genuinely needs a versioned migration would require either forking the class (blocked by the iOS 26.4 cascade panic — see "Why TripTask is no longer forked") or a `.custom` stage keyed off a new entity type.

This also invalidates the plan, recorded in several frozen Phase-5/5.1 spec docs, to remove the deprecated V2 relationships (`Trip.participants`, `TripPackingItem.person`) "in a future `SchemaV4`": removing a property from a shared top-level class is the same structural-on-a-shared-class change and cannot be a distinct version either. Those columns therefore stay as inert dead storage unless/until a `.custom` migration keyed off a new entity type is warranted — not worth it on their own.

## Test environment detection

The probe is injectable; `ModelStore.configuration(probe:)` is `nonisolated` so tests can call it without main-actor isolation. The probe branches:

| Context | Trigger |
|---|---|
| Unit tests | `environment["XCTestConfigurationFilePath"] != nil` |
| UI test host | launch arguments contain `-uitest` followed by `"1"` |
| SwiftUI Previews | `environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"` |

The first three branches return `isStoredInMemoryOnly: true, cloudKitDatabase: .none`. The fallthrough returns `cloudKitDatabase: .private("iCloud.me.nore.ig.scramble")`.

`ModelStore.shared` tries CloudKit; on throw, logs via `os_log(.error)` with the `[ModelStore.fallback]` marker and constructs a local-only fallback. If the fallback also throws, `fatalError`. The container is `@MainActor static let` (one-time evaluation at first access).

## Gotchas

- `@Model` classes inherit MainActor isolation under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Tests that touch them need `@MainActor` on the suite/test.
- `Schema(versionedSchema: SchemaV1.self)` is the canonical constructor. The variadic `ModelContainer(for: Trip.self, …)` form also works but bypasses the VersionedSchema declaration.
- `SchemaV1`, `AppMigrationPlan`, and `modelLogger` are file-scope `nonisolated` so they can be referenced from value types in any context.
- `Person.initial` returns `String(name.first!).uppercased()` or `"?"` for empty names. Returns the full grapheme cluster (incl. ZWJ-joined emoji); uppercasing emoji returns the emoji unchanged.
- The duplicate test-run behaviour seen in `xcodebuild test` output (each test reported twice) is benign — Swift Testing's discovery interacts with XCTest's, but assertions only fire once.
