import Foundation

/// Phase 5.1 — owns the single `for await event in syncEngine.events`
/// iteration and re-broadcasts each event to every registered subscriber.
/// Production has two subscribers: `RulesEngineTriggerOrchestrator`
/// (existing) and `ZoneMigrationCoordinator` (new) — see design §
/// "TripSyncEventBus (new)".
///
/// **Lifecycle contracts:**
///   - Subscribers register their handler via `subscribeOrchestrator` /
///     `subscribeCoordinator` BEFORE `start()`. Late registrations are
///     fatal in DEBUG (via `assertionFailure`) and silently rejected in
///     release; production wires both subscribers in `ScrambleApp.init`
///     so this is a programming error.
///   - The bus does NOT buffer events. The engine's `events` stream is
///     empty at the moment `start()` returns because the engine is
///     started after `bus.start()`; events flow only afterwards.
///   - Each dispatch wraps the handler call in a `do/catch` so a
///     subscriber's thrown error is logged via `modelLogger.error` and
///     the bus continues for the other subscriber.
///   - **Handlers must be atomic or tolerate partial predecessor
///     state.** Dispatch order is fixed (orchestrator first, coordinator
///     second), so if the orchestrator handler throws mid-rule-engine-run
///     with a partial write committed, the coordinator handler still
///     receives the same event and acts on a partially updated store.
///     Today the orchestrator's rule-engine pass and the coordinator's
///     journal mutations are committed through `LocalWriteHook.commit`
///     and `globalsContext.save()` respectively — both atomic per
///     ModelContext — so a half-committed predecessor is structurally
///     impossible. Future subscribers that batch multi-step work without
///     this property must add their own catch-and-rollback or accept
///     the partial-state risk.
///   - `stop()` cancels the iteration task; used by tests.
///
/// Note: production has exactly two named subscribers. The two-slot
/// (orchestrator + coordinator) shape is deliberate — calling
/// `subscribeOrchestrator` twice replaces the previous handler in DEBUG
/// with an `assertionFailure`. This is not a fan-out-to-N bus; it is a
/// fan-out-to-two router for the two known consumers.
@MainActor
final class TripSyncEventBus {
  private let events: AsyncStream<TripSyncEvent>
  private var orchestratorHandler: (@MainActor (TripSyncEvent) throws -> Void)?
  private var coordinatorHandler: (@MainActor (TripSyncEvent) throws -> Void)?
  private var iterationTask: Task<Void, Never>?

  init(events: AsyncStream<TripSyncEvent>) {
    self.events = events
  }

  /// Register the orchestrator handler. Must be called before `start()`,
  /// and only once per bus lifetime.
  func subscribeOrchestrator(
    _ handler: @escaping @MainActor (TripSyncEvent) throws -> Void
  ) {
    if iterationTask != nil {
      assertionFailure("TripSyncEventBus: subscribeOrchestrator after start()")
      modelLogger.fault("[TripSyncEventBus] late orchestrator subscription — ignored")
      return
    }
    if orchestratorHandler != nil {
      assertionFailure("TripSyncEventBus: subscribeOrchestrator called twice")
      modelLogger.fault("[TripSyncEventBus] duplicate orchestrator subscription — overwriting")
    }
    orchestratorHandler = handler
  }

  /// Register the coordinator handler. Must be called before `start()`,
  /// and only once per bus lifetime.
  func subscribeCoordinator(
    _ handler: @escaping @MainActor (TripSyncEvent) throws -> Void
  ) {
    if iterationTask != nil {
      assertionFailure("TripSyncEventBus: subscribeCoordinator after start()")
      modelLogger.fault("[TripSyncEventBus] late coordinator subscription — ignored")
      return
    }
    if coordinatorHandler != nil {
      assertionFailure("TripSyncEventBus: subscribeCoordinator called twice")
      modelLogger.fault("[TripSyncEventBus] duplicate coordinator subscription — overwriting")
    }
    coordinatorHandler = handler
  }

  /// Begin iterating the engine event stream. Idempotent — only the
  /// first call starts the task; subsequent calls are no-ops.
  func start() {
    guard iterationTask == nil else { return }
    let orchestrator = orchestratorHandler
    let coordinator = coordinatorHandler
    iterationTask = Task { @MainActor [events] in
      for await event in events {
        Self.dispatch(event, to: orchestrator, label: "orchestrator")
        Self.dispatch(event, to: coordinator, label: "coordinator")
      }
    }
  }

  /// Test-only: cancel the iteration task so subsequent yields don't
  /// reach the registered handlers.
  func stop() {
    iterationTask?.cancel()
    iterationTask = nil
  }

  @MainActor
  private static func dispatch(
    _ event: TripSyncEvent,
    to handler: (@MainActor (TripSyncEvent) throws -> Void)?,
    label: String
  ) {
    guard let handler else { return }
    do {
      try handler(event)
    } catch {
      modelLogger.error(
        "[TripSyncEventBus] \(label, privacy: .public) handler threw: \(error.localizedDescription, privacy: .public)"
      )
    }
  }
}

extension TripSyncEventBus {
  /// Convenience overload that wires an orchestrator instance via
  /// `handle(event:)`. The bus stores a closure capturing the
  /// orchestrator weakly so deinit of the orchestrator (in tests) does
  /// not retain it through the bus.
  func subscribeOrchestrator(_ orchestrator: RulesEngineTriggerOrchestrator) {
    subscribeOrchestrator { [weak orchestrator] event in
      orchestrator?.handle(event: event)
    }
  }

  /// Convenience overload that wires the coordinator's three event
  /// handlers. The closure parses the event and dispatches to the
  /// matching coordinator entry point.
  func subscribeCoordinator(_ coordinator: ZoneMigrationCoordinator) {
    subscribeCoordinator { [weak coordinator] event in
      guard let coordinator else { return }
      switch event {
      case .zoneSaved(let zoneID):
        coordinator.handleZoneSaved(zoneID)
      case .recordsSaved(let recordIDs):
        coordinator.handleRecordsSaved(recordIDs)
      case .recordsFailed(let recordIDs, let error):
        coordinator.handleRecordsFailed(recordIDs, error: error)
      case .zoneChanged, .recordsFetched, .shareAccepted, .zoneRemoved, .error:
        break
      }
    }
  }
}
