import Foundation
import Testing
import UserNotifications

@testable import Scramble

/// Phase 6 — `NotificationReconciler.diff` coverage (Req 2.3). The
/// reconciler computes (add, remove) from the planner's output and the
/// device's live pending list. An identifier already present in pending
/// AND whose body matches the plan is treated as no-op so the service
/// avoids a redundant `add` call that would replace an identical request.
@Suite("NotificationReconciler")
@MainActor
struct NotificationReconcilerTests {

  // MARK: - Empty cases

  @Test("Empty plan + empty pending → empty diff")
  func emptyEmpty() {
    let diff = NotificationReconciler.diff(plan: [], pending: [])
    #expect(diff.toAdd.isEmpty)
    #expect(diff.toRemove.isEmpty)
  }

  @Test("Empty plan with stale pending → remove all pending (keyed by identifier)")
  func emptyPlanRemovesStale() {
    let id1 = NotificationIdentifier.make(tripID: UUID(), phase: .dayBefore)
    let id2 = NotificationIdentifier.make(tripID: UUID(), phase: .returnDay)
    let pending: [UNNotificationRequest] = [
      Self.request(identifier: id1, body: "stale"),
      Self.request(identifier: id2, body: "stale"),
    ]
    let diff = NotificationReconciler.diff(plan: [], pending: pending)
    #expect(Set(diff.toRemove) == Set([id1, id2]))
    #expect(diff.toAdd.isEmpty)
  }

  // MARK: - No-op detection (body match)

  @Test("Identifier present + body identical → no add, no remove")
  func bodyMatchIsNoOp() {
    let tripID = UUID()
    let phase: Phase = .dayBefore
    let body = NotificationPlanner.body(
      phase: phase, outstandingTasks: 2
    )
    let plan = ActivationPlan(
      tripID: tripID, phase: phase,
      fireDateComponents: Self.someComponents(),
      outstandingTaskCount: 2,
      body: body,
      title: "Iceland"
    )
    let pending: [UNNotificationRequest] = [
      Self.request(
        identifier: NotificationIdentifier.make(tripID: tripID, phase: phase), body: body)
    ]
    let diff = NotificationReconciler.diff(plan: [plan], pending: pending)
    #expect(diff.toAdd.isEmpty)
    #expect(diff.toRemove.isEmpty)
  }

  @Test("Identifier present + body differs → add (replaces by identifier), no remove")
  func bodyDiffersTriggersAdd() {
    let tripID = UUID()
    let phase: Phase = .departureDay
    let plan = ActivationPlan(
      tripID: tripID, phase: phase,
      fireDateComponents: Self.someComponents(),
      outstandingTaskCount: 3,
      body: "3 outstanding task(s) for 'Departure day'",
      title: "Iceland"
    )
    let pending: [UNNotificationRequest] = [
      Self.request(
        identifier: NotificationIdentifier.make(tripID: tripID, phase: phase),
        body: "2 outstanding task(s) for 'Departure day'"
      )
    ]
    let diff = NotificationReconciler.diff(plan: [plan], pending: pending)
    #expect(diff.toAdd == [plan])
    #expect(diff.toRemove.isEmpty)
  }

  // MARK: - Defensive cleanup

  @Test(
    "Pending requests with foreign identifiers in the activation namespace get cleaned up")
  func foreignActivationIdentifiersCleanedUp() {
    let plan = ActivationPlan(
      tripID: UUID(), phase: .dayBefore,
      fireDateComponents: Self.someComponents(),
      outstandingTaskCount: 0,
      body: "'Day before' has started",
      title: "T"
    )
    let strayID =
      "scramble.activation.\(UUID().uuidString).\(Phase.returnDay.rawValue)"
    let pending: [UNNotificationRequest] = [
      Self.request(identifier: strayID, body: "stale")
    ]
    let diff = NotificationReconciler.diff(plan: [plan], pending: pending)
    #expect(diff.toRemove == [strayID])
    #expect(diff.toAdd == [plan])
  }

  @Test(
    "Pending requests outside the activation namespace are ignored (not touched, not added back)")
  func foreignNamespaceIgnored() {
    let plan = ActivationPlan(
      tripID: UUID(), phase: .dayBefore,
      fireDateComponents: Self.someComponents(),
      outstandingTaskCount: 0,
      body: "'Day before' has started",
      title: "T"
    )
    let pending: [UNNotificationRequest] = [
      Self.request(identifier: "some.unrelated.notification.id", body: "leave me alone")
    ]
    let diff = NotificationReconciler.diff(plan: [plan], pending: pending)
    #expect(diff.toRemove.isEmpty)
    #expect(diff.toAdd == [plan])
  }

  // MARK: - Order stability

  @Test("toAdd is returned in plan-input order")
  func toAddPreservesPlanOrder() {
    let plans = (0..<4).map { _ in
      ActivationPlan(
        tripID: UUID(), phase: .dayBefore,
        fireDateComponents: Self.someComponents(),
        outstandingTaskCount: 0,
        body: "x",
        title: "T"
      )
    }
    let diff = NotificationReconciler.diff(plan: plans, pending: [])
    #expect(diff.toAdd == plans)
  }

  @Test("toRemove is returned in pending-input order")
  func toRemovePreservesPendingOrder() {
    let id1 = NotificationIdentifier.make(tripID: UUID(), phase: .dayBefore)
    let id2 = NotificationIdentifier.make(tripID: UUID(), phase: .returnDay)
    let id3 = NotificationIdentifier.make(tripID: UUID(), phase: .departureDay)
    let pending = [
      Self.request(identifier: id1, body: "x"),
      Self.request(identifier: id2, body: "x"),
      Self.request(identifier: id3, body: "x"),
    ]
    let diff = NotificationReconciler.diff(plan: [], pending: pending)
    #expect(diff.toRemove == [id1, id2, id3])
  }

  // MARK: - Helpers

  static func request(identifier: String, body: String) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.body = body
    return UNNotificationRequest(
      identifier: identifier, content: content, trigger: nil
    )
  }

  static func someComponents() -> DateComponents {
    var comps = DateComponents()
    comps.year = 2026
    comps.month = 7
    comps.day = 1
    comps.hour = 9
    comps.minute = 0
    return comps
  }
}
