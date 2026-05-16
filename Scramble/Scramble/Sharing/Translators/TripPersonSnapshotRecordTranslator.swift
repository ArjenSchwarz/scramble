import CloudKit
import Foundation
import SwiftData

/// `TripPersonSnapshot` ↔ `CKRecord` translator. Carries the denormalised
/// person identity inside the trip zone so participants render avatars and
/// names without crossing into the owner's globals (Decision 7).
@MainActor
enum TripPersonSnapshotRecordTranslator {
  static let recordType: String = "TripPersonSnapshot"

  static func recordID(
    for snapshot: TripPersonSnapshot, in zoneID: CKRecordZone.ID
  ) -> CKRecord.ID {
    CKRecord.ID(recordName: snapshot.id.uuidString, zoneID: zoneID)
  }

  static func toRecord(
    _ snapshot: TripPersonSnapshot,
    in zoneID: CKRecordZone.ID,
    existing: CKRecord? = nil
  ) throws -> CKRecord {
    let record =
      existing
      ?? CKRecord(recordType: recordType, recordID: recordID(for: snapshot, in: zoneID))
    record["personID"] = snapshot.personID.uuidString as CKRecordValue
    record["name"] = snapshot.name as CKRecordValue
    record["colourID"] = snapshot.colourID as CKRecordValue
    record["initialSource"] = snapshot.initialSource as CKRecordValue
    record["isRosterMember"] = snapshot.isRosterMember as CKRecordValue
    if let trip = snapshot.trip {
      record["tripID"] = trip.id.uuidString as CKRecordValue
    } else {
      record["tripID"] = nil
    }
    return record
  }

  static func from(_ record: CKRecord, into context: ModelContext) throws {
    guard record.recordType == recordType else {
      throw TranslatorError.recordTypeMismatch(expected: recordType, actual: record.recordType)
    }
    guard let id = UUID(uuidString: record.recordID.recordName) else { return }
    let snapshot =
      try existingSnapshot(id: id, in: context) ?? insertSnapshot(id: id, in: context)

    let personID = (record["personID"] as? String).flatMap(UUID.init(uuidString:))
    if let personID {
      snapshot.personID = personID
    }
    if let name = record["name"] as? String { snapshot.name = name }
    if let colourID = record["colourID"] as? String { snapshot.colourID = colourID }
    if let initialSource = record["initialSource"] as? String {
      snapshot.initialSource = initialSource
    }
    if let isRosterMember = record["isRosterMember"] as? Bool {
      snapshot.isRosterMember = isRosterMember
    }
    let tripID = (record["tripID"] as? String).flatMap(UUID.init(uuidString:))
    if let tripID {
      snapshot.trip = try fetchTrip(id: tripID, in: context)
    }
    snapshot.ckRecordSystemFields = encodeSystemFields(of: record)
  }

  private static func existingSnapshot(
    id: UUID, in context: ModelContext
  ) throws -> TripPersonSnapshot? {
    let descriptor = FetchDescriptor<TripPersonSnapshot>(predicate: #Predicate { $0.id == id })
    return try context.fetch(descriptor).first
  }

  private static func insertSnapshot(id: UUID, in context: ModelContext) -> TripPersonSnapshot {
    let snapshot = TripPersonSnapshot(id: id)
    context.insert(snapshot)
    return snapshot
  }

  private static func fetchTrip(id: UUID, in context: ModelContext) throws -> Trip? {
    let descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })
    return try context.fetch(descriptor).first
  }
}
