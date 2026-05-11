# Persistence layer

## Files

- `Scramble/Scramble/Models/Schema.swift` — `SchemaV1` (VersionedSchema, all six entities), `AppMigrationPlan` (no stages in v1), shared `modelLogger` for the persistence layer.
- `Scramble/Scramble/Models/{Trip,Person,MasterTaskItem,MasterPackingItem,TripTask,TripPackingItem}.swift` — `@Model` entities with Codable-bridge extensions for `attributes`, `conditions`, `phase`, `source`, `state`.
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
