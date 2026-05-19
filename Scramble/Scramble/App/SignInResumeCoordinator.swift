import CloudKit
import Foundation
import UIKit

/// Phase 5.1 — re-runs `ZoneMigrationCoordinator` enqueue + Stage B when
/// iCloud becomes available after launch. See design §
/// "SignInResumeCoordinator (new)" and Req 4.8.
///
/// Observed signals (any one fires `runResumeIfNeeded`):
///   - `NSNotification.Name.CKAccountChanged` — the primary signal.
///   - `UIScene.didActivateNotification` — fallback for the documented
///     case where `CKAccountChanged` is coalesced or missed during a
///     background → foreground transition.
///
/// Concurrency: a single in-flight `Task` reference plus a
/// `pendingReplay` flag collapses storm-fire to at most one trailing
/// replay. New invocations either start the task (when nil) or set
/// `pendingReplay = true` (when non-nil); the in-flight task checks +
/// consumes the flag in a tail loop before clearing `inFlight`.
@MainActor
final class SignInResumeCoordinator {
  private let isCloudAvailable: () -> Bool
  private let resume: () async -> Void
  private var inFlight: Task<Void, Never>?
  private var pendingReplay: Bool = false
  private var observers: [NSObjectProtocol] = []

  /// Production init — wires the coordinator's check + resume action.
  /// The `CKContainer` is implicit in `migrationCoordinator.isCloudAvailable`
  /// today; if a future revision needs direct `CKContainer.accountStatus()`
  /// re-checks distinct from the coordinator's check, add it back here.
  convenience init(migrationCoordinator: ZoneMigrationCoordinator) {
    self.init(
      isCloudAvailable: { migrationCoordinator.isCloudAvailable() },
      resume: { @MainActor in
        do {
          try migrationCoordinator.enqueueAll()
          try migrationCoordinator.runStageB()
        } catch {
          modelLogger.error(
            "[SignInResumeCoordinator] resume failed: \(error.localizedDescription, privacy: .public)"
          )
        }
      }
    )
  }

  /// Test-friendly init — accepts the two closures the production path
  /// derives from `migrationCoordinator`. Tests use this to drive the
  /// storm-collapse logic without a real coordinator.
  init(
    isCloudAvailable: @escaping () -> Bool,
    resume: @escaping () async -> Void
  ) {
    self.isCloudAvailable = isCloudAvailable
    self.resume = resume
  }

  deinit {
    inFlight?.cancel()
    for token in observers {
      NotificationCenter.default.removeObserver(token)
    }
  }

  /// Install the notification observers and perform an immediate
  /// `accountStatus()` re-check (handles "account became available
  /// before observer installed"). Idempotent — calling twice does not
  /// double-install observers.
  func start() {
    if !observers.isEmpty { return }
    let center = NotificationCenter.default
    // Hop the notification handler into a @MainActor Task rather than
    // `MainActor.assumeIsolated`. The latter is correct today because
    // we register with `queue: .main`, but `OperationQueue.main` is not
    // formally the MainActor's executor — if CloudKit ever changes the
    // delivery queue (or Swift 6 strict-checking tightens the
    // assumeIsolated trap), the silent trap is a regression hazard.
    // Spawning a Task is unconditionally safe; the small overhead is
    // negligible for these rare notifications.
    let onChange = center.addObserver(
      forName: .CKAccountChanged,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.runResumeIfNeeded() }
    }
    let onActivate = center.addObserver(
      forName: UIScene.didActivateNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.runResumeIfNeeded() }
    }
    observers = [onChange, onActivate]
    runResumeIfNeeded()
  }

  /// Single entry point for resume — checks availability, collapses
  /// storm-fire via `inFlight` + `pendingReplay`. Guarantees ≤1
  /// trailing replay per in-flight run regardless of trigger volume.
  ///
  /// Triggers that arrive DURING the trailing replay would otherwise be
  /// orphaned: they see `inFlight != nil` and set `pendingReplay`, but
  /// the in-flight task is about to exit and would clear the flag.
  /// After clearing `inFlight` we re-check the flag and, if a late
  /// trigger landed, re-enter via a fresh `runResumeIfNeeded()` call.
  /// Each round still bounds itself to ≤1 trailing replay; sustained
  /// storms chain rounds rather than absorbing forever.
  func runResumeIfNeeded() {
    guard isCloudAvailable() else { return }
    if inFlight != nil {
      pendingReplay = true
      return
    }
    inFlight = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.resume()
      if self.pendingReplay && self.isCloudAvailable() {
        self.pendingReplay = false
        await self.resume()
      }
      // Capture-then-clear so we observe triggers that landed during
      // the trailing replay above. Clearing `inFlight` first lets the
      // re-entry start a new task instead of just flipping the flag.
      let hadLateTrigger = self.pendingReplay
      self.pendingReplay = false
      self.inFlight = nil
      if hadLateTrigger {
        self.runResumeIfNeeded()
      }
    }
  }
}
