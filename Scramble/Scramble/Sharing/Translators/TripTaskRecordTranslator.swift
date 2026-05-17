import CloudKit
import Foundation
import SwiftData

/// `TripTask` ↔ `CKRecord` translator (Decision 13). Relationships are
/// encoded as UUID strings, never as `CKRecord.Reference`.
@MainActor
enum TripTaskRecordTranslator {
  static let recordType: String = "TripTask"

  static func recordID(for task: TripTask, in zoneID: CKRecordZone.ID) -> CKRecord.ID {
    CKRecord.ID(recordName: task.id.uuidString, zoneID: zoneID)
  }

  static func toRecord(
    _ task: TripTask,
    in zoneID: CKRecordZone.ID,
    existing: CKRecord? = nil
  ) throws -> CKRecord {
    let record =
      existing ?? CKRecord(recordType: recordType, recordID: recordID(for: task, in: zoneID))
    if let trip = task.trip {
      record["tripID"] = trip.id.uuidString as CKRecordValue
    } else {
      record["tripID"] = nil
    }
    record["masterItemID"] = task.masterItemID?.uuidString as CKRecordValue?
    record["name"] = task.name as CKRecordValue
    record["phaseRaw"] = task.phaseRaw as CKRecordValue
    record["isCompleted"] = task.isCompleted as CKRecordValue
    record["sourceRaw"] = task.sourceRaw as CKRecordValue
    record["currentlyMatchesRules"] = task.currentlyMatchesRules as CKRecordValue
    record["pinnedByUser"] = task.pinnedByUser as CKRecordValue
    record["assigneePersonID"] = task.assigneePersonID?.uuidString as CKRecordValue?
    record["userDeletedOnThisTrip"] = task.userDeletedOnThisTrip as CKRecordValue
    return record
  }

  static func from(_ record: CKRecord, into context: ModelContext) throws {
    guard record.recordType == recordType else {
      throw TranslatorError.recordTypeMismatch(expected: recordType, actual: record.recordType)
    }
    guard let id = UUID(uuidString: record.recordID.recordName) else { return }
    let task = try existingTask(id: id, in: context) ?? insertTask(id: id, in: context)

    let tripID = (record["tripID"] as? String).flatMap(UUID.init(uuidString:))
    if let tripID {
      task.trip = try fetchTrip(id: tripID, in: context)
    }
    task.masterItemID =
      (record["masterItemID"] as? String).flatMap(UUID.init(uuidString:))
    if let name = record["name"] as? String { task.name = name }
    if let phaseRaw = record["phaseRaw"] as? String { task.phaseRaw = phaseRaw }
    if let isCompleted = record["isCompleted"] as? Bool { task.isCompleted = isCompleted }
    if let sourceRaw = record["sourceRaw"] as? String { task.sourceRaw = sourceRaw }
    if let currentlyMatchesRules = record["currentlyMatchesRules"] as? Bool {
      task.currentlyMatchesRules = currentlyMatchesRules
    }
    if let pinnedByUser = record["pinnedByUser"] as? Bool { task.pinnedByUser = pinnedByUser }
    task.assigneePersonID =
      (record["assigneePersonID"] as? String).flatMap(UUID.init(uuidString:))
    if let userDeleted = record["userDeletedOnThisTrip"] as? Bool {
      task.userDeletedOnThisTrip = userDeleted
    }
    task.ckRecordSystemFields = encodeSystemFields(of: record)
  }

  private static func existingTask(id: UUID, in context: ModelContext) throws -> TripTask? {
    let descriptor = FetchDescriptor<TripTask>(predicate: #Predicate { $0.id == id })
    return try context.fetch(descriptor).first
  }

  private static func insertTask(id: UUID, in context: ModelContext) -> TripTask {
    let task = TripTask(id: id)
    context.insert(task)
    return task
  }

  private static func fetchTrip(id: UUID, in context: ModelContext) throws -> Trip? {
    let descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })
    return try context.fetch(descriptor).first
  }
}
