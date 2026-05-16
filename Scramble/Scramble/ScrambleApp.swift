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
  private let rulesLastEvaluatedTracker: RulesLastEvaluatedTracker

  init() {
    let containers = ModelStore.containers
    let tripsLocal = containers.tripsLocal.mainContext
    let globals = containers.globals.mainContext
    let engine = TripSyncEngine(
      context: tripsLocal,
      container: CKContainer(identifier: ModelStore.cloudKitContainerIdentifier)
    )
    let service = Self.makeSharingService(engine: engine, tripsLocal: tripsLocal)
    let tracker = RulesLastEvaluatedTracker()
    self.sharingService = service
    self.syncEngine = engine
    self.rulesLastEvaluatedTracker = tracker
    self.migrationCoordinator = ZoneMigrationCoordinator(
      globalsContext: globals,
      tripsLocalContext: tripsLocal,
      driver: TripSyncEngineZoneMigrationDriver(syncEngine: engine)
    )
    self.triggerOrchestrator = Self.makeTriggerOrchestrator(
      service: service, tripsLocal: tripsLocal, tracker: tracker
    )
    AppDelegate.environment = AppDelegate.Environment(
      sharingService: service,
      notificationRouter: RemoteNotificationRouter(
        fetcher: TripSyncEngineNotificationFetcher(syncEngine: engine)
      )
    )
    #if DEBUG
      UITestSeed.applyIfRequested(
        globalsContainer: ModelStore.shared,
        tripsLocalContainer: ModelStore.containers.tripsLocal
      )
    #endif
    Self.runColdLaunchEnginePass(service: service)
  }

  private static func makeSharingService(
    engine: TripSyncEngine, tripsLocal: ModelContext
  ) -> any SharingService {
    #if DEBUG
      if EnvironmentProbe.production.isUITestHost {
        return UITestSharingService()
      }
    #endif
    return CloudKitSharingService(
      container: engine.container,
      context: tripsLocal,
      syncEngine: engine
    )
  }

  private static func makeTriggerOrchestrator(
    service: any SharingService,
    tripsLocal: ModelContext,
    tracker: RulesLastEvaluatedTracker
  ) -> RulesEngineTriggerOrchestrator {
    let runner = RulesEngineRunner(
      context: tripsLocal, ownerIdentity: service.ownerIdentity(forTrip:)
    )
    return RulesEngineTriggerOrchestrator(
      run: { tripID in
        let descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == tripID })
        guard let trip = try? tripsLocal.fetch(descriptor).first else { return }
        _ = try? runner.runForTrip(trip)
      },
      tracker: tracker
    )
  }

  /// Cold-launch engine pass over master-listed trips. Runs against the
  /// globals container — pre-Stage-B trips still live there and the
  /// ownership gate is permissive for trips without a `TripZoneState`.
  private static func runColdLaunchEnginePass(service: any SharingService) {
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
      MigrationGate(prepare: prepareLaunch, content: rootContent)
    }
    .modelContainer(ModelStore.containers.globals)
  }

  @MainActor
  private func prepareLaunch() async {
    // Stage A → engine startup ordering (design § "Stage A → engine
    // startup ordering"). Skip the CloudKit-touching startup in
    // test / UI-test / preview branches to keep tests deterministic.
    let probe = EnvironmentProbe.production
    let isHeadless = probe.isTest || probe.isUITestHost || probe.isPreview
    guard !isHeadless else { return }
    do {
      try migrationCoordinator.enqueueAll()
      try migrationCoordinator.runStageB()
    } catch {
      modelLogger.error(
        "[MigrationGate] Stage B failed: \(error.localizedDescription, privacy: .public)"
      )
    }
    syncEngine.start()
    let orchestrator = triggerOrchestrator
    let engine = syncEngine
    Task { @MainActor in
      for await event in engine.events {
        orchestrator.handle(event: event)
      }
    }
  }

  @ViewBuilder
  private func rootContent() -> some View {
    RootView()
      .environment(\.theme, .midnightAtlas)
      .environment(\.tripsLocalContainer, ModelStore.containers.tripsLocal)
      .environment(\.sharingService, sharingService)
      .environment(\.rulesLastEvaluatedTracker, rulesLastEvaluatedTracker)
      .environment(\.zoneMigrationCoordinator, migrationCoordinator)
  }
}
