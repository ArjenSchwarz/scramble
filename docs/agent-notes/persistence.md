# Persistence layer

## Files

- `Scramble/Scramble/Models/Schema.swift` — `SchemaV1` (pre-Phase-3 frozen) and `SchemaV2` (current — adds `TripTask.assigneePersonID` + `TripTask.userDeletedOnThisTripRaw`), `AppMigrationPlan` with a single `.lightweight` stage `V1 → V2`, `typealias TripTask = SchemaV2.TripTask`, and shared `modelLogger`.
- `Scramble/Scramble/Models/{Trip,Person,MasterTaskItem,MasterPackingItem,TripPackingItem}.swift` — `@Model` entities with Codable-bridge extensions for `attributes`, `conditions`, `phase`, `source`, `state`. `TripTask` now lives inside `Schema.swift` (both V1 and V2 variants).
- `Scramble/Scramble/Persistence/EnvironmentProbe.swift` — value type wrapping `environment` + `arguments`; `production` reads `ProcessInfo.processInfo`. Branches: `isTest`, `isUITestHost`, `isPreview`.
- `Scramble/Scramble/Persistence/ModelStore.swift` — `@MainActor enum`. `shared` evaluates `makeContainer(probe: .production)` once. `configuration(probe:)` is `nonisolated` and unit-tested.

## Relationship layout (SwiftData)

Inverse pairs:

| Owning side (declares `inverse:`) | Non-owning side |
|---|---|
| `Trip.participants` → `inverse: \Person.trips`, `deleteRule: .nullify` | `Person.trips` |
| `Trip.tasks` → `inverse: \TripTask.trip`, `deleteRule: .cascade` | `TripTask.trip` |
| `Trip.packingItems` → `inverse: \TripPackingItem.trip`, `deleteRule: .cascade` | `TripPackingItem.trip` |
| `Person.tripPackingItems` → `inverse: \TripPackingItem.person`, `deleteRule: .deny` | `TripPackingItem.person` |
| `Person.masterPackingItems` → `inverse: \MasterPackingItem.person`, `deleteRule: .deny` | `MasterPackingItem.person` |

Inverse and deleteRule are colocated on the same `@Relationship`. The non-owning side is a plain `@Relationship var` with no arguments; SwiftData resolves the inverse automatically.

## SwiftData `.deny` is declared but not enforced — see decision_log Decision 16

SwiftData iOS 26.4 does not throw on `context.save()` after deleting a Person with live references, even with `.deny` correctly declared. The rule is kept in the schema as defense-in-depth and intent; primary enforcement happens in the UI guard at the delete affordance (req 9.7, task 22). The SchemaTests verify the inverse-traversal reads (`person.tripPackingItems`, `person.masterPackingItems`) that the UI uses.

## Codable-bridge contract

- `TripAttributes` (blob) and `ItemConditions` (blob) round-trip via `JSONEncoder/Decoder`. Decode failures fall back to defaults (`TripAttributes()`, `.always`) and log via `modelLogger.error(...)` — never crash.
- Enum-valued properties (`Phase`, `ItemSource`, `PackingState`) are stored as `String` rawValues with `*Raw` storage and computed-property bridges. Unknown raw values fall back to the documented default. This pattern sidesteps CloudKit schema-promotion friction (Decision 14).
- `TripTask.userDeletedOnThisTrip` (Phase 3, Decision 7) is exposed as non-Optional `Bool` via a computed bridge, but the underlying column `userDeletedOnThisTripRaw` is `Bool?`. The nullable storage is mandatory on iOS 26.4: SwiftData/CoreData asserts (`Code=1570 ... is a required value`) when a lightweight-migrated column has a non-Optional Swift default — see Phase 3 decision log Decision 12. Treat the `userDeletedOnThisTrip` computed property as the canonical surface; the `*Raw` storage exists only because the migration path requires it.

## Versioned schema policy

- Phase 3 (Decision 11) established versioned schemas as policy going forward. Each schema change — additive or not — gets a new `SchemaV<N>` and an explicit `MigrationStage` in `AppMigrationPlan`, even when SwiftData would tolerate in-place edits.
- `TripTask` is the first model with V1 and V2 variants. Other models (`Trip`, `Person`, `MasterTaskItem`, `MasterPackingItem`, `TripPackingItem`) are referenced from both versions but are unchanged.
- Each `VersionedSchema.models` array must list its own model references; `MigrationStage.lightweight` compares metadata between versions, so if both versions point at the same Swift type there is no diff and the migration is a no-op.

## SchemaV2 migration test deferral

- `SchemaV2MigrationTests` verifies plan shape (`schemas`, `stages`, lightweight stage typing) but **does not** perform a real on-disk V1→V2 round-trip. Two `@Model` types named `TripTask` cannot coexist in the same test process: SwiftData resolves entity-class lookup by class name, so seeding a `SchemaV1.TripTask` store and re-opening with `SchemaV2.TripTask` in one binary collides. The functional check (new fields default correctly on migrated rows) is exercised indirectly via fresh-V2 inserts in other tests. If a regression in the migration step ever ships, it will surface on first launch against an existing on-device store rather than in CI.

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
