//
//  ScrambleApp.swift
//  Scramble
//
//  Created by Arjen Schwarz on 10/5/2026.
//

import CloudKit
import SwiftData
import SwiftUI
import UserNotifications
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
  /// Phase 5.1 — single-iteration multicast of `syncEngine.events` to
  /// both the orchestrator and the migration coordinator. Constructed
  /// in `init` so subscribers register before `start()` is called from
  /// `prepareLaunch`.
  private let eventBus: TripSyncEventBus
  /// Phase 5.1 — drives `migrationCoordinator.enqueueAll + runStageB`
  /// on every iCloud sign-in transition. `MigrationGate.prepare` also
  /// routes through this so a single in-flight invocation collapses
  /// gate-startup + account-changed + scene-activated triggers.
  private let signInResumeCoordinator: SignInResumeCoordinator
  /// Phase 6 — local activation notification orchestrator. Owns
  /// `UNUserNotificationCenter` interaction; wired into `LocalWriteHook`
  /// via `PendingChangeBroadcaster` (Decision 12).
  private let notificationsService: NotificationsService
  /// Phase 6 — `UNUserNotificationCenterDelegate` for activation taps.
  /// Holds the 1-slot pendingRoute consumed by `RootView`.
  private let activationRouter: NotificationRouter

  init() {
    let containers = ModelStore.containers
    let tripsLocal = containers.tripsLocal.mainContext
    let globals = containers.globals.mainContext
    let cloudContainer = CKContainer(identifier: ModelStore.cloudKitContainerIdentifier)
    let engine = TripSyncEngine(context: tripsLocal, container: cloudContainer)
    let wiring = Self.makeNotificationsWiring(engine: engine)
    let router = wiring.router
    let notifications = wiring.service
    let hook = wiring.hook
    let service = Self.makeSharingService(engine: engine, tripsLocal: tripsLocal, hook: hook)
    let tracker = RulesLastEvaluatedTracker()
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: globals,
      tripsLocalContext: tripsLocal,
      driver: TripSyncEngineZoneMigrationDriver(syncEngine: engine)
    )
    let orchestrator = Self.makeTriggerOrchestrator(
      service: service, tripsLocal: tripsLocal, tracker: tracker, hook: hook
    )
    let bus = TripSyncEventBus(events: engine.events)
    bus.subscribeOrchestrator(orchestrator)
    bus.subscribeCoordinator(coordinator)
    let resume = SignInResumeCoordinator(migrationCoordinator: coordinator)

    self.sharingService = service
    self.syncEngine = engine
    self.rulesLastEvaluatedTracker = tracker
    self.localWriteHook = hook
    self.migrationCoordinator = coordinator
    self.triggerOrchestrator = orchestrator
    self.eventBus = bus
    self.signInResumeCoordinator = resume
    self.notificationsService = notifications
    self.activationRouter = router

    AppDelegate.environment = AppDelegate.Environment(
      sharingService: service,
      notificationRouter: RemoteNotificationRouter(
        fetcher: TripSyncEngineNotificationFetcher(syncEngine: engine)
      ),
      activationRouter: router,
      notificationsService: notifications
    )
    UNUserNotificationCenter.current().delegate = router
    #if DEBUG
      UITestSeed.applyIfRequested(
        globalsContainer: ModelStore.shared,
        tripsLocalContainer: ModelStore.containers.tripsLocal
      )
    #endif
    Self.runColdLaunchEnginePass(service: service, hook: localWriteHook)
  }

  /// Phase 6 — constructs the local activation notification stack and
  /// the `LocalWriteHook` wrapping a `PendingChangeBroadcaster` that
  /// fans every commit out to both the sync engine and the
  /// notifications service (Decision 12).
  struct NotificationsWiring {
    let router: NotificationRouter
    let service: NotificationsService
    let hook: LocalWriteHook
  }

  private static func makeNotificationsWiring(
    engine: TripSyncEngine
  ) -> NotificationsWiring {
    let router = NotificationRouter()
    let notifications = NotificationsService(
      center: UNUserNotificationCenter.current(),
      tripContext: { ModelStore.containers.tripsLocal.mainContext }
    )
    let broadcaster = PendingChangeBroadcaster(children: [engine, notifications])
    let hook = LocalWriteHook(notifier: broadcaster)
    return NotificationsWiring(router: router, service: notifications, hook: hook)
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

  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      MigrationGate(prepare: prepareLaunch, content: rootContent)
        .onOpenURL { url in
          guard let route = NotificationRouter.route(from: url) else { return }
          activationRouter.enqueue(route)
        }
    }
    .modelContainer(ModelStore.containers.globals)
    .onChange(of: scenePhase) { previous, current in
      // Phase 6 Req 3.6 / 4.5 — bridge SwiftUI's ScenePhase to the
      // notifications service. The service has no SwiftUI imports;
      // we map .active → .becameActive and .background →
      // .enteredBackground here.
      if previous != .active, current == .active {
        Task { @MainActor in
          await notificationsService.handleScenePhase(.becameActive)
        }
      } else if previous == .active, current == .background {
        Task { @MainActor in
          await notificationsService.handleScenePhase(.enteredBackground)
        }
      }
    }
  }

  @MainActor
  private func prepareLaunch() async {
    // Stage A → engine startup ordering (design § "Stage A → engine
    // startup ordering"). Skip the CloudKit-touching startup in
    // test / UI-test / preview branches to keep tests deterministic.
    let probe = EnvironmentProbe.production
    let isHeadless = probe.isTest || probe.isUITestHost || probe.isPreview
    guard !isHeadless else { return }

    // Bus subscribers were registered in init(); start the iteration
    // first so any events the engine emits as it starts up land on
    // both the orchestrator and the migration coordinator.
    eventBus.start()
    // Route the initial resume through the same single in-flight
    // pipeline that observes CKAccountChanged / scene-activated. This
    // collapses MigrationGate startup + later sign-in flips to one
    // serial pipeline (design § "SignInResumeCoordinator").
    signInResumeCoordinator.start()
    // Back-stop visibility: log when the migration journal accumulates
    // beyond a sane bound (design § "Data Models" — known non-goal of
    // automatic cleanup). Failure-to-count is itself a regression
    // signal — surface the error rather than swallowing it.
    do {
      let count = try migrationCoordinator.journalCount()
      if count > 100 {
        modelLogger.warning(
          "[MigrationGate] MigrationJournalEntry rows=\(count) — back-stop threshold exceeded"
        )
      }
    } catch {
      modelLogger.error(
        "[MigrationGate] journal back-stop count failed: \(error.localizedDescription, privacy: .public)"
      )
    }
    // Capture fresh-state before `start()` so a reinstalled device (empty
    // local trips store, no persisted engine state) explicitly pulls its
    // trip zones back down rather than waiting on an unprompted automatic
    // sync (T-1670). Detached so the migration gate releases promptly;
    // restored rows land reactively as the fetch applies them.
    let needsInitialFetch = syncEngine.needsInitialFetch()
    syncEngine.start()
    if needsInitialFetch {
      Task { @MainActor in await syncEngine.fetchChangesOnLaunch() }
    }
    // Phase 6 — seed `authStatus` so the "Open Settings" affordance can
    // render `.denied` on cold launch (before any scene-phase transition
    // fires). The `UNUserNotificationCenter.delegate` is installed at
    // init time so a cold-launch tap that arrives before this runs is
    // still routed correctly.
    await notificationsService.start()
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
      .environment(\.notificationsService, notificationsService)
      .environment(\.activationRouter, activationRouter)
      .environment(\.notificationAuthStatus, notificationsService.authStatusHolder)
  }
}
