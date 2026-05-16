#if DEBUG
  import CloudKit
  import Foundation

  /// DEBUG-only `SharingService` that returns hard-coded ownership and
  /// participant lists seeded by `UITestSeed`. Production builds use
  /// `CloudKitSharingService`; UI tests can't reach CloudKit, so the
  /// in-memory tripsLocal store is paired with this stub for the share-
  /// surface assertions in `Phase5SharingUITests`.
  @MainActor
  final class UITestSharingService: SharingService {
    /// Static so `UITestSeed` (also `@MainActor`) can populate the
    /// fixture state before the SwiftUI tree first renders, without
    /// having to pass the service instance into the seed entry point.
    static var participantsByTrip: [UUID: [ShareParticipant]] = [:]
    static var ownerIdentitiesByTrip: [UUID: OwnerIdentity] = [:]

    /// Reset between tests / fixtures. Called by `UITestSeed` whenever
    /// a fixture is applied.
    static func reset() {
      participantsByTrip = [:]
      ownerIdentitiesByTrip = [:]
    }

    func createShare(forTrip tripID: UUID) async throws -> CKShare {
      let zoneID = CKRecordZone.ID(
        zoneName: "trip-\(tripID.uuidString)",
        ownerName: CKCurrentUserDefaultName
      )
      let share = CKShare(recordZoneID: zoneID)
      share.publicPermission = .none
      return share
    }

    func presentShareUI(for share: CKShare, rootRecord: CKRecord) async {}

    func acceptShare(_ metadata: CKShare.Metadata) async throws -> AcceptedShareResult {
      AcceptedShareResult(
        zoneID: metadata.share.recordID.zoneID,
        ownerDisplayName: nil
      )
    }

    func leaveShare(forTrip tripID: UUID) async throws {}

    func participants(forTrip tripID: UUID) async throws -> [ShareParticipant] {
      Self.participantsByTrip[tripID] ?? []
    }

    func ownerIdentity(forTrip tripID: UUID) -> OwnerIdentity? {
      Self.ownerIdentitiesByTrip[tripID]
    }
  }
#endif
