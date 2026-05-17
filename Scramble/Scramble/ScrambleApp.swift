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
  /// Phase 5.1 — the single chokepoint for every `tripsLocal` save. The
  /// hook's notifier is `TripSyncEngine`; trip-domain SwiftUI surfaces
  /// reach it via `@Environment(\.localWriteHook)` and call
  /// `hook.commit(_:)` instead of `modelContext.save()`.
  private let localWriteHook: LocalWriteHook

  init() {
    let containers = ModelStore.containers
    let tripsLocal = containers.tripsLocal.mainContext
    let globals = containers.globals.mainContext
    let engine = TripSyncEngine(
      context: tripsLocal,
      container: CKContainer(identifier: ModelStore.cloudKitContainerIdentifier)
    )
    let hook = LocalWriteHook(notifier: engine)
    let service = Self.makeSharingService(engine: engine, tripsLocal: tripsLocal, hook: hook)
    let tracker = RulesLastEvaluatedTracker()
    self.sharingService = service
    self.syncEngine = engine
    self.rulesLastEvaluatedTracker = tracker
    self.localWriteHook = hook
    self.migrationCoordinator = ZoneMigrationCoordinator(
      globalsContext: globals,
      tripsLocalContext: tripsLocal,
      driver: TripSyncEngineZoneMigrationDriver(syncEngine: engine)
    )
    self.triggerOrchestrator = Self.makeTriggerOrchestrator(
      service: service, tripsLocal: tripsLocal, tracker: tracker, hook: localWriteHook
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
    Self.runColdLaunchEnginePass(service: service, hook: localWriteHook)
  }

  private static func makeSharingService(
    engine: TripSyncEngine, tripsLocal: ModelContext, hook: LocalWriteHook
  ) -> any SharingService {
    #if DEBUG
      if EnvironmentProbe.production.isUITestHost {
        return UITestSharingService()
      }
    #endif
    return CloudKitSharingService(
      container: engine.container,
      context: tripsLocal,
      syncEngine: engine,
      hook: hook
    )
  }

  private static func makeTriggerOrchestrator(
    service: any SharingService,
    tripsLocal: ModelContext,
    tracker: RulesLastEvaluatedTracker,
    hook: LocalWriteHook
  ) -> RulesEngineTriggerOrchestrator {
    let runner = RulesEngineRunner(
      context: tripsLocal,
      mastersContext: ModelStore.containers.globals.mainContext,
      ownerIdentity: service.ownerIdentity(forTrip:),
      hook: hook
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

  /// Cold-launch engine pass over master-listed trips. Phase 5.1: runs
  /// against the `tripsLocal` container — that is where Trip rows now
  /// live; the ownership gate remains permissive for trips without a
  /// `TripZoneState`.
  private static func runColdLaunchEnginePass(
    service: any SharingService, hook: LocalWriteHook
  ) {
    do {
      _ = try RulesEngineRunner(
        context: ModelStore.containers.tripsLocal.mainContext,
        mastersContext: ModelStore.containers.globals.mainContext,
        ownerIdentity: service.ownerIdentity(forTrip:),
        hook: hook
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
      .environment(\.globalsContainer, ModelStore.containers.globals)
      .environment(\.tripsLocalContainer, ModelStore.containers.tripsLocal)
      .environment(\.localWriteHook, localWriteHook)
      .environment(\.sharingService, sharingService)
      .environment(\.rulesLastEvaluatedTracker, rulesLastEvaluatedTracker)
      .environment(\.zoneMigrationCoordinator, migrationCoordinator)
  }
}
