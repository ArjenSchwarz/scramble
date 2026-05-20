import Foundation

/// Phase 6 — identifier scheme for activation notifications (Req 2.3,
/// Req 2.4).
///
/// The identifier `scramble.activation.<tripID-UUID>.<phase-rawValue>` is
/// the `UNNotificationRequest.identifier` so a given `(tripID, phase)` is
/// unique and replaceable. The thread identifier
/// `scramble.trip.<tripID-UUID>` groups all of a trip's pending and
/// delivered notifications together in Notification Center.
///
/// `parse` is the inverse of `make`. It returns `nil` for any string that
/// does not exactly match the four-segment shape
/// (`scramble.activation.<UUID>.<rawValue>`), has an unparseable UUID in
/// the trip slot, or has a phase raw value that does not correspond to a
/// `Phase` case.
nonisolated enum NotificationIdentifier {

  private static let activationPrefix = "scramble.activation"
  private static let threadPrefix = "scramble.trip"

  static func make(tripID: UUID, phase: Phase) -> String {
    "\(activationPrefix).\(tripID.uuidString).\(phase.rawValue)"
  }

  static func threadID(for tripID: UUID) -> String {
    "\(threadPrefix).\(tripID.uuidString)"
  }

  static func parse(_ raw: String) -> (tripID: UUID, phase: Phase)? {
    let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
    // Expect exactly four parts: "scramble", "activation", "<UUID>", "<rawValue>".
    guard parts.count == 4,
      parts[0] == "scramble",
      parts[1] == "activation",
      let tripID = UUID(uuidString: String(parts[2])),
      let phase = Phase(rawValue: String(parts[3]))
    else {
      return nil
    }
    return (tripID, phase)
  }
}
