import Foundation
import SwiftData
import os

@MainActor
enum ModelStore {
  static let shared: ModelContainer = makeContainer(probe: .production)

  nonisolated static let cloudKitContainerIdentifier = "iCloud.me.nore.ig.scramble"

  nonisolated static func configuration(probe: EnvironmentProbe) -> ModelConfiguration {
    let schema = Schema(versionedSchema: SchemaV1.self)
    if probe.isTest || probe.isUITestHost || probe.isPreview {
      return ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
      )
    }
    return ModelConfiguration(
      schema: schema,
      cloudKitDatabase: .private(cloudKitContainerIdentifier)
    )
  }

  static func makeContainer(probe: EnvironmentProbe) -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV1.self)
    let primary = configuration(probe: probe)
    do {
      return try ModelContainer(
        for: schema,
        migrationPlan: AppMigrationPlan.self,
        configurations: [primary]
      )
    } catch {
      let message = error.localizedDescription
      modelLogger.error(
        "[ModelStore.fallback] CloudKit container construction failed; using local-only: \(message, privacy: .public)"
      )
      let fallback = ModelConfiguration(
        schema: schema,
        cloudKitDatabase: .none
      )
      do {
        return try ModelContainer(
          for: schema,
          migrationPlan: AppMigrationPlan.self,
          configurations: [fallback]
        )
      } catch {
        fatalError("[ModelStore] local-only fallback also failed: \(error)")
      }
    }
  }
}
