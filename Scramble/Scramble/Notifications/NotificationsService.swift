import CloudKit
import Foundation
import SwiftData
import UserNotifications
import os

/// Phase 6 — single owner of all `UNUserNotificationCenter` interaction.
///
/// Triggered by:
/// - `ScenePhase` transitions at the WindowGroup root.
/// - `TripDeletion.delete` (after the commit succeeds).
/// - `TripEditorView` create-flow save closure (auth gate).
/// - `LocalWriteHook.commit` via `PendingChangeBroadcaster`.
/// - Authorization status flip observed on foreground re-entry.
///
/// `requestReschedule(reason:)` is the single funnel. Immediate-flush
/// reasons run the reconciler synchronously; coalesced reasons cancel
/// any in-flight 2-second timer and start a new one (Decision in
/// design.md §"Coalesce mechanics").
///
/// The reconciler is full-fleet — every trigger results in a fresh
/// `plan(trips:tasks:now:calendar:cap:)` call. Per-record classification
/// is deliberately not attempted (Decision 12).
@MainActor
final class NotificationsService: PendingChangeNotifier {

  // MARK: - Reschedule reasons

  enum ReschedReason: Sendable, Hashable {
    case appActivation
    case scenePhaseBackground
    case tripDeleted(tripID: UUID)
    case authChanged(UNAuthorizationStatus)
    case localWrite
    case tripSaved(tripID: UUID, wasInsert: Bool)

    var requiresImmediateFlush: Bool {
      switch self {
      case .appActivation, .scenePhaseBackground, .tripDeleted, .authChanged:
        return true
      case .localWrite, .tripSaved:
        return false
      }
    }
  }

  // MARK: - Observable state

  /// Surfaced to UI so the "Open Settings" affordance can read the live
  /// authorization status (Req 3.5).
  private(set) var authStatus: UNAuthorizationStatus = .notDetermined

  // MARK: - Injection points

  private let center: any NotificationCenterProtocol
  private let router: NotificationRouter
  private let tripContext: @MainActor () -> ModelContext
  private let calendar: Calendar
  private let now: @MainActor () -> Date
  private let coalesceWindow: Duration

  private var pendingCoalesce: Task<Void, Never>?

  // MARK: - Init

  init(
    center: any NotificationCenterProtocol,
    router: NotificationRouter,
    tripContext: @escaping @MainActor () -> ModelContext,
    calendar: Calendar = .autoupdatingCurrent,
    now: @escaping @MainActor () -> Date = Date.init,
    coalesceWindow: Duration = .seconds(2)
  ) {
    self.center = center
    self.router = router
    self.tripContext = tripContext
    self.calendar = calendar
    self.now = now
    self.coalesceWindow = coalesceWindow
  }

  // MARK: - Lifecycle

  /// Installs the delegate and seeds `authStatus`. Idempotent.
  func start() async {
    center.setDelegate(router)
    authStatus = await center.authorizationStatus()
  }

  // MARK: - Trip-save auth gate (Req 3.1, 3.2, 3.3)

