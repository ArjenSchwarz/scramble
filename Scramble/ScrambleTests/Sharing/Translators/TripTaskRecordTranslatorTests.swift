import CloudKit
import Foundation
import SwiftData
import Testing

@testable import Scramble

@Suite("TripTaskRecordTranslator", .serialized)
@MainActor
struct TripTaskRecordTranslatorTests {

  @Test("toRecord encodes the parent trip relationship as a UUID-valued field, not a CKReference")
  func encodesTripRelationshipAsUUID() throws {
    let zoneID = Self.zoneID()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack", phase: .dayBefore)

    let record = try TripTaskRecordTranslator.toRecord(task, in: zoneID)
    #expect(record["tripID"] is String)
    #expect(record["tripID"] as? String == trip.id.uuidString)
    #expect((record["tripID"] as Any?) is String)
  }

  @Test("toRecord round-trips enum-valued fields as raw strings")
  func encodesEnumFieldsAsRawStrings() throws {
    let zoneID = Self.zoneID()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack", phase: .departureDay, source: .rule)

    let record = try TripTaskRecordTranslator.toRecord(task, in: zoneID)
    #expect(record["phaseRaw"] as? String == Phase.departureDay.rawValue)
    #expect(record["sourceRaw"] as? String == ItemSource.rule.rawValue)
  }

  @Test("from inserts a TripTask with userDeletedOnThisTrip absent → false default")
  func decodeMissingFieldUsesSwiftDefault() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let zoneID = Self.zoneID()
    let id = UUID()
    let record = CKRecord(
      recordType: TripTaskRecordTranslator.recordType,
      recordID: CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    )
    record["name"] = "Pack" as CKRecordValue
    // Deliberately omit `userDeletedOnThisTrip`.

    try TripTaskRecordTranslator.from(record, into: context)
    try context.save()

    let stored = try #require(try context.fetch(FetchDescriptor<TripTask>()).first)
    #expect(stored.userDeletedOnThisTrip == false)
  }

  @Test("from preserves CKRecord system fields by encoding into ckRecordSystemFields")
  func decodePersistsSystemFields() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let zoneID = Self.zoneID()
    let id = UUID()
    let record = CKRecord(
      recordType: TripTaskRecordTranslator.recordType,
      recordID: CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    )
    record["name"] = "Pack" as CKRecordValue

    try TripTaskRecordTranslator.from(record, into: context)
    try context.save()

    let stored = try #require(try context.fetch(FetchDescriptor<TripTask>()).first)
    let blob = try #require(stored.ckRecordSystemFields)
    let rebuilt = try #require(decodeSystemFields(from: blob))
    #expect(rebuilt.recordID.recordName == id.uuidString)
    #expect(rebuilt.recordType == TripTaskRecordTranslator.recordType)
  }

  @Test("System-fields preservation across roundtrip — record reused on second toRecord")
  func systemFieldsPreservedAcrossRoundtrip() throws {
    let zoneID = Self.zoneID()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack")

    let initial = try TripTaskRecordTranslator.toRecord(task, in: zoneID)
    let blob = encodeSystemFields(of: initial)
    let rebuilt = try #require(decodeSystemFields(from: blob))

    task.name = "Pack v2"
    let updated = try TripTaskRecordTranslator.toRecord(task, in: zoneID, existing: rebuilt)
    #expect(updated.recordID == initial.recordID)
    #expect(updated["name"] as? String == "Pack v2")
  }

  // MARK: - Helpers

  private static func zoneID() -> CKRecordZone.ID {
    CKRecordZone.ID(zoneName: "trip-\(UUID().uuidString)", ownerName: CKCurrentUserDefaultName)
  }

  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }
}
