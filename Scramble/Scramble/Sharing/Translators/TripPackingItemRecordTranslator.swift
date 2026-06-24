import CloudKit
import Foundation
import SwiftData

/// `TripPackingItem` ↔ `CKRecord` translator. The `personSnapshotID`
/// value reference is encoded as `personSnapshotID: String` per the
/// design's "relationships are UUID record fields" rule (Decision 13).
@MainActor
enum TripPackingItemRecordTranslator {
  static let recordType: String = "TripPackingItem"

  static func recordID(for item: TripPackingItem, in zoneID: CKRecordZone.ID) -> CKRecord.ID {
    CKRecord.ID(recordName: item.id.uuidString, zoneID: zoneID)
  }

  static func toRecord(
    _ item: TripPackingItem,
    in zoneID: CKRecordZone.ID,
    existing: CKRecord? = nil
  ) throws -> CKRecord {
    let record =
      existing ?? CKRecord(recordType: recordType, recordID: recordID(for: item, in: zoneID))
    if let trip = item.trip {
      record["tripID"] = trip.id.uuidString as CKRecordValue
    } else {
      record["tripID"] = nil
    }
    record["personSnapshotID"] = item.personSnapshotID?.uuidString as CKRecordValue?
    record["masterItemID"] = item.masterItemID?.uuidString as CKRecordValue?
    record["name"] = item.name as CKRecordValue
    record["stateRaw"] = item.stateRaw as CKRecordValue
    record["sourceRaw"] = item.sourceRaw as CKRecordValue
    record["currentlyMatchesRules"] = item.currentlyMatchesRules as CKRecordValue
    record["pinnedByUser"] = item.pinnedByUser as CKRecordValue
    // Feature `packing-item-subitems`. Assigning `CKRecordValue?(nil)`
    // clears the field so a user who clears the note propagates the
    // deletion to other devices (Req 6.5, Decision 10/12 — the
    // `masterItemID` / `countryCode` clear-propagation precedent).
    record["note"] = item.note as CKRecordValue?
    // Write the sub-item blob only when non-empty. A `nil` or a non-nil
    // empty `Data()` both serialise as an ABSENT field — never a present
    // empty blob — so a cleared list reads back as `[]` on the receiver.
    // This is the first Codable blob on this translator, so the
    // `kRecordBlobSizeCap` guard is net-new here (Decision 8/11): the
    // 50×200 inline caps keep the blob far under the cap, so the throw is
    // effectively unreachable but retained as defence.
    if let subItemsData = item.subItemsData, !subItemsData.isEmpty {
      guard subItemsData.count <= kRecordBlobSizeCap else {
        throw TranslatorError.blobTooLarge(field: "subItemsData", size: subItemsData.count)
      }
      record["subItemsData"] = subItemsData as CKRecordValue
    } else {
      record["subItemsData"] = nil
    }
    return record
  }

  /// Decode a `CKRecord` into the matching `TripPackingItem`.
  ///
  /// - Important: This requires a FULL server snapshot. Never pass a
  ///   partial / `desiredKeys` record here. `note` and `subItemsData`
  ///   are assigned UNCONDITIONALLY (clear-propagation, Req 6.5 /
  ///   Decision 12), so an absent field is read as "cleared" — a partial
  ///   record would silently wipe local note / sub-items. `CKSyncEngine`'s
  ///   fetch path delivers full records, so this holds today; keep it
  ///   that way if a `desiredKeys` path is ever added.
  /// - Note: Forward-compat constraint — a record written by a *pre-feature*
  ///   app build never carries `note` / `subItemsData`, so the unconditional
  ///   clear here wipes a newer client's locally-entered values when an older
  ///   client edits the same item. Acceptable at v1 (single user, no mixed-
  ///   version fleet); revisit if old + new builds must coexist. See
  ///   `docs/agent-notes/sync-infrastructure.md`.
  static func from(_ record: CKRecord, into context: ModelContext) throws {
    guard record.recordType == recordType else {
      throw TranslatorError.recordTypeMismatch(expected: recordType, actual: record.recordType)
    }
    guard let id = UUID(uuidString: record.recordID.recordName) else { return }
    let item = try existingItem(id: id, in: context) ?? insertItem(id: id, in: context)

    let tripID = (record["tripID"] as? String).flatMap(UUID.init(uuidString:))
    if let tripID {
      item.trip = try fetchTrip(id: tripID, in: context)
    }
    // Only assign when the key resolves to a UUID. Absence on the inbound
    // record means "no change" — we cannot distinguish a field the sender
    // omitted from a field the sender cleared, so the conservative read
    // matches the `tripID` handling above and avoids destroying the local
    // value when an older client schema didn't carry the field.
    let snapshotID = (record["personSnapshotID"] as? String)
      .flatMap(UUID.init(uuidString:))
    if let snapshotID {
      // Store the bare ID — dangling references are tolerated. The
      // snapshot may not have synced into this store yet; the
      // `personSnapshot` bridge resolves it on read once it arrives.
      item.personSnapshotID = snapshotID
    }
    item.masterItemID =
      (record["masterItemID"] as? String).flatMap(UUID.init(uuidString:))
    if let name = record["name"] as? String { item.name = name }
    if let stateRaw = record["stateRaw"] as? String { item.stateRaw = stateRaw }
    if let sourceRaw = record["sourceRaw"] as? String { item.sourceRaw = sourceRaw }
    if let currentlyMatchesRules = record["currentlyMatchesRules"] as? Bool {
      item.currentlyMatchesRules = currentlyMatchesRules
    }
    if let pinnedByUser = record["pinnedByUser"] as? Bool { item.pinnedByUser = pinnedByUser }
    // Feature `packing-item-subitems`. Unconditional assignment so a
    // clear on the wire reaches this device (Req 6.5 / Decision 12 —
    // diverging from the `if let` sibling fields above, following the
    // `masterItemID` in-file precedent). Relies on the full-snapshot
    // contract documented on this method.
    item.note = record["note"] as? String
    item.subItemsData = record["subItemsData"] as? Data
    item.ckRecordSystemFields = encodeSystemFields(of: record)
  }

  private static func existingItem(id: UUID, in context: ModelContext) throws -> TripPackingItem? {
    let descriptor = FetchDescriptor<TripPackingItem>(predicate: #Predicate { $0.id == id })
    return try context.fetch(descriptor).first
  }

  private static func insertItem(id: UUID, in context: ModelContext) -> TripPackingItem {
    let item = TripPackingItem(id: id)
    context.insert(item)
    return item
  }

  private static func fetchTrip(id: UUID, in context: ModelContext) throws -> Trip? {
    let descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })
    return try context.fetch(descriptor).first
  }
}
