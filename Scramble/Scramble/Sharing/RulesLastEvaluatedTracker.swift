import CloudKit
import Foundation

/// Phase 5 — observable per-trip "rules last evaluated" tracker. Records
/// the timestamp of the most recent `TripSyncEvent.zoneChanged` the
/// participant has observed; Trip Detail reads it to render the
/// "Rules last evaluated {relative-time}" subline
/// (Req [8.8](../../specs/phase-5-cloudkit-sharing/requirements.md#8.8)).
///
/// The rules engine itself runs only on the owner's device
/// (Decision 3); participants infer "the owner re-evaluated" from each
/// inbound zone-change event. Self-originated events are filtered upstream
/// in `RulesEngineTriggerOrchestrator` and never reach the tracker.
@MainActor
@Observable
final class RulesLastEvaluatedTracker {
  /// `tripID → most recent observed zone-change time`. Direct dictionary
  /// access keeps the surface minimal — Trip Detail reads via
  /// `time(forTrip:)` and the orchestrator writes via `record(tripID:at:)`.
  private(set) var times: [UUID: Date] = [:]

  init() {}

  func record(tripID: UUID, at date: Date = .now) {
    times[tripID] = date
  }

  func time(forTrip tripID: UUID) -> Date? {
    times[tripID]
  }

  /// Pulls a trip ID out of a `trip-<uuid>` zone name. Returns `nil` for
  /// foreign zone names so the tracker silently ignores events not
  /// originated by Phase 5 trip zones.
  static func tripID(fromZoneName name: String) -> UUID? {
    guard name.hasPrefix("trip-") else { return nil }
    return UUID(uuidString: String(name.dropFirst("trip-".count)))
  }
}
