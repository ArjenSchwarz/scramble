import Foundation
import UserNotifications

/// Phase 6 — diffs the planner's expected plan list against the device's
/// pending `UNNotificationRequest`s (Req 2.3).
///
/// Two outputs:
/// - `toAdd`: plans whose `(tripID, phase)` identifier is either missing
///   from pending OR whose pending body differs from the plan body.
///   Adding via `UNUserNotificationCenter.add` with the same identifier
///   replaces an existing request, so a body change does not need a
///   separate remove.
/// - `toRemove`: identifiers in pending whose `(tripID, phase)` is not
///   present in the plan. Limited to identifiers in the activation
///   namespace (prefix `scramble.activation.`) so unrelated app-wide
///   notifications are left alone.
///
/// Order stability — `toAdd` follows the plan's order, `toRemove` follows
/// pending's order.
nonisolated enum NotificationReconciler {

  struct Diff: Equatable, Sendable {
    let toAdd: [ActivationPlan]
    let toRemove: [String]
  }

  static func diff(plan: [ActivationPlan], pending: [UNNotificationRequest]) -> Diff {
    let activationPrefix = "scramble.activation."

    // Index pending requests by identifier, restricted to the activation
    // namespace. Anything outside that namespace is ignored.
    var pendingByID: [String: UNNotificationRequest] = [:]
    var pendingOrder: [String] = []
    for request in pending {
      guard request.identifier.hasPrefix(activationPrefix) else { continue }
      pendingByID[request.identifier] = request
      pendingOrder.append(request.identifier)
    }

    var planIDs: Set<String> = []
    var toAdd: [ActivationPlan] = []
    for entry in plan {
      let identifier = NotificationIdentifier.make(tripID: entry.tripID, phase: entry.phase)
      planIDs.insert(identifier)
      if let existing = pendingByID[identifier], existing.content.body == entry.body {
        // No-op — identifier present and body identical.
        continue
      }
      toAdd.append(entry)
    }

    // Identifiers in pending but not in plan — remove.
    let toRemove = pendingOrder.filter { !planIDs.contains($0) }
    return Diff(toAdd: toAdd, toRemove: toRemove)
  }
}
