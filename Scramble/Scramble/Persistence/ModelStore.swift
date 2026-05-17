import Foundation
import SwiftData
import os

@MainActor
enum ModelStore {

  nonisolated static let cloudKitContainerIdentifier = "iCloud.me.nore.ig.scramble"

  /// Phase 5 split (Decision 13). `globals` retains SwiftData's CloudKit
  /// mirror for `Person` / master lists / migration journal; `tripsLocal`
  /// is a local-only store whose CloudKit sync is driven by
  /// `TripSyncEngine`, not by SwiftData.
  ///
  /// Both schemas remain `SchemaV3`-shaped (full model list) because the
  /// deprecated V2 cross-references — `Trip.participants → Person`,
  /// `TripPackingItem.person → Person` — survive until V4 cleanup. The
  /// logical ownership table from the design document is enforced by
  /// convention: `globals.mainContext` holds globals records,
  /// `tripsLocal.mainContext` holds trip-zone records. Stage B (later)
  /// performs the actual data move.
  struct Containers {
    let globals: ModelContainer
    let tripsLocal: ModelContainer
  }

  /// Backwards-compatible single-container handle. Aliases `globals` so
  /// pre-Phase-5 call sites keep working until they migrate to the
  /// dual-container API. New trip-sync code uses `containers.tripsLocal`
  /// directly.
  static let shared: ModelContainer = containers.globals

  static let containers: Containers = makeContainers(probe: .production)

  /// Why an in-memory container was chosen. Exposed so tests can assert on
  /// the reason directly rather than inferring it from `ModelConfiguration`
  /// fields that Apple may reshape between SDK releases.
  nonisolated enum StrategyReason: Equatable, Sendable {
    case unitTest
    case uiTest
    case preview
  }

  /// Pure decision: which container should be built for the given probe?
  /// `configuration(probe:)` and `makeContainer(probe:)` both switch on
  /// this so the unit tests can pin the four branches without inspecting
  /// opaque SwiftData types.
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

  // MARK: - Legacy single-container API (still used by callers awaiting the
  // tripsLocal-aware migration).

  nonisolated static func configuration(probe: EnvironmentProbe) -> ModelConfiguration {
    globalsConfiguration(probe: probe)
  }

  static func makeContainer(probe: EnvironmentProbe) -> ModelContainer {
    makeGlobalsContainer(probe: probe)
  }

  // MARK: - Phase 5 dual-container API

  static func makeContainers(probe: EnvironmentProbe) -> Containers {
    Containers(
      globals: makeGlobalsContainer(probe: probe),
      tripsLocal: makeTripsLocalContainer(probe: probe)
    )
  }

  /// Globals container — `Person`, master lists, and migration journal.
  /// Production wiring uses SwiftData's CloudKit mirror against the
  /// private database; tests get an in-memory store. The schema includes
  /// the full V3 model list so the deprecated V2 cross-references
  /// (`Trip.participants → Person`) keep resolving until V4 cleanup.
  nonisolated static func globalsConfiguration(probe: EnvironmentProbe) -> ModelConfiguration {
    let schema = Schema(versionedSchema: SchemaV3.self)
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

  static func makeGlobalsContainer(probe: EnvironmentProbe) -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let primary = globalsConfiguration(probe: probe)
    do {
      return try ModelContainer(
        for: schema,
        migrationPlan: AppMigrationPlan.self,
        configurations: [primary]
      )
    } catch {
      let message = error.localizedDescription
      modelLogger.error(
        "[ModelStore.globals.fallback] CloudKit container construction failed; using local-only: \(message, privacy: .public)"
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
        fatalError("[ModelStore.globals] local-only fallback also failed: \(error)")
      }
    }
  }

  /// Local-only container for trip-zone entities. CloudKit sync of these
  /// records is driven by `TripSyncEngine`, not by SwiftData (Decision
  /// 13). The store URL is distinct from the globals store so the two do
  /// not collide.
  nonisolated static func tripsLocalConfiguration(probe: EnvironmentProbe) -> ModelConfiguration {
    let schema = Schema(versionedSchema: SchemaV3.self)
    switch strategy(probe: probe) {
    case .inMemory:
      return ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
      )
    case .productionCloudKit:
      let url = tripsLocalStoreURL()
      return ModelConfiguration(
        schema: schema,
        url: url,
        cloudKitDatabase: .none
      )
    }
  }

  static func makeTripsLocalContainer(probe: EnvironmentProbe) -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let primary = tripsLocalConfiguration(probe: probe)
    do {
      return try ModelContainer(
        for: schema,
        migrationPlan: AppMigrationPlan.self,
        configurations: [primary]
      )
    } catch {
      modelLogger.error(
        "[ModelStore.tripsLocal] container construction failed: \(error.localizedDescription, privacy: .public)"
      )
      // Fall back to in-memory so the app still launches; the user's
      // trip data won't persist across launches but they keep a working
      // session.
      let fallback = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
      )
      do {
        return try ModelContainer(for: schema, configurations: [fallback])
      } catch {
        fatalError("[ModelStore.tripsLocal] in-memory fallback also failed: \(error)")
      }
    }
  }

  /// On-disk URL for the production `tripsLocal` store. Lives in the
  /// app's Application Support directory next to (but separate from) the
  /// default SwiftData store so the two containers never share a file.
  nonisolated static func tripsLocalStoreURL() -> URL {
    let support =
      FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let scrambleDir = support.appendingPathComponent("Scramble", isDirectory: true)
    try? FileManager.default.createDirectory(at: scrambleDir, withIntermediateDirectories: true)
    return scrambleDir.appendingPathComponent("TripsLocal.store")
  }
}
