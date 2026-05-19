import CloudKit
import Foundation

@testable import Scramble

/// In-process two-side fake `SharingService`. Two `FakeSharingService`
/// instances bound to the same `Bus` simulate an owner/participant pair
/// for tests; the bus carries `simulateOwnerWrite` / acceptance /
/// `triggerZoneChange` events from one side to the other (Decision 13,
/// design § "FakeSharingService design").
///
/// Lives in the test target only — production code never imports this
/// file. Tests construct the bus + two endpoints and exercise the share
/// lifecycle without reaching CloudKit.
@MainActor
final class FakeSharingService: SharingService {

  enum Role: Equatable, Sendable {
    case owner
    case participant
  }

  let role: Role
  let bus: Bus

  /// Async stream of events delivered to *this* endpoint. The bus
  /// publishes here when the other endpoint calls `simulateOwnerWrite`,
  /// `triggerZoneChange`, `simulateAcceptance`, etc.
  let events: AsyncStream<FakeSharingEvent>

  private let eventContinuation: AsyncStream<FakeSharingEvent>.Continuation

  /// Imperative override — set to non-zero to slow event delivery via
  /// `bus.deliveryDelay`. Tests that want immediate, deterministic
  /// delivery leave this at zero.
  var deliveryDelay: TimeInterval {
    get { bus.deliveryDelay }
    set { bus.deliveryDelay = newValue }
  }

  /// Imperative override — when non-nil, the next throwing `SharingService`
  /// method invocation throws this error and clears it.
  var pendingError: (any Error)?

  /// Tracks shares created on this endpoint, keyed by trip ID. Set on the
  /// owner side at `createShare`; mirrored to the participant on
  /// `simulateAcceptance`.
  private(set) var shares: [UUID: CKShare] = [:]

  /// Tracks the local view of who owns each trip's zone — populated on
  /// share creation (owner side) and on acceptance (participant side).
  private(set) var ownerIdentities: [UUID: OwnerIdentity] = [:]

  /// Per-share participant lists. Tests can mutate via
  /// `setParticipants(_:forTrip:)` to drive the Participants UI.
  private var participantsByTrip: [UUID: [ShareParticipant]] = [:]

  init(role: Role, bus: Bus) {
    self.role = role
    self.bus = bus
    var continuation: AsyncStream<FakeSharingEvent>.Continuation!
    self.events = AsyncStream { continuation = $0 }
    self.eventContinuation = continuation
    bus.attach(endpoint: self)
  }

  // MARK: - SharingService

  func createShare(forTrip tripID: UUID) async throws -> CKShare {
    if let error = pendingError {
      pendingError = nil
      throw error
    }
    guard role == .owner else {
      throw FakeSharingError.participantCannotCreateShare
    }
    if let existing = shares[tripID] { return existing }
    let zoneID = Self.zoneID(for: tripID, ownerName: CKCurrentUserDefaultName)
    let share = CKShare(recordZoneID: zoneID)
    share.publicPermission = .none
    shares[tripID] = share
    ownerIdentities[tripID] = .currentUser
    return share
  }

  func presentShareUI(for share: CKShare, rootRecord: CKRecord) async {
    // No-op in the fake — tests don't render UI.
  }

  func acceptShare(_ metadata: CKShare.Metadata) async throws -> AcceptedShareResult {
    if let error = pendingError {
      pendingError = nil
      throw error
    }
    let zoneID = metadata.share.recordID.zoneID
    let ownerName = metadata.ownerIdentity.userRecordID?.recordName
    return AcceptedShareResult(zoneID: zoneID, ownerDisplayName: ownerName)
  }

  func leaveShare(forTrip tripID: UUID) async throws {
    if let error = pendingError {
      pendingError = nil
      throw error
    }
    shares.removeValue(forKey: tripID)
    ownerIdentities.removeValue(forKey: tripID)
    let zoneID = Self.zoneID(for: tripID, ownerName: CKCurrentUserDefaultName)
    bus.publish(.zoneRemoved(zoneID: zoneID), to: oppositeRole)
  }

  func participants(forTrip tripID: UUID) async throws -> [ShareParticipant] {
    if let error = pendingError {
      pendingError = nil
      throw error
    }
    return participantsByTrip[tripID] ?? []
  }

  func ownerIdentity(forTrip tripID: UUID) -> OwnerIdentity? {
    ownerIdentities[tripID]
  }

  // MARK: - Imperative test hooks

