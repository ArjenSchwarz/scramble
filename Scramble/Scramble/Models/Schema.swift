import Foundation
import SwiftData
import os

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
      TripTask.self,
      TripPackingItem.self
    ]
  }
}

nonisolated enum AppMigrationPlan: SchemaMigrationPlan {
  nonisolated static var schemas: [any VersionedSchema.Type] {
    [SchemaV1.self]
  }

  nonisolated static var stages: [MigrationStage] {
    []
  }
}

nonisolated let modelLogger = Logger(
  subsystem: "me.nore.ig.Scramble",
  category: "models"
)
