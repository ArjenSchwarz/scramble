import CloudKit
import Foundation
import SwiftData
import UIKit
import os

/// Production `SharingService` impl. Wraps `CKContainer`,
/// `TripSyncEngine`, and `UICloudSharingController` to satisfy the share
/// lifecycle requirements from Phase 5 (Reqs [5](../../specs/phase-5-cloudkit-sharing/requirements.md#5-share-invitation-flow), [6](../../specs/phase-5-cloudkit-sharing/requirements.md#6-share-acceptance-flow), [7](../../specs/phase-5-cloudkit-sharing/requirements.md#7-participant-management-surface),
/// [10](../../specs/phase-5-cloudkit-sharing/requirements.md#10-trip-ownership-identification)).
///
/// Test coverage lives against `FakeSharingService` —
/// `CloudKitSharingServiceLifecycleTests` exercises the shared protocol
/// contract; the production impl is exercised end-to-end via the
/// manual test plan and the `CKSyncEngineValidationHarness`.
@MainActor
final class CloudKitSharingService: SharingService {
  let container: CKContainer
  let context: ModelContext
  let syncEngine: TripSyncEngine

  init(container: CKContainer, context: ModelContext, syncEngine: TripSyncEngine) {
    self.container = container
    self.context = context
    self.syncEngine = syncEngine
  }

  // MARK: - createShare

  func createShare(forTrip tripID: UUID) async throws -> CKShare {
    let zoneState = try fetchZoneState(forTrip: tripID)
    if let existingShareID = zoneState.shareID {
      if let share = try await fetchShare(recordName: existingShareID, in: zoneState) {
        return share
      }
    }
    let zoneID = TripZoneStateRecordTranslator.zoneID(for: zoneState)
    let share = CKShare(recordZoneID: zoneID)
    share.publicPermission = .none
    // Hand the CKShare to the engine for upload via
    // CKSyncEngine.State.add(pendingRecordZoneChanges:) — the engine's
    // delegate emits the share record on the next batch and confirms via
    // sentRecordZoneChanges.
    syncEngine.privateEngine?.state.add(
      pendingRecordZoneChanges: [.saveRecord(share.recordID)]
    )
    zoneState.shareID = share.recordID.recordName
    try context.save()
    return share
  }

  /// Best-effort lookup of an existing share record. Falls back to a
  /// fresh fetch from CloudKit when the local cache is stale.
  private func fetchShare(
    recordName: String, in zoneState: TripZoneState
  ) async throws -> CKShare? {
    let zoneID = TripZoneStateRecordTranslator.zoneID(for: zoneState)
    let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
    let database: CKDatabase
    switch zoneState.zoneScope {
    case "shared": database = container.sharedCloudDatabase
    default: database = container.privateCloudDatabase
    }
    return try? await database.record(for: recordID) as? CKShare
  }

  // MARK: - presentShareUI

  func presentShareUI(for share: CKShare, rootRecord: CKRecord) async {
    // The UI presentation is owned by the SwiftUI wrapper
    // (`UICloudSharingControllerRepresentable`); the service itself is
    // headless. Callers receiving the CKShare from `createShare` mount
    // the representable in a sheet rather than calling this method.
  }

  // MARK: - acceptShare

  func acceptShare(_ metadata: CKShare.Metadata) async throws -> AcceptedShareResult {
    _ = try await container.accept(metadata)
    let sharedEngine = syncEngine.sharedEngine
    sharedEngine?.state.add(pendingDatabaseChanges: [
      .saveZone(CKRecordZone(zoneID: metadata.share.recordID.zoneID))
    ])
    try await sharedEngine?.fetchChanges()
    let ownerName = metadata.ownerIdentity.userRecordID?.recordName
    return AcceptedShareResult(
      zoneID: metadata.share.recordID.zoneID,
      ownerDisplayName: ownerName
    )
  }

  // MARK: - leaveShare

  func leaveShare(forTrip tripID: UUID) async throws {
    let zoneState = try fetchZoneState(forTrip: tripID)
    let zoneID = TripZoneStateRecordTranslator.zoneID(for: zoneState)
    _ = try await container.sharedCloudDatabase.deleteRecordZone(withID: zoneID)
    try cleanupLocalState(forTrip: tripID)
  }

  // MARK: - deleteOwnedTrip

  /// Tear down the tripsLocal-side bookkeeping for an owner-deleted trip
  /// and ask the private engine to remove the CK zone. The Trip record
  /// itself lives in the globals container in Phase 5; the view layer
  /// removes it from there separately.
  func deleteOwnedTrip(forTrip tripID: UUID) async throws {
    let descriptor = FetchDescriptor<TripZoneState>(
      predicate: #Predicate { $0.tripID == tripID }
    )
    let zoneStates = try context.fetch(descriptor)
    for state in zoneStates {
      let zoneID = TripZoneStateRecordTranslator.zoneID(for: state)
      syncEngine.privateEngine?.state.add(
        pendingDatabaseChanges: [.deleteZone(zoneID)]
      )
      state.pendingUploadFlags = Data()
      context.delete(state)
    }
    try context.save()
  }

