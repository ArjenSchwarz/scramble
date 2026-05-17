import CloudKit
import Foundation

/// Phase 5 sharing seam — the injectable surface every CloudKit-sharing
/// operation flows through (Req 12.1). Production wiring is
/// `CloudKitSharingService`; tests use `FakeSharingService`. Implementations
/// MUST be safe to call from `@MainActor` code.
@MainActor
protocol SharingService: AnyObject {
  /// Create the trip's `CKShare` and resolve once CloudKit confirms the
  /// share record was saved (Req 5.2). Throws if the trip does not have a
  /// `TripZoneState` yet, or if CloudKit rejects the save.
  func createShare(forTrip tripID: UUID) async throws -> CKShare

  /// Present the system share / manage-participants sheet for the given
  /// share. The implementation is a no-op outside an interactive scene
  /// (e.g., in tests).
  func presentShareUI(for share: CKShare, rootRecord: CKRecord) async

  /// Accept an inbound share invitation and trigger the initial fetch on
  /// the participant side (Req 6.1, 6.2).
  func acceptShare(_ metadata: CKShare.Metadata) async throws -> AcceptedShareResult

  /// Leave the trip's share from the participant side (Req 6.5). Triggers
  /// local cleanup of the trip's records.
  func leaveShare(forTrip tripID: UUID) async throws

  /// Owner-side trip deletion (Req 1.4). Tears down the trip's
  /// `TripZoneState`, clears pending uploads, and queues the
  /// `CKRecordZone` deletion on the private engine. The caller is
  /// responsible for removing the `Trip` record itself from the globals
  /// container — Phase 5 still routes trip CRUD through the globals
  /// store while the cross-container relocation is in progress.
  func deleteOwnedTrip(forTrip tripID: UUID) async throws

  /// Current participants for the trip's share, including pending invitees
  /// (Req 7.1). The display-name fallback chain
  /// (display name → email → "Invited participant") is applied here so
  /// callers receive presentation-ready strings.
  func participants(forTrip tripID: UUID) async throws -> [ShareParticipant]

  /// Synchronous owner check (Req 10.4). Reads only from `TripZoneState`;
  /// no I/O. Returns `nil` when the trip is not yet associated with any
  /// zone state (e.g., still in the default-zone, pre-Stage-B).
  func ownerIdentity(forTrip tripID: UUID) -> OwnerIdentity?
}

/// Result of accepting an inbound share invitation. Conveys the zone the
/// trip was bound to and the owner's display name (when CloudKit has
/// resolved one) so the UI can render the trip without a follow-up fetch.
struct AcceptedShareResult: Equatable, Sendable {
  let zoneID: CKRecordZone.ID
  let ownerDisplayName: String?
}

/// Presentation-ready participant view for the Trip Detail Participants
/// section (Req 7). Wraps the underlying `CKShare.Participant` so callers
/// don't have to deal with optional name fields and pending-state flags.
struct ShareParticipant: Equatable, Sendable, Identifiable {
  enum AcceptanceState: String, Sendable {
    case pending
    case accepted
    case removed
    case unknown
  }

  /// `userIdentity.userRecordID?.recordName` when known; `UUID().uuidString`
  /// fallback when CloudKit has not yet resolved a record for this
  /// participant. The `id` is what `Identifiable` uses; it is not stable
  /// across runs for unresolved invitees.
  let id: String
  /// Resolved per Req 7.1's fallback chain
  /// (display name → email → "Invited participant" → "Loading…").
  let displayName: String
  let acceptanceState: AcceptanceState
  let isCurrentUser: Bool
}

/// Synchronous owner-identity surface (Req 10.1, 10.4). Returned by
/// `SharingService.ownerIdentity(forTrip:)`.
enum OwnerIdentity: Equatable, Sendable {
  case currentUser
  case otherUser(displayName: String?)
}
