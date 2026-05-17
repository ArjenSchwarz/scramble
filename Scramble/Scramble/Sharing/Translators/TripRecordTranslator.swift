import CloudKit
import Foundation
import SwiftData

/// `Trip` ↔ `CKRecord` translator. Implementation lands in task 9.
@MainActor
enum TripRecordTranslator {
  static let recordType: String = "Trip"

  static func recordID(for trip: Trip, in zoneID: CKRecordZone.ID) -> CKRecord.ID {
    CKRecord.ID(recordName: trip.id.uuidString, zoneID: zoneID)
  }

  static func toRecord(
    _ trip: Trip,
    in zoneID: CKRecordZone.ID,
    existing: CKRecord? = nil
  ) throws -> CKRecord {
    let record =
      existing ?? CKRecord(recordType: recordType, recordID: recordID(for: trip, in: zoneID))
    record["name"] = trip.name as CKRecordValue
    record["startDate"] = trip.startDate as CKRecordValue
    record["endDate"] = trip.endDate as CKRecordValue
    if trip.attributesData.count > kRecordBlobSizeCap {
      throw TranslatorError.blobTooLarge(field: "attributesData", size: trip.attributesData.count)
    }
    record["attributesData"] = trip.attributesData as CKRecordValue
    return record
  }

  static func from(_ record: CKRecord, into context: ModelContext) throws {
    guard record.recordType == recordType else {
      throw TranslatorError.recordTypeMismatch(expected: recordType, actual: record.recordType)
    }
    guard let id = UUID(uuidString: record.recordID.recordName) else { return }
    let trip = try existingTrip(id: id, in: context) ?? insertTrip(id: id, in: context)
    if let name = record["name"] as? String { trip.name = name }
    if let startDate = record["startDate"] as? Date { trip.startDate = startDate }
    if let endDate = record["endDate"] as? Date { trip.endDate = endDate }
    if let attributesData = record["attributesData"] as? Data {
      trip.attributesData = attributesData
    }
    trip.ckRecordSystemFields = encodeSystemFields(of: record)
  }

  private static func existingTrip(id: UUID, in context: ModelContext) throws -> Trip? {
    let descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })
    return try context.fetch(descriptor).first
  }

  private static func insertTrip(id: UUID, in context: ModelContext) -> Trip {
    let trip = Trip(id: id, name: "")
    context.insert(trip)
    return trip
  }
}

/// Encode a `CKRecord`'s system fields into a `Data` blob suitable for
/// storage in a model's `ckRecordSystemFields` property. The companion
/// `decodeSystemFields(from:)` rebuilds the bare `CKRecord` shell so a
/// later `toRecord(_:in:existing:)` call layers user fields on top
/// without losing the server change tag / share state.
@MainActor
func encodeSystemFields(of record: CKRecord) -> Data {
  let coder = NSKeyedArchiver(requiringSecureCoding: true)
  record.encodeSystemFields(with: coder)
  coder.finishEncoding()
  return coder.encodedData
}

@MainActor
func decodeSystemFields(from data: Data) -> CKRecord? {
  guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
  coder.requiresSecureCoding = true
  return CKRecord(coder: coder)
}
