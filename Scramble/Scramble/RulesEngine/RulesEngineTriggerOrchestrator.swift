import CloudKit
import Foundation

/// Phase 5 — bridges `TripSyncEngine.events` to the rules engine.
///
/// Adds the new "CloudKit-received change to a trip-owned record on the
/// owner's device" trigger
/// (Req [8.6](../../../specs/phase-5-cloudkit-sharing/requirements.md#8.6)).
/// The orchestrator filters self-originated events so the owner's engine
/// does not re-run on its own writes (echo-suppression, design § "engine
/// ownership gate").
///
/// Wiring (production): `ScrambleApp` constructs one orchestrator after
/// `MigrationGate` releases. The orchestrator spawns a `Task` that
/// iterates `syncEngine.events` and forwards each event through
/// `handle(event:)`. The `run` closure is `RulesEngineRunner.runForTrip`
/// wrapped to look up the matching `Trip` by ID.
@MainActor
final class RulesEngineTriggerOrchestrator {
  let run: (UUID) -> Void

  init(run: @escaping (UUID) -> Void) {
    self.run = run
  }

  /// Apply a single `TripSyncEvent`. Self-originated `.zoneChanged`
  /// events are dropped per the design's echo-suppression rule; remote
  /// ones trigger `run(tripID)` after parsing the trip ID from the
  /// zone name (`trip-<uuid>`).
  func handle(event: TripSyncEvent) {
    switch event {
    case .zoneChanged(let zoneID, _, let isSelfOriginated):
      guard !isSelfOriginated else { return }
      guard let tripID = parseTripID(from: zoneID.zoneName) else { return }
      run(tripID)
    case .recordsFetched, .shareAccepted, .zoneRemoved, .error:
      break
    }
  }

  private func parseTripID(from zoneName: String) -> UUID? {
    guard zoneName.hasPrefix("trip-") else { return nil }
    let suffix = zoneName.dropFirst("trip-".count)
    return UUID(uuidString: String(suffix))
  }
}
