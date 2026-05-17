import CloudKit
import Foundation
import Testing

@testable import Scramble

/// Phase 5 — covers the participant-side "Rules last evaluated" data
/// path (Req [8.8](../../../specs/phase-5-cloudkit-sharing/requirements.md#8.8)).
///
/// The orchestrator records a timestamp for each non-self-originated
/// zone-change event; Trip Detail reads the tracker to render the
/// subline. Self-originated events are filtered upstream and must not
/// reach the tracker.
@Suite("RulesLastEvaluatedTracker")
@MainActor
struct RulesLastEvaluatedTrackerTests {

  @Test("Tracker records timestamps keyed by trip ID")
  func recordWritesToTracker() {
    let tracker = RulesLastEvaluatedTracker()
    let trip = UUID()
    let stamp = Date(timeIntervalSince1970: 1_700_000_000)
    tracker.record(tripID: trip, at: stamp)
    #expect(tracker.time(forTrip: trip) == stamp)
  }

  @Test("Tracker returns nil for unknown trips")
  func unknownTripsReturnNil() {
    let tracker = RulesLastEvaluatedTracker()
    #expect(tracker.time(forTrip: UUID()) == nil)
  }

  @Test("zone name parser pulls trip UUID out of trip-<uuid> names")
  func zoneNameParseRoundTrip() {
    let tripID = UUID()
    let parsed = RulesLastEvaluatedTracker.tripID(
      fromZoneName: "trip-\(tripID.uuidString)"
    )
    #expect(parsed == tripID)
  }

  @Test("Foreign zone names are ignored by the parser")
  func foreignZoneNameYieldsNil() {
    #expect(RulesLastEvaluatedTracker.tripID(fromZoneName: "globals") == nil)
    #expect(RulesLastEvaluatedTracker.tripID(fromZoneName: "trip-not-a-uuid") == nil)
  }

  // MARK: - Orchestrator wiring

  @Test("Orchestrator updates the tracker on remote zone-change events")
  func orchestratorRecordsRemoteEvents() {
    let tracker = RulesLastEvaluatedTracker()
    let fixedNow = Date(timeIntervalSince1970: 1_701_000_000)
    var runCount = 0
    let orchestrator = RulesEngineTriggerOrchestrator(
      run: { _ in runCount += 1 },
      tracker: tracker,
      now: { fixedNow }
    )
    let tripID = UUID()
    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(tripID.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    orchestrator.handle(
      event: .zoneChanged(zoneID, scope: .shared, isSelfOriginated: false)
    )
    #expect(tracker.time(forTrip: tripID) == fixedNow)
    #expect(runCount == 1)
  }

  @Test("Self-originated events do not advance the tracker")
  func selfOriginatedEventsAreIgnored() {
    let tracker = RulesLastEvaluatedTracker()
    let orchestrator = RulesEngineTriggerOrchestrator(
      run: { _ in },
      tracker: tracker
    )
    let tripID = UUID()
    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(tripID.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    orchestrator.handle(
      event: .zoneChanged(zoneID, scope: .private, isSelfOriginated: true)
    )
    #expect(tracker.time(forTrip: tripID) == nil)
  }

  @Test("Foreign zone names skip the tracker entirely")
  func foreignZonesAreSkipped() {
    let tracker = RulesLastEvaluatedTracker()
    let orchestrator = RulesEngineTriggerOrchestrator(
      run: { _ in },
      tracker: tracker
    )
    let zoneID = CKRecordZone.ID(
      zoneName: "globals",
      ownerName: CKCurrentUserDefaultName
    )
    orchestrator.handle(
      event: .zoneChanged(zoneID, scope: .private, isSelfOriginated: false)
    )
    #expect(tracker.times.isEmpty)
  }
}
