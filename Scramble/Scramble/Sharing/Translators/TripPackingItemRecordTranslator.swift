import CloudKit
import Foundation
import SwiftData

/// `TripPackingItem` ↔ `CKRecord` translator. The `personSnapshot`
/// relationship is encoded as `personSnapshotID: String` per the design's
/// "relationships are UUID record fields" rule (Decision 13).
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
    record["personSnapshotID"] = item.personSnapshot?.id.uuidString as CKRecordValue?
    record["masterItemID"] = item.masterItemID?.uuidString as CKRecordValue?
    record["name"] = item.name as CKRecordValue
    record["stateRaw"] = item.stateRaw as CKRecordValue
    record["sourceRaw"] = item.sourceRaw as CKRecordValue
    record["currentlyMatchesRules"] = item.currentlyMatchesRules as CKRecordValue
    record["pinnedByUser"] = item.pinnedByUser as CKRecordValue
    return record
  }

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
    let snapshotID = (record["personSnapshotID"] as? String)
      .flatMap(UUID.init(uuidString:))
    if let snapshotID {
      item.personSnapshot = try fetchSnapshot(id: snapshotID, in: context)
    } else if record["personSnapshotID"] == nil {
      item.personSnapshot = nil
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

  private static func fetchSnapshot(
    id: UUID, in context: ModelContext
  ) throws -> TripPersonSnapshot? {
    let descriptor = FetchDescriptor<TripPersonSnapshot>(predicate: #Predicate { $0.id == id })
    return try context.fetch(descriptor).first
  }
}
