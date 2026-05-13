import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Migration from `SchemaV1.TripTask` to `SchemaV2.TripTask` via
/// `AppMigrationPlan`'s lightweight stage.
///
/// The on-disk data-round-trip flavour of this test (seed via a V1 container,
/// reopen with V2 + migration plan, assert new fields default to nil/false) is
/// intentionally skipped: SwiftData panics when two `@Model` types named
/// `TripTask` (one per versioned schema) coexist in the same test process,
/// which is unavoidable when other suites use V2 containers in parallel.
///
/// What the production migration ACTUALLY relies on:
///   1. `AppMigrationPlan` lists both versions and a lightweight stage between them.
///   2. `SchemaV2.TripTask` stores `userDeletedOnThisTrip` via a nullable
///      backing column (`userDeletedOnThisTripRaw: Bool?`) so the lightweight
///      migration adds the column as NULL on pre-V2 rows without tripping the
///      Core Data "required value" validation, and the non-Optional facade
///      reads `nil` as `false`.
///   3. `SchemaV2.TripTask.assigneePersonID` is already `UUID?`, so migration
///      leaves pre-V2 rows with `nil`.
///   4. The persistent entity name is the same string (`"TripTask"`) under
///      both versions — required for SwiftData to even consider the lightweight
///      diff valid, and for CloudKit not to orphan existing records.
///
/// The tests below cover (1), (3), and (4). Round-trip of (2) on real on-disk
/// data is exercised manually when bumping the schema; see decision_log Decision 11.
@Suite("SchemaV2 migration", .serialized)
@MainActor
struct SchemaV2MigrationTests {

  // MARK: - Migration plan shape

  @Test("AppMigrationPlan declares both versions and a stage from V1 → V2")
  func planLinksV1AndV2() {
    let schemaIDs = AppMigrationPlan.schemas.map(ObjectIdentifier.init)
    #expect(schemaIDs.contains(ObjectIdentifier(SchemaV1.self)))
    #expect(schemaIDs.contains(ObjectIdentifier(SchemaV2.self)))
    #expect(AppMigrationPlan.stages.count == 1)
  }

  @Test("Fresh V2 records default to assigneePersonID == nil and userDeletedOnThisTrip == false")
  func freshV2RecordsDefaultCorrectly() throws {
    let schema = Schema(versionedSchema: SchemaV2.self)
    let config = ModelConfiguration(
      schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(
      for: schema,
      migrationPlan: AppMigrationPlan.self,
      configurations: [config]
    )
    let context = container.mainContext

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    let task = TripTask(trip: trip, name: "Pack")
    context.insert(task)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<TripTask>())
    #expect(fetched.count == 1)
    let stored = try #require(fetched.first)
    #expect(stored.assigneePersonID == nil)
    #expect(stored.userDeletedOnThisTrip == false)
  }

  // MARK: - Entity name stability

  @Test("Persistent entity name resolves identically across versions (both are 'TripTask')")
  func entityNameIsStableAcrossVersions() {
    // A future SwiftData behaviour change that qualified entity names with their
    // enclosing enum (e.g. "SchemaV1.TripTask") would orphan existing on-disk and
    // CloudKit records. Pin the resolved name here so the regression is loud.
    let v1Schema = Schema(versionedSchema: SchemaV1.self)
    let v2Schema = Schema(versionedSchema: SchemaV2.self)
    let v1TripTaskName = v1Schema.entities.first(where: { $0.name.contains("TripTask") })?.name
    let v2TripTaskName = v2Schema.entities.first(where: { $0.name.contains("TripTask") })?.name
    #expect(v1TripTaskName == "TripTask")
    #expect(v2TripTaskName == "TripTask")
    #expect(v1TripTaskName == v2TripTaskName)
  }
}
