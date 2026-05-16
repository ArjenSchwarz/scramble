//
//  ScrambleApp.swift
//  Scramble
//
//  Created by Arjen Schwarz on 10/5/2026.
//

import CloudKit
import SwiftData
import SwiftUI
import os

@main
struct ScrambleApp: App {
  /// Phase 5 — share-acceptance + silent-push delegate. The actual policy
  /// (`SharingService`, `RemoteNotificationRouter`) is set on
  /// `AppDelegate.environment` from `init` below.
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  /// Production wiring constructed once at launch. Held in `let`
  /// storage so the closures handed to `MigrationGate` and the
  /// environment do not capture mutable state.
  private let sharingService: any SharingService
  private let syncEngine: TripSyncEngine
  private let migrationCoordinator: ZoneMigrationCoordinator
  private let triggerOrchestrator: RulesEngineTriggerOrchestrator

  init() {
    let containers = ModelStore.containers
    let tripsLocalContext = containers.tripsLocal.mainContext
    let globalsContext = containers.globals.mainContext

    let engine = TripSyncEngine(
      context: tripsLocalContext,
      container: CKContainer(identifier: ModelStore.cloudKitContainerIdentifier)
    )
    let service = CloudKitSharingService(
      container: engine.container,
      context: tripsLocalContext,
      syncEngine: engine
    )
    let migrationDriver = TripSyncEngineZoneMigrationDriver(syncEngine: engine)
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: globalsContext,
      tripsLocalContext: tripsLocalContext,
      driver: migrationDriver
    )
    let notificationFetcher = TripSyncEngineNotificationFetcher(syncEngine: engine)
    let router = RemoteNotificationRouter(fetcher: notificationFetcher)

    self.sharingService = service
    self.syncEngine = engine
    self.migrationCoordinator = coordinator

    // The orchestrator runs the engine for a single trip; we look up the
    // trip on demand via the tripsLocal context.
    let runner = RulesEngineRunner(
      context: tripsLocalContext,
      ownerIdentity: service.ownerIdentity(forTrip:)
    )
    self.triggerOrchestrator = RulesEngineTriggerOrchestrator { tripID in
      let descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == tripID })
      guard let trip = try? tripsLocalContext.fetch(descriptor).first else { return }
      _ = try? runner.runForTrip(trip)
    }

    AppDelegate.environment = AppDelegate.Environment(
      sharingService: service,
      notificationRouter: router
    )

    #if DEBUG
      UITestSeed.applyIfRequested(to: ModelStore.shared)
    #endif
    // Cold-launch engine pass over master-listed trips. Runs against the
    // globals container — pre-Stage-B trips still live there and the
    // ownership gate is permissive for trips without a `TripZoneState`.
    do {
      _ = try RulesEngineRunner(
        context: ModelStore.shared.mainContext,
        ownerIdentity: service.ownerIdentity(forTrip:)
      ).runForAllNonPastTrips()
    } catch {
      modelLogger.error(
        "[RulesEngine.cold-launch-failed] error=\(String(describing: error), privacy: .public)"
      )
    }
  }

  var body: some Scene {
    WindowGroup {
      MigrationGate(
        prepare: { [migrationCoordinator, syncEngine, triggerOrchestrator] in
          do {
            try migrationCoordinator.enqueueAll()
            try migrationCoordinator.runStageB()
          } catch {
            modelLogger.error(
              "[MigrationGate] Stage B failed: \(error.localizedDescription, privacy: .public)"
            )
          }
          // Stage A → engine startup ordering (design § "Stage A → engine
          // startup ordering"). Skip the CloudKit-touching startup in test
          // / UI-test / preview branches to keep tests deterministic.
          let probe = EnvironmentProbe.production
          let isHeadless = probe.isTest || probe.isUITestHost || probe.isPreview
          if !isHeadless {
            syncEngine.start()
            Task { @MainActor in
              for await event in syncEngine.events {
                triggerOrchestrator.handle(event: event)
              }
            }
          }
        }
      ) {
        RootView()
          .environment(\.theme, .midnightAtlas)
          .environment(\.tripsLocalContainer, ModelStore.containers.tripsLocal)
          .environment(\.sharingService, sharingService)
      }
    }
    .modelContainer(ModelStore.containers.globals)
  }
}
