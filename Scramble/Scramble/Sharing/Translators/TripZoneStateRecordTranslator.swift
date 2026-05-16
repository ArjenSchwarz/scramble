import CloudKit
import Foundation
import SwiftData

/// `CKShare` ↔ `TripZoneState` translator. `TripZoneState` itself is a
/// local-only mirror of zone-level information (which records are dirty,
/// which scope the zone lives in, the share's CloudKit ID); the
/// "remote record" it corresponds to is the zone's `CKShare`.
///
/// The translator is deliberately narrow: it caches the share's record
/// identifier and system fields onto the local row when the engine
/// fetches/sends a share, so subsequent saves preserve the share's server
/// change tag. The trip-zone scope is captured at construction by
/// `TripZoneState.zoneScope` and is not re-derived from the record on
/// every fetch.
@MainActor
enum TripZoneStateRecordTranslator {
  /// Standard CloudKit record type for shares. Exposed for tests so they
  /// can construct fake `CKShare` records without referencing
  /// `CKRecord.SystemType.share` (a `String?` constant).
  static let recordType: String = "cloudkit.share"

  static func recordID(for state: TripZoneState) -> CKRecord.ID? {
    guard let shareID = state.shareID else { return nil }
    return CKRecord.ID(
      recordName: shareID,
      zoneID: zoneID(for: state)
    )
  }

  static func zoneID(for state: TripZoneState) -> CKRecordZone.ID {
    CKRecordZone.ID(
      zoneName: "trip-\(state.tripID.uuidString)",
      ownerName: state.zoneOwnerName.isEmpty ? CKCurrentUserDefaultName : state.zoneOwnerName
    )
  }

  /// Apply a fetched `CKShare` to the matching `TripZoneState` row.
  /// Inserts a placeholder zone-state row when none exists locally for
  /// the share's zone — this happens on the participant side when the
  /// share arrives ahead of any trip records.
  static func from(_ share: CKShare, into context: ModelContext) throws {
    let zoneID = share.recordID.zoneID
    guard
      let tripID = parseTripID(from: zoneID.zoneName)
    else { return }
    let state =
      try existingState(tripID: tripID, in: context)
      ?? insertState(tripID: tripID, zoneID: zoneID, in: context)
    state.shareID = share.recordID.recordName
    state.zoneOwnerName = zoneID.ownerName
    state.ckRecordSystemFields = encodeSystemFields(of: share)
  }

  private static func parseTripID(from zoneName: String) -> UUID? {
    guard zoneName.hasPrefix("trip-") else { return nil }
    let suffix = zoneName.dropFirst("trip-".count)
    return UUID(uuidString: String(suffix))
  }

  private static func existingState(
    tripID: UUID, in context: ModelContext
  ) throws -> TripZoneState? {
    let descriptor = FetchDescriptor<TripZoneState>(predicate: #Predicate { $0.tripID == tripID })
    return try context.fetch(descriptor).first
  }

  private static func insertState(
    tripID: UUID,
    zoneID: CKRecordZone.ID,
    in context: ModelContext
  ) -> TripZoneState {
    let scope: String =
      zoneID.ownerName == CKCurrentUserDefaultName ? "private" : "shared"
    let state = TripZoneState(
      tripID: tripID,
      zoneOwnerName: zoneID.ownerName,
      zoneScope: scope,
      shareID: nil
    )
    context.insert(state)
    return state
  }
}
