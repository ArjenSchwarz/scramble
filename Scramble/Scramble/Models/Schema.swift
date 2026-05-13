import Foundation
import SwiftData
import os

// MARK: - SchemaV1 (pre-Phase-3, frozen)

/// Pre-Phase-3 shape. `SchemaV1.TripTask` is frozen here so the migration into
/// `SchemaV2` is a real SwiftData diff (lightweight stage) rather than a
/// metadata-identical no-op.
nonisolated enum SchemaV1: VersionedSchema {
  nonisolated static var versionIdentifier: Schema.Version {
    Schema.Version(1, 0, 0)
  }

  nonisolated static var models: [any PersistentModel.Type] {
    [
      Trip.self,
      Person.self,
      MasterTaskItem.self,
      MasterPackingItem.self,
      SchemaV1.TripTask.self,
      TripPackingItem.self,
    ]
  }

  @Model
  final class TripTask {
    var id: UUID = UUID()
    @Relationship var trip: Trip?
    var masterItemID: UUID?
    var name: String = ""
    var phaseRaw: String = Phase.weeksBefore.rawValue
    var isCompleted: Bool = false
    var sourceRaw: String = ItemSource.manual.rawValue
    var currentlyMatchesRules: Bool = true
    var pinnedByUser: Bool = false

    init() {}
  }
}

// MARK: - SchemaV2 (current — adds assigneePersonID and userDeletedOnThisTrip)

/// Phase 3 schema. Adds `assigneePersonID` (Req 9.1, Decision 9: stored as
/// `UUID?` rather than `@Relationship`) and `userDeletedOnThisTrip` (Req 9.1,
/// Decision 7: per-trip soft-delete flag for rule-driven tasks).
nonisolated enum SchemaV2: VersionedSchema {
  nonisolated static var versionIdentifier: Schema.Version {
    Schema.Version(2, 0, 0)
  }

  nonisolated static var models: [any PersistentModel.Type] {
    [
      Trip.self,
      Person.self,
      MasterTaskItem.self,
      MasterPackingItem.self,
      SchemaV2.TripTask.self,
      TripPackingItem.self,
    ]
  }

  @Model
  final class TripTask {
    var id: UUID = UUID()
    @Relationship var trip: Trip?
    var masterItemID: UUID?
    var name: String = ""
    var phaseRaw: String = Phase.weeksBefore.rawValue
    var isCompleted: Bool = false
    var sourceRaw: String = ItemSource.manual.rawValue
    var currentlyMatchesRules: Bool = true
    var pinnedByUser: Bool = false
    /// Decision 9 — value reference, dangling references tolerated.
    var assigneePersonID: UUID?
    /// Decision 7 — set by Phase 3 delete affordance; never set by the engine.
    ///
    /// Stored as `Bool?` so SwiftData's lightweight migration can backfill old
    /// records with a NULL column without tripping the Core Data validation
    /// path (`Code=1570 ... is a required value`). The public API on the model
    /// remains non-Optional via the `userDeletedOnThisTrip` computed bridge
    /// below, which treats `nil` as `false`. The storage default is `nil`,
    /// not `false`, because SwiftData/CoreData on iOS 26.4 asserts when a
    /// nullable column also declares a non-nil Swift default. `private(set)`
    /// keeps the bridge as the single mutation path; SwiftData still
    /// observes writes from inside the `userDeletedOnThisTrip` setter.
    private(set) var userDeletedOnThisTripRaw: Bool?

    init(
      id: UUID = UUID(),
      trip: Trip? = nil,
      masterItemID: UUID? = nil,
      name: String = "",
      phase: Phase = .weeksBefore,
      isCompleted: Bool = false,
      source: ItemSource = .manual,
      currentlyMatchesRules: Bool = true,
      pinnedByUser: Bool = false,
      assigneePersonID: UUID? = nil,
      userDeletedOnThisTrip: Bool = false
    ) {
      self.id = id
      self.trip = trip
      self.masterItemID = masterItemID
      self.name = name
      self.phaseRaw = phase.rawValue
      self.isCompleted = isCompleted
      self.sourceRaw = source.rawValue
      self.currentlyMatchesRules = currentlyMatchesRules
      self.pinnedByUser = pinnedByUser
      self.assigneePersonID = assigneePersonID
      self.userDeletedOnThisTripRaw = userDeletedOnThisTrip
    }
  }
}

// MARK: - Current type alias

/// Application code uses `TripTask`; the alias keeps every existing call site
/// compiling unchanged after the schema bump.
typealias TripTask = SchemaV2.TripTask

extension SchemaV2.TripTask {
  var phase: Phase {
    get { Phase(rawValue: phaseRaw) ?? .weeksBefore }
    set { phaseRaw = newValue.rawValue }
  }

  var source: ItemSource {
    get { ItemSource(rawValue: sourceRaw) ?? .manual }
    set { sourceRaw = newValue.rawValue }
  }

  /// Non-Optional bridge over `userDeletedOnThisTripRaw`. See the storage
  /// declaration on `SchemaV2.TripTask` for why the underlying column is
  /// nullable; callers should treat this property as the canonical surface.
  var userDeletedOnThisTrip: Bool {
    get { userDeletedOnThisTripRaw ?? false }
    set { userDeletedOnThisTripRaw = newValue }
  }
}

// MARK: - Migration plan

nonisolated enum AppMigrationPlan: SchemaMigrationPlan {
  nonisolated static var schemas: [any VersionedSchema.Type] {
    [SchemaV1.self, SchemaV2.self]
  }

  nonisolated static var stages: [MigrationStage] {
    // Lightweight migration adds the new columns. `assigneePersonID` is `UUID?`
    // and `userDeletedOnThisTripRaw` is `Bool?`, so migrated pre-V2 rows
    // surface as `nil` on the underlying column and as the Swift default on
    // the model facade (`userDeletedOnThisTrip` returns `false`).
    [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
  }
}

// MARK: - Logger

nonisolated let modelLogger = Logger(
  subsystem: "me.nore.ig.Scramble",
  category: "models"
)
