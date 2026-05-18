import CloudKit
import Foundation
import Testing

@testable import Scramble

/// Phase 5.1 — `TripSyncEventBus` multicasts the engine's event stream to
/// both `RulesEngineTriggerOrchestrator` and `ZoneMigrationCoordinator`.
/// See design § "TripSyncEventBus (new)".
@Suite("TripSyncEventBus", .serialized)
@MainActor
struct TripSyncEventBusTests {

  @Test("Both subscribers receive every event from a single iteration")
  func multicastsToBothSubscribers() async throws {
    let stream = AsyncStream.makeStream(of: TripSyncEvent.self)
    let bus = TripSyncEventBus(events: stream.stream)
    let recorderA = HandlerRecorder()
    let recorderB = HandlerRecorder()
    bus.subscribeOrchestrator { recorderA.record($0) }
    bus.subscribeCoordinator { recorderB.record($0) }
    bus.start()

    let zone = CKRecordZone.ID(zoneName: "trip-1", ownerName: CKCurrentUserDefaultName)
    stream.continuation.yield(.zoneSaved(zone))
    stream.continuation.yield(
      .recordsSaved([
        CKRecord.ID(recordName: "r1", zoneID: zone)
      ]))
    stream.continuation.finish()

    await waitFor { recorderA.events.count >= 2 && recorderB.events.count >= 2 }

    #expect(recorderA.events.count == 2)
    #expect(recorderB.events.count == 2)
    bus.stop()
  }

  @Test("A throwing subscriber is logged and does NOT starve the other subscriber")
  func subscriberFailureIsIsolated() async throws {
    let stream = AsyncStream.makeStream(of: TripSyncEvent.self)
    let bus = TripSyncEventBus(events: stream.stream)
    let healthy = HandlerRecorder()
    // Orchestrator handler throws on every event — the bus must log and
    // continue, so the coordinator subscriber still sees the event.
    bus.subscribeOrchestrator { _ in
      throw HandlerError.intentional
    }
    bus.subscribeCoordinator { healthy.record($0) }
    bus.start()

    let zone = CKRecordZone.ID(zoneName: "trip-1", ownerName: CKCurrentUserDefaultName)
    stream.continuation.yield(.zoneSaved(zone))
    stream.continuation.yield(.recordsSaved([CKRecord.ID(recordName: "r", zoneID: zone)]))
    stream.continuation.finish()

    await waitFor { healthy.events.count >= 2 }
    #expect(healthy.events.count == 2, "Healthy subscriber receives every event")
    bus.stop()
  }

  @Test("stop() cancels the iteration task (test-only)")
  func stopCancelsIteration() async throws {
    let stream = AsyncStream.makeStream(of: TripSyncEvent.self)
    let bus = TripSyncEventBus(events: stream.stream)
    let recorder = HandlerRecorder()
    bus.subscribeOrchestrator { recorder.record($0) }
    bus.start()
    bus.stop()

    let zone = CKRecordZone.ID(zoneName: "trip-1", ownerName: CKCurrentUserDefaultName)
    stream.continuation.yield(.zoneSaved(zone))
    stream.continuation.finish()
    // Give the test loop a chance to attempt dispatch.
    try? await Task.sleep(nanoseconds: 50_000_000)
    #expect(recorder.events.isEmpty, "stop() prevents further dispatch")
  }

  // MARK: - Helpers

  enum HandlerError: Error { case intentional }

  @MainActor
  final class HandlerRecorder {
    var events: [TripSyncEvent] = []
    func record(_ event: TripSyncEvent) { events.append(event) }
  }

  private func waitFor(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<100 {
      if condition() { return }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
  }
}