  func requestAuthorizationIfNeeded(forTrip trip: Trip) async {
    let status = await center.authorizationStatus()
    authStatus = status
    guard status == .notDetermined else { return }
    let plans = NotificationPlanner.plan(
      trips: [trip],
      tripTasksByTripID: [:],
      now: now(),
      calendar: calendar,
      cap: 60
    )
    guard !plans.isEmpty else { return }
    let granted =
      (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    authStatus = granted ? .authorized : .denied
    if granted {
      await runReconcile()
    }
  }

  // MARK: - ScenePhase handling (Req 3.6, 4.5)

  /// Equivalent of the SwiftUI `ScenePhase` transitions the service cares
  /// about. The bridge is performed at `ScrambleApp.body` so this type
  /// — and the service itself — does not need to import SwiftUI.
  enum ScenePhaseTransition: Sendable {
    case becameActive
    case enteredBackground
  }

  func handleScenePhase(_ transition: ScenePhaseTransition) async {
    switch transition {
    case .becameActive:
      let nextStatus = await center.authorizationStatus()
      let oldStatus = authStatus
      authStatus = nextStatus
      if oldStatus != nextStatus {
        requestReschedule(reason: .authChanged(nextStatus))
      }
      requestReschedule(reason: .appActivation)
      await flushCoalesce()
    case .enteredBackground:
      requestReschedule(reason: .scenePhaseBackground)
      await flushCoalesce()
    }
  }

  // MARK: - Reschedule entry point (Req 4.3, 4.4)

  func requestReschedule(reason: ReschedReason) {
    if case .tripDeleted(let tripID) = reason {
      cancelAllForTrip(tripID: tripID)
    }
    if reason.requiresImmediateFlush {
      pendingCoalesce?.cancel()
      pendingCoalesce = nil
      Task { @MainActor in
        await runReconcile()
      }
      return
    }
    // Coalesced path.
    pendingCoalesce?.cancel()
    pendingCoalesce = Task { @MainActor [self] in
      try? await Task.sleep(for: coalesceWindow)
      guard !Task.isCancelled else { return }
      await runReconcile()
      pendingCoalesce = nil
    }
  }

  // MARK: - PendingChangeNotifier conformance

  func notifyPendingChanges(
    savedRecordIDs: [CKRecord.ID],
    deletedRecordIDs: [CKRecord.ID],
    in zoneID: CKRecordZone.ID
  ) {
    requestReschedule(reason: .localWrite)
  }

  // MARK: - Internal — reconciliation

  func flushCoalesce() async {
    guard pendingCoalesce != nil else { return }
    pendingCoalesce?.cancel()
    pendingCoalesce = nil
    await runReconcile()
  }

  func runReconcile() async {
    let status = await center.authorizationStatus()
    authStatus = status
    guard status == .authorized else {
      await cancelAllActivationNotifications()
      return
    }
    let context = tripContext()
    let plans: [ActivationPlan]
    do {
      let trips = try context.fetch(FetchDescriptor<Trip>())
      let tasks = try context.fetch(FetchDescriptor<TripTask>())
      let tasksByTripID = Dictionary(grouping: tasks) { task in
        task.trip?.id ?? UUID()
      }
      plans = NotificationPlanner.plan(
        trips: trips,
        tripTasksByTripID: tasksByTripID,
        now: now(),
        calendar: calendar,
        cap: 60
      )
    } catch {
      modelLogger.error(
        "[NotificationsService] failed to fetch trips: \(error.localizedDescription, privacy: .public)"
      )
      return
    }

    let pending = await center.pendingNotificationRequests()
    let diff = NotificationReconciler.diff(plan: plans, pending: pending)

    if !diff.toRemove.isEmpty {
      center.removePendingNotificationRequests(withIdentifiers: diff.toRemove)
    }
    for plan in diff.toAdd {
      let request = Self.makeRequest(from: plan)
      do {
        try await center.add(request)
      } catch {
        modelLogger.error(
          """
          [NotificationsService] add(request:) failed for \
          \(request.identifier, privacy: .public): \
          \(error.localizedDescription, privacy: .public)
          """
        )
        // No retry inside this pass per Req 2.5; next reconcile retries.
      }
    }
  }

  private func cancelAllActivationNotifications() async {
    let pending = await center.pendingNotificationRequests()
    let identifiers =
      pending
      .map(\.identifier)
      .filter { $0.hasPrefix("scramble.activation.") }
    if !identifiers.isEmpty {
      center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
  }

  private func cancelAllForTrip(tripID: UUID) {
    let activation = Phase.allCases.map {
      NotificationIdentifier.make(tripID: tripID, phase: $0)
    }
    center.removePendingNotificationRequests(withIdentifiers: activation)
    center.removeDeliveredNotifications(withIdentifiers: activation)
  }

  // MARK: - Request construction

  static func makeRequest(from plan: ActivationPlan) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = plan.title
    content.body = plan.body
    content.userInfo = [
      NotificationRouter.userInfoTripIDKey: plan.tripID.uuidString,
      NotificationRouter.userInfoPhaseKey: plan.phase.rawValue,
    ]
    content.threadIdentifier = NotificationIdentifier.threadID(for: plan.tripID)
    let trigger = UNCalendarNotificationTrigger(
      dateMatching: plan.fireDateComponents, repeats: false
    )
    return UNNotificationRequest(
      identifier: NotificationIdentifier.make(tripID: plan.tripID, phase: plan.phase),
      content: content,
      trigger: trigger
    )
  }
}