  /// Trip-deletion ordering (design § "Trip-deletion ordering"): clear
  /// dirty flags, then packing items / tasks, then snapshots, then the
  /// trip itself, then the zone state. Done in one transaction.
  private func cleanupLocalState(forTrip tripID: UUID) throws {
    let zoneStates = try context.fetch(
      FetchDescriptor<TripZoneState>(predicate: #Predicate { $0.tripID == tripID })
    )
    for state in zoneStates {
      state.pendingUploadFlags = Data()
    }

    let trips = try context.fetch(
      FetchDescriptor<Trip>(predicate: #Predicate { $0.id == tripID })
    )
    guard let trip = trips.first else {
      // Still tear down the zone state row even when the Trip is gone
      // already (mid-cleanup crash recovery).
      for state in zoneStates { context.delete(state) }
      try context.save()
      return
    }

    for item in trip.packingItems ?? [] {
      context.delete(item)
    }
    for task in trip.tasks ?? [] {
      context.delete(task)
    }
    for snapshot in trip.participantSnapshots ?? [] {
      context.delete(snapshot)
    }
    context.delete(trip)
    for state in zoneStates {
      context.delete(state)
    }
    try context.save()
  }

  // MARK: - participants

  func participants(forTrip tripID: UUID) async throws -> [ShareParticipant] {
    let zoneState = try fetchZoneState(forTrip: tripID)
    guard let shareID = zoneState.shareID else { return [] }
    let zoneID = TripZoneStateRecordTranslator.zoneID(for: zoneState)
    let recordID = CKRecord.ID(recordName: shareID, zoneID: zoneID)
    let database: CKDatabase =
      zoneState.zoneScope == "shared"
      ? container.sharedCloudDatabase : container.privateCloudDatabase
    let record = try await database.record(for: recordID)
    guard let share = record as? CKShare else { return [] }
    return share.participants.map(Self.makeShareParticipant)
  }

  /// Apply Req 7.1's display-name fallback (`displayName → email →
  /// "Invited participant"`) together with Req 7.8's in-flight
  /// placeholder: while CloudKit is still resolving the identity for a
  /// pending invite, show `"Loading…"` rather than the terminal
  /// "Invited participant" string.
  static func makeShareParticipant(_ participant: CKShare.Participant) -> ShareParticipant {
    let identity = participant.userIdentity
    let lookup = identity.lookupInfo
    let formattedName = identity.nameComponents.flatMap(personNameDisplayName)
    let acceptance: ShareParticipant.AcceptanceState = {
      switch participant.acceptanceStatus {
      case .pending: return .pending
      case .accepted: return .accepted
      case .removed: return .removed
      case .unknown: return .unknown
      @unknown default: return .unknown
      }
    }()
    let displayName: String = {
      if let formattedName { return formattedName }
      if let email = lookup?.emailAddress, !email.isEmpty { return email }
      // Identity not yet resolved. Treat pending invitations as
      // in-flight (Req 7.8) and accepted-but-unresolved as the Req 7.1
      // terminal fallback.
      return acceptance == .pending ? "Loading…" : "Invited participant"
    }()
    return ShareParticipant(
      id: identity.userRecordID?.recordName ?? UUID().uuidString,
      displayName: displayName,
      acceptanceState: acceptance,
      isCurrentUser: participant.role == .owner
    )
  }

  private static func personNameDisplayName(_ components: PersonNameComponents) -> String? {
    let formatter = PersonNameComponentsFormatter()
    formatter.style = .default
    let result = formatter.string(from: components).trimmingCharacters(in: .whitespaces)
    return result.isEmpty ? nil : result
  }

  // MARK: - ownerIdentity

  /// Synchronous, no-I/O ownership check (Req 10.4). Reads the cached
  /// `TripZoneState` row; returns `nil` when the trip isn't yet bound to
  /// any zone state (e.g., still pre-Stage-B).
  func ownerIdentity(forTrip tripID: UUID) -> OwnerIdentity? {
    let descriptor = FetchDescriptor<TripZoneState>(predicate: #Predicate { $0.tripID == tripID })
    guard let state = try? context.fetch(descriptor).first else { return nil }
    if state.zoneOwnerName == CKCurrentUserDefaultName || state.zoneScope == "private" {
      return .currentUser
    }
    return .otherUser(displayName: state.zoneOwnerName)
  }

  // MARK: - Internal

  private func fetchZoneState(forTrip tripID: UUID) throws -> TripZoneState {
    let descriptor = FetchDescriptor<TripZoneState>(predicate: #Predicate { $0.tripID == tripID })
    if let existing = try context.fetch(descriptor).first {
      return existing
    }
    // Stage-B normally inserts TripZoneState; the share path tolerates
    // missing state by lazily creating one on the owner side so a brand
    // new trip can be shared immediately after creation.
    let state = TripZoneState(
      tripID: tripID,
      zoneOwnerName: CKCurrentUserDefaultName,
      zoneScope: "private"
    )
    context.insert(state)
    try context.save()
    return state
  }
}