  /// Simulate the owner writing a record. Delivers a `zoneChanged` event
  /// to the participant side after `deliveryDelay`.
  func simulateOwnerWrite(
    _ record: CKRecord,
    tripID: UUID
  ) {
    precondition(role == .owner, "simulateOwnerWrite is owner-only")
    let zoneID = record.recordID.zoneID
    bus.publish(
      .zoneChanged(zoneID: zoneID, records: [record], deletedRecordIDs: []),
      to: .participant
    )
  }

  /// Simulate the owner sending a share invitation that the participant
  /// accepts. Updates both endpoints' caches.
  func simulateAcceptance(forTrip tripID: UUID, participantOwnerName: String) {
    precondition(role == .owner, "simulateAcceptance is owner-driven")
    let share =
      shares[tripID]
      ?? CKShare(recordZoneID: Self.zoneID(for: tripID, ownerName: CKCurrentUserDefaultName))
    shares[tripID] = share
    ownerIdentities[tripID] = .currentUser
    bus.publish(
      .shareAccepted(zoneID: share.recordID.zoneID, ownerName: participantOwnerName),
      to: .participant
    )
  }

  /// Simulate a CloudKit subscription firing for a zone — the bus
  /// delivers a synthetic `zoneChanged` event with no record payload so
  /// the receiving side can refetch.
  func triggerZoneChange(zoneID: CKRecordZone.ID, target: Role) {
    bus.publish(
      .zoneChanged(zoneID: zoneID, records: [], deletedRecordIDs: []),
      to: target
    )
  }

  /// Inject an error into the next call to a throwing `SharingService`
  /// method. Cleared automatically once raised.
  func simulateError(_ error: any Error) {
    pendingError = error
  }

  /// Set the participant list returned by `participants(forTrip:)`.
  func setParticipants(_ participants: [ShareParticipant], forTrip tripID: UUID) {
    participantsByTrip[tripID] = participants
  }

  /// Mark this endpoint as being a participant of `tripID`'s share —
  /// recorded so `ownerIdentity(forTrip:)` returns `.otherUser`.
  func recordRemoteOwner(forTrip tripID: UUID, ownerName: String) {
    precondition(role == .participant, "Remote-owner records belong on the participant side")
    ownerIdentities[tripID] = .otherUser(displayName: ownerName)
  }

  // MARK: - Helpers

  private var oppositeRole: Role {
    role == .owner ? .participant : .owner
  }

  static func zoneID(for tripID: UUID, ownerName: String) -> CKRecordZone.ID {
    CKRecordZone.ID(zoneName: "trip-\(tripID.uuidString)", ownerName: ownerName)
  }

  fileprivate func deliver(_ event: FakeSharingEvent) {
    eventContinuation.yield(event)
  }
}

// MARK: - Bus

/// Delivers fake sharing events between an owner endpoint and a
/// participant endpoint. Owns no global state — each test constructs its
/// own bus.
@MainActor
final class FakeSharingBus {
  weak var owner: FakeSharingService?
  weak var participant: FakeSharingService?
  var deliveryDelay: TimeInterval = 0

  fileprivate func attach(endpoint: FakeSharingService) {
    switch endpoint.role {
    case .owner: owner = endpoint
    case .participant: participant = endpoint
    }
  }

  /// Publish an event to the named role. When `deliveryDelay > 0` the
  /// delivery is deferred via a Task; otherwise it is synchronous.
  fileprivate func publish(_ event: FakeSharingEvent, to role: FakeSharingService.Role) {
    let target: FakeSharingService? = (role == .owner) ? owner : participant
    guard let target else { return }
    if deliveryDelay > 0 {
      let nanos = UInt64(deliveryDelay * 1_000_000_000)
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: nanos)
        target.deliver(event)
      }
    } else {
      target.deliver(event)
    }
  }
}

typealias Bus = FakeSharingBus

// MARK: - Events

/// Events the fake bus delivers to an endpoint. Mirrors the production
/// `TripSyncEvent` shape closely so tests can switch on the same cases.
enum FakeSharingEvent: Equatable, Sendable {
  case zoneChanged(
    zoneID: CKRecordZone.ID,
    records: [CKRecord],
    deletedRecordIDs: [CKRecord.ID]
  )
  case shareAccepted(zoneID: CKRecordZone.ID, ownerName: String?)
  case zoneRemoved(zoneID: CKRecordZone.ID)
}

// MARK: - Errors

enum FakeSharingError: Error, Equatable {
  case participantCannotCreateShare
  case forced
}
