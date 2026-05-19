import Foundation
import Testing

@testable import Scramble

/// Phase 6 — `NotificationIdentifier` identifier-scheme coverage (Req 2.3,
/// 2.4). The identifier shape `scramble.activation.<UUID>.<phase-rawValue>`
/// is contractual: changing it would un-pair every device's pending
/// notifications from their next reconciliation pass.
@Suite("NotificationIdentifier")
struct NotificationIdentifierTests {

  // MARK: - make + parse round-trip

  @Test(
    "make → parse round-trip recovers (tripID, phase) for every Phase",
    arguments: Phase.allCases)
  func roundTripForEveryPhase(phase: Phase) {
    let tripID = UUID()
    let raw = NotificationIdentifier.make(tripID: tripID, phase: phase)
    let parsed = NotificationIdentifier.parse(raw)
    #expect(parsed?.tripID == tripID)
    #expect(parsed?.phase == phase)
  }

  @Test("make produces the documented `scramble.activation.<UUID>.<rawValue>` shape")
  func makeProducesExpectedShape() {
    let tripID = UUID()
    let raw = NotificationIdentifier.make(tripID: tripID, phase: .departureDay)
    #expect(raw == "scramble.activation.\(tripID.uuidString).\(Phase.departureDay.rawValue)")
  }

  // MARK: - parse rejects malformed input

  @Test(
    "parse returns nil for malformed inputs",
    arguments: [
      "",
      "scramble.activation",
      "scramble.activation.not-a-uuid.departureDay",
      "scramble.trip.\(UUID().uuidString).departureDay",
      "scramble.activation.\(UUID().uuidString).notAPhase",
      "scramble.activation.\(UUID().uuidString)",
      "something.else.entirely",
    ])
  func parseRejectsMalformed(raw: String) {
    #expect(NotificationIdentifier.parse(raw) == nil)
  }

  // MARK: - threadID

  @Test("threadID produces the documented `scramble.trip.<UUID>` shape")
  func threadIDShape() {
    let tripID = UUID()
    #expect(NotificationIdentifier.threadID(for: tripID) == "scramble.trip.\(tripID.uuidString)")
  }
}
