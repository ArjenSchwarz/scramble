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
  /// Phase 5.1 — every `tripsLocal` save routes through this chokepoint
  /// so the engine is notified about dirty / deleted records.
  let hook: LocalWriteHook

  init(
    container: CKContainer,
    context: ModelContext,
    syncEngine: TripSyncEngine,
    hook: LocalWriteHook
  ) {
    self.container = container
    self.context = context
    self.syncEngine = syncEngine
    self.hook = hook
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
    // Hand the CKShare to the engine. `enqueueShareSave` caches the
    // CKShare so the engine's record provider can return the actual
    // instance — `CKShare` is not in SwiftData and cannot be
    // reconstructed from the local store by the translator dispatch.
    syncEngine.enqueueShareSave(share)
    zoneState.shareID = share.recordID.recordName
    // Routes through the chokepoint. `TripZoneState` mappings return
    // nil from the hook's record-type dispatch, so the save lands but
    // the notifier emits no record-level signals — the engine has
    // already learned about the share via `enqueueShareSave`.
    try hook.commit(context)
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
    // The CloudKit acceptance has already landed server-side. If the
    // shared engine hasn't been started yet (acceptance arrived during
    // the migration splash), skip the explicit fetch: `automaticallySync`
    // = true means the engine will pull the new zone once `start()`
    // completes. Surfacing this in the log keeps the gap visible.
    guard let sharedEngine = syncEngine.sharedEngine else {
      modelLogger.info(
        "[CloudKitSharingService] acceptShare received before sharedEngine started; relying on automaticallySync to catch up"
      )
      let owner = metadata.ownerIdentity
      return AcceptedShareResult(
        zoneID: metadata.share.recordID.zoneID,
        ownerDisplayName: Self.resolveOwnerDisplayName(from: owner)
      )
    }
    sharedEngine.state.add(pendingDatabaseChanges: [
      .saveZone(CKRecordZone(zoneID: metadata.share.recordID.zoneID))
    ])
    try await sharedEngine.fetchChanges()
    return AcceptedShareResult(
      zoneID: metadata.share.recordID.zoneID,
      ownerDisplayName: Self.resolveOwnerDisplayName(from: metadata.ownerIdentity)
    )
  }

  /// Prefer the display name CloudKit resolved; fall back to email; only
  /// return `nil` when CloudKit has no human-readable identifier yet (the
  /// raw `userRecordID.recordName` is an opaque `_abc123…` string and is
  /// not safe to surface in UI per Req 7.1).
  private static func resolveOwnerDisplayName(from owner: CKUserIdentity) -> String? {
    if let components = owner.nameComponents {
      let formatted =
        personNameFormatter
        .string(from: components)
        .trimmingCharacters(in: .whitespaces)
      if !formatted.isEmpty { return formatted }
    }
    if let email = owner.lookupInfo?.emailAddress, !email.isEmpty {
      return email
    }
    return nil
  }

  // MARK: - leaveShare

  /// Participant-side leave. Phase 5.1: tolerates the case where the
  /// remote zone has already been deleted (`CKError.zoneNotFound`) and
  /// routes the local cleanup through `TripDeletion.delete` so the
  /// reverse-cascade ends in a single `LocalWriteHook.commitDeletion`
  /// transaction.
  func leaveShare(forTrip tripID: UUID) async throws {
    let zoneState = try fetchZoneState(forTrip: tripID)
    let zoneID = TripZoneStateRecordTranslator.zoneID(for: zoneState)
    do {
      _ = try await container.sharedCloudDatabase.deleteRecordZone(withID: zoneID)
    } catch let error as CKError where error.code == .zoneNotFound {
      // The owner revoked the share (or another device on the user's
      // account already left it). Proceed with local cleanup — the
      // expected post-leave state is identical either way.
    }
    try TripDeletion.delete(
      tripID: tripID, in: context, hook: hook, zoneDeleter: nil
    )
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
    let currentUserRecordID = share.currentUserParticipant?.userIdentity.userRecordID
    return share.participants.map {
      Self.makeShareParticipant($0, currentUserRecordID: currentUserRecordID)
    }
  }

  /// Apply Req 7.1's display-name fallback (`displayName → email →
  /// "Invited participant"`) together with Req 7.8's in-flight
  /// placeholder: while CloudKit is still resolving the identity for a
  /// pending invite, show `"Loading…"` rather than the terminal
  /// "Invited participant" string. `isCurrentUser` is decided by record-ID
  /// match against `share.currentUserParticipant` rather than the
  /// participant role, so a participant on the share recognises their own
  /// row (the role check would only mark the trip's owner).
  static func makeShareParticipant(
    _ participant: CKShare.Participant,
    currentUserRecordID: CKRecord.ID? = nil
  ) -> ShareParticipant {
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
    let isCurrentUser: Bool = {
      if let currentUserRecordID, let theirID = identity.userRecordID {
        return currentUserRecordID == theirID
      }
      return false
    }()
    return ShareParticipant(
      id: identity.userRecordID?.recordName ?? UUID().uuidString,
      displayName: displayName,
      acceptanceState: acceptance,
      isCurrentUser: isCurrentUser
    )
  }

  /// Shared formatter for owner + participant name resolution; allocating
  /// per call adds up in the Participants section's loop.
  private static let personNameFormatter: PersonNameComponentsFormatter = {
    let formatter = PersonNameComponentsFormatter()
    formatter.style = .default
    return formatter
  }()

  private static func personNameDisplayName(_ components: PersonNameComponents) -> String? {
    let result = personNameFormatter.string(from: components)
      .trimmingCharacters(in: .whitespaces)
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
    // Phase 5.1: lazy-insert lands through the chokepoint.
    // `TripZoneState` mapping returns nil so this is a save-only path.
    try hook.commit(context)
    return state
  }
}
