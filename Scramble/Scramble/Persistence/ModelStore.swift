import Foundation
import SwiftData
import os

@MainActor
enum ModelStore {
  static let shared: ModelContainer = makeContainer(probe: .production)

  nonisolated static let cloudKitContainerIdentifier = "iCloud.me.nore.ig.scramble"

  /// Why an in-memory container was chosen. Exposed so tests can assert on the
  /// reason directly rather than inferring it from `ModelConfiguration` fields
  /// that Apple may reshape between SDK releases.
  nonisolated enum StrategyReason: Equatable, Sendable {
    case unitTest
    case uiTest
    case preview
  }

  /// Pure decision: which container should be built for the given probe?
  /// `configuration(probe:)` and `makeContainer(probe:)` both switch on this so
  /// the unit tests can pin the four branches without inspecting opaque
  /// SwiftData types.
  nonisolated enum Strategy: Equatable, Sendable {
    case inMemory(reason: StrategyReason)
    case productionCloudKit
  }

  nonisolated static func strategy(probe: EnvironmentProbe) -> Strategy {
    if probe.isTest { return .inMemory(reason: .unitTest) }
    if probe.isUITestHost { return .inMemory(reason: .uiTest) }
    if probe.isPreview { return .inMemory(reason: .preview) }
    return .productionCloudKit
  }

  nonisolated static func configuration(probe: EnvironmentProbe) -> ModelConfiguration {
    let schema = Schema(versionedSchema: SchemaV1.self)
    switch strategy(probe: probe) {
    case .inMemory:
      return ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
      )
    case .productionCloudKit:
      return ModelConfiguration(
        schema: schema,
        cloudKitDatabase: .private(cloudKitContainerIdentifier)
      )
    }
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
