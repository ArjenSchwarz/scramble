import CloudKit
import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Phase 5 — share-lifecycle contract tests. All cases use
/// `FakeSharingService` because the production `CloudKitSharingService`
/// requires a real CloudKit session; `FakeSharingService` is the test
/// substitute that satisfies the same `SharingService` contract.
@Suite("CloudKitSharingService — share lifecycle contract", .serialized)
@MainActor
struct CloudKitSharingServiceLifecycleTests {

  // MARK: - createShare

  @Test("createShare uses CKShare(recordZoneID:) — share's zoneID matches the trip zone")
  func createShareUsesZoneIDInitializer() async throws {
    let bus = FakeSharingBus()
    let owner = FakeSharingService(role: .owner, bus: bus)
    let tripID = UUID()

    let share = try await owner.createShare(forTrip: tripID)
    let expectedZone = FakeSharingService.zoneID(
      for: tripID, ownerName: CKCurrentUserDefaultName)
    #expect(share.recordID.zoneID == expectedZone)
    #expect(share.publicPermission == .none)
  }

  @Test(
    "createShare on an already-shared trip returns the existing share, doesn't create a new one")
  func createShareIsIdempotent() async throws {
    let bus = FakeSharingBus()
    let owner = FakeSharingService(role: .owner, bus: bus)
    let tripID = UUID()
    let first = try await owner.createShare(forTrip: tripID)
    let second = try await owner.createShare(forTrip: tripID)
    #expect(first === second, "Repeat invocations must return the same CKShare")
  }

  // MARK: - acceptShare (covered via simulateAcceptance — CKShare.Metadata
  // is not directly constructible in tests; the production
  // CloudKitSharingService impl owns the metadata-driven path)

  @Test("simulateAcceptance from owner publishes shareAccepted to the participant bus")
  func simulateAcceptanceDeliversShareAcceptedEvent() async throws {
    let bus = FakeSharingBus()
    let owner = FakeSharingService(role: .owner, bus: bus)
    let participant = FakeSharingService(role: .participant, bus: bus)
    let tripID = UUID()
    _ = try await owner.createShare(forTrip: tripID)
    owner.simulateAcceptance(forTrip: tripID, participantOwnerName: "remote-name")

    let event = try await Self.firstEvent(from: participant)
    if case .shareAccepted(let zoneID, let ownerName) = event {
      #expect(zoneID.zoneName == "trip-\(tripID.uuidString)")
      #expect(ownerName == "remote-name")
    } else {
      Issue.record("Expected .shareAccepted; got \(event)")
    }
  }

  // MARK: - leaveShare

  @Test("leaveShare drops local share state and notifies the bus with .zoneRemoved")
  func leaveShareCleansUpAndNotifies() async throws {
    let bus = FakeSharingBus()
    let owner = FakeSharingService(role: .owner, bus: bus)
    let participant = FakeSharingService(role: .participant, bus: bus)
    let tripID = UUID()
    _ = try await owner.createShare(forTrip: tripID)

    try await owner.leaveShare(forTrip: tripID)
    #expect(owner.shares[tripID] == nil)

    let event = try await Self.firstEvent(from: participant)
    if case .zoneRemoved(let zoneID) = event {
      #expect(zoneID.zoneName == "trip-\(tripID.uuidString)")
    } else {
      Issue.record("Expected .zoneRemoved on bus; got \(event)")
    }
  }

  // MARK: - participants

  @Test("participants returns the configured ShareParticipant list with display names resolved")
  func participantsReflectFallbackChain() async throws {
    let bus = FakeSharingBus()
    let owner = FakeSharingService(role: .owner, bus: bus)
    let tripID = UUID()
    let people = [
      ShareParticipant(
        id: "alice", displayName: "Alice", acceptanceState: .accepted, isCurrentUser: false),
      ShareParticipant(
        id: "bob", displayName: "bob@example.com", acceptanceState: .pending, isCurrentUser: false),
      ShareParticipant(
        id: "carol", displayName: "Invited participant",
        acceptanceState: .pending, isCurrentUser: false),
    ]
    owner.setParticipants(people, forTrip: tripID)

    let result = try await owner.participants(forTrip: tripID)
    #expect(result.count == 3)
    #expect(result[0].displayName == "Alice")
    #expect(result[1].displayName == "bob@example.com")
    #expect(result[2].displayName == "Invited participant")
  }

  // MARK: - ownerIdentity

  @Test("ownerIdentity returns .currentUser on the owner side after createShare")
  func ownerIdentityIsCurrentUserOnOwner() async throws {
    let bus = FakeSharingBus()
    let owner = FakeSharingService(role: .owner, bus: bus)
    let tripID = UUID()
    _ = try await owner.createShare(forTrip: tripID)
    #expect(owner.ownerIdentity(forTrip: tripID) == .currentUser)
  }

  @Test("ownerIdentity returns .otherUser on the participant side once the share is accepted")
  func ownerIdentityReportsRemoteOnParticipant() async throws {
    let bus = FakeSharingBus()
    let participant = FakeSharingService(role: .participant, bus: bus)
    let tripID = UUID()
    participant.recordRemoteOwner(forTrip: tripID, ownerName: "Alice")
    if case .otherUser(let displayName) = participant.ownerIdentity(forTrip: tripID) {
      #expect(displayName == "Alice")
    } else {
      Issue.record("Expected .otherUser on participant side")
    }
  }

  @Test("ownerIdentity is synchronous — does not block on I/O")
  func ownerIdentityIsSynchronous() async throws {
    let bus = FakeSharingBus()
    let owner = FakeSharingService(role: .owner, bus: bus)
    let tripID = UUID()
    _ = try await owner.createShare(forTrip: tripID)
    let start = Date()
    _ = owner.ownerIdentity(forTrip: tripID)
    let elapsed = Date().timeIntervalSince(start)
    #expect(elapsed < 0.005, "ownerIdentity must not perform I/O (Req 10.4)")
  }

  // MARK: - Helpers

  private static func firstEvent(
    from endpoint: FakeSharingService
  ) async throws -> FakeSharingEvent {
    for await event in endpoint.events {
      return event
    }
    throw NSError(domain: "FakeShareLifecycle", code: 0)
  }
}
