import CloudKit
import Foundation
import Testing

@testable import Scramble

@Suite("FakeSharingService", .serialized)
@MainActor
struct FakeSharingServiceTests {

  // MARK: - Bus delivery

  @Test("Bus delivers an event published from one endpoint to the other")
  func busDeliversEventBetweenEndpoints() async throws {
    let bus = FakeSharingBus()
    let owner = FakeSharingService(role: .owner, bus: bus)
    let participant = FakeSharingService(role: .participant, bus: bus)

    let tripID = UUID()
    let zoneID = FakeSharingService.zoneID(for: tripID, ownerName: CKCurrentUserDefaultName)
    let record = CKRecord(
      recordType: "Trip",
      recordID: CKRecord.ID(recordName: tripID.uuidString, zoneID: zoneID)
    )
    record["name"] = "Iceland" as CKRecordValue

    owner.simulateOwnerWrite(record, tripID: tripID)

    let received = try await Self.firstEvent(from: participant)
    if case .zoneChanged(let receivedZoneID, let records, _) = received {
      #expect(receivedZoneID == zoneID)
      #expect(records.first?["name"] as? String == "Iceland")
    } else {
      Issue.record("Expected .zoneChanged on participant; got \(received)")
    }
  }

  @Test("deliveryDelay defers event delivery on the bus")
  func busHonorsDeliveryDelay() async throws {
    let bus = FakeSharingBus()
    let owner = FakeSharingService(role: .owner, bus: bus)
    let participant = FakeSharingService(role: .participant, bus: bus)
    bus.deliveryDelay = 0.05

    let tripID = UUID()
    let zoneID = FakeSharingService.zoneID(for: tripID, ownerName: CKCurrentUserDefaultName)
    let record = CKRecord(
      recordType: "Trip",
      recordID: CKRecord.ID(recordName: tripID.uuidString, zoneID: zoneID)
    )
    let start = Date()
    owner.simulateOwnerWrite(record, tripID: tripID)
    _ = try await Self.firstEvent(from: participant)
    let elapsed = Date().timeIntervalSince(start)
    #expect(elapsed >= 0.05, "Delivery should respect bus.deliveryDelay")
  }

  // MARK: - Share creation + acceptance

  @Test("createShare on the owner endpoint registers a CKShare keyed by trip ID")
  func ownerCreatesShare() async throws {
    let bus = FakeSharingBus()
    let owner = FakeSharingService(role: .owner, bus: bus)
    _ = FakeSharingService(role: .participant, bus: bus)

    let tripID = UUID()
    let share = try await owner.createShare(forTrip: tripID)

    #expect(owner.shares[tripID] === share)
    #expect(owner.ownerIdentity(forTrip: tripID) == .currentUser)
  }

  @Test("createShare on the participant endpoint throws (only the owner can share)")
  func participantCannotCreateShare() async {
    let bus = FakeSharingBus()
    let participant = FakeSharingService(role: .participant, bus: bus)

    do {
      _ = try await participant.createShare(forTrip: UUID())
      Issue.record("createShare should reject participant invocation")
    } catch let error as FakeSharingError {
      #expect(error == .participantCannotCreateShare)
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }

  @Test("simulateAcceptance delivers a shareAccepted event to the participant side")
  func ownerCanSimulateParticipantAcceptance() async throws {
    let bus = FakeSharingBus()
    let owner = FakeSharingService(role: .owner, bus: bus)
    let participant = FakeSharingService(role: .participant, bus: bus)

    let tripID = UUID()
    _ = try await owner.createShare(forTrip: tripID)
    owner.simulateAcceptance(forTrip: tripID, participantOwnerName: "remote-user")

    let received = try await Self.firstEvent(from: participant)
    if case .shareAccepted(let zoneID, let ownerName) = received {
      #expect(zoneID.zoneName == "trip-\(tripID.uuidString)")
      #expect(ownerName == "remote-user")
    } else {
      Issue.record("Expected .shareAccepted on participant; got \(received)")
    }
  }

  // MARK: - Error injection

  @Test("simulateError causes the next throwing call to fail and clears the override")
  func simulateErrorIsConsumedOnce() async throws {
    let bus = FakeSharingBus()
    let owner = FakeSharingService(role: .owner, bus: bus)
    owner.simulateError(FakeSharingError.forced)
    do {
      _ = try await owner.createShare(forTrip: UUID())
      Issue.record("createShare should have thrown the injected error")
    } catch let error as FakeSharingError {
      #expect(error == .forced)
    }
    // Second call should succeed because the error was consumed.
    _ = try await owner.createShare(forTrip: UUID())
  }

  // MARK: - Helpers

  private static func firstEvent(
    from endpoint: FakeSharingService
  ) async throws -> FakeSharingEvent {
    for await event in endpoint.events {
      return event
    }
    throw FirstEventError.streamEnded
  }
}

private enum FirstEventError: Error {
  case streamEnded
}
