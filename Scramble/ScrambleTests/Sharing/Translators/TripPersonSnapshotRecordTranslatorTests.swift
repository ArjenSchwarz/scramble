import CloudKit
import Foundation
import SwiftData
import Testing

@testable import Scramble

@Suite("TripPersonSnapshotRecordTranslator", .serialized)
@MainActor
struct TripPersonSnapshotRecordTranslatorTests {

  @Test("toRecord encodes personID + name + colourID + roster flag")
  func encodesAllFields() throws {
    let zoneID = Self.zoneID()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let snapshot = TripPersonSnapshot(
      personID: UUID(),
      name: "Alice",
      colourID: "cyan",
      initialSource: "name",
      isRosterMember: true,
      trip: trip
    )

    let record = try TripPersonSnapshotRecordTranslator.toRecord(snapshot, in: zoneID)
    #expect(record["personID"] as? String == snapshot.personID.uuidString)
    #expect(record["name"] as? String == "Alice")
    #expect(record["colourID"] as? String == "cyan")
    #expect(record["initialSource"] as? String == "name")
    #expect(record["isRosterMember"] as? Bool == true)
    #expect(record["tripID"] as? String == trip.id.uuidString)
  }

  @Test("from inserts a snapshot when none exists locally")
  func decodeInsertsWhenAbsent() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let zoneID = Self.zoneID()
    let id = UUID()
    let personID = UUID()
    let record = CKRecord(
      recordType: TripPersonSnapshotRecordTranslator.recordType,
      recordID: CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    )
    record["personID"] = personID.uuidString as CKRecordValue
    record["name"] = "Bob" as CKRecordValue
    record["colourID"] = "green" as CKRecordValue
    record["initialSource"] = "name" as CKRecordValue
    record["isRosterMember"] = true as CKRecordValue

    try TripPersonSnapshotRecordTranslator.from(record, into: context)
    try context.save()

    let stored = try #require(try context.fetch(FetchDescriptor<TripPersonSnapshot>()).first)
    #expect(stored.id == id)
    #expect(stored.personID == personID)
    #expect(stored.name == "Bob")
    #expect(stored.colourID == "green")
    #expect(stored.isRosterMember == true)
  }

  @Test("from on a fetched snapshot with isRosterMember missing keeps Swift default true")
  func decodeMissingRosterFlagKeepsDefault() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let zoneID = Self.zoneID()
    let id = UUID()
    let record = CKRecord(
      recordType: TripPersonSnapshotRecordTranslator.recordType,
      recordID: CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    )
    record["personID"] = UUID().uuidString as CKRecordValue
    // isRosterMember intentionally absent.

    try TripPersonSnapshotRecordTranslator.from(record, into: context)
    try context.save()

    let stored = try #require(try context.fetch(FetchDescriptor<TripPersonSnapshot>()).first)
    #expect(stored.isRosterMember == true, "Swift default for isRosterMember is true")
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
