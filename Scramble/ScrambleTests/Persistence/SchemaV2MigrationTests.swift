import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Migration from `SchemaV1.TripTask` to `SchemaV2.TripTask` via
/// `AppMigrationPlan`'s lightweight stage.
///
/// On-disk data round-trips (seeding via a V1 container and reopening with V2,
/// or seeding via a V2 container and reopening with V3) are intentionally
/// skipped. SwiftData panics when two `@Model` types named `TripTask`
/// (`SchemaV1.TripTask` / `SchemaV2.TripTask` / `SchemaV3.TripTask`) coexist
/// in the same test process. As of Phase 5, two-version migration tests can
/// only verify plan shape; fresh-record default-value coverage moves to
/// `SchemaV3MigrationTests` (which uses the active V3 container exclusively).
///
/// What the production V1 → V2 migration ACTUALLY relies on:
///   1. `AppMigrationPlan` lists both versions and a lightweight stage between them.
///   2. `SchemaV2.TripTask` stores `userDeletedOnThisTrip` via a nullable
///      backing column (`userDeletedOnThisTripRaw: Bool?`) so the lightweight
///      migration adds the column as NULL on pre-V2 rows without tripping the
///      Core Data "required value" validation.
///   3. `SchemaV2.TripTask.assigneePersonID` is already `UUID?`, so migration
///      leaves pre-V2 rows with `nil`.
///   4. The persistent entity name is the same string (`"TripTask"`) under
///      both versions — required for SwiftData to even consider the lightweight
///      diff valid, and for CloudKit not to orphan existing records.
///
/// The plan-shape test below covers (1). Item (4) — entity-name stability —
/// is now exercised exclusively by `SchemaV3MigrationTests` since
/// constructing two `Schema(versionedSchema:)` values for forked TripTasks
/// (V1 alongside V2) crashes the test process; the equivalent V2-vs-V3
/// stability check is enough as a regression guard. (2) and (3) are
/// exercised on real on-disk data when the schema is bumped on device.
@Suite("SchemaV2 migration", .serialized)
@MainActor
struct SchemaV2MigrationTests {

  @Test("AppMigrationPlan declares V1 and V2 (plus the V2 → V3 stage Phase 5 added)")
  func planLinksV1AndV2() {
    let schemaIDs = AppMigrationPlan.schemas.map(ObjectIdentifier.init)
    #expect(schemaIDs.contains(ObjectIdentifier(SchemaV1.self)))
    #expect(schemaIDs.contains(ObjectIdentifier(SchemaV2.self)))
    #expect(AppMigrationPlan.stages.count >= 1)
  }
}
