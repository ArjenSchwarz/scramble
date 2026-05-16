import CloudKit
import Foundation
import SwiftData
import Testing

@testable import Scramble

@Suite("TripPackingItemRecordTranslator", .serialized)
@MainActor
struct TripPackingItemRecordTranslatorTests {

  @Test("toRecord encodes personSnapshot relationship as personSnapshotID String")
  func encodesPersonSnapshotAsUUIDString() throws {
    let zoneID = Self.zoneID()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let snapshot = TripPersonSnapshot(personID: UUID(), name: "Alice", colourID: "cyan")
    let item = TripPackingItem(
      trip: trip,
      name: "Toothbrush",
      personSnapshot: snapshot
    )

    let record = try TripPackingItemRecordTranslator.toRecord(item, in: zoneID)
    #expect(record["personSnapshotID"] as? String == snapshot.id.uuidString)
    // Defensive — must NOT be a CKReference.
    #expect((record["personSnapshotID"] as Any?) is String)
  }

  @Test("toRecord encodes nil personSnapshot as a missing record field")
  func encodesNilPersonSnapshot() throws {
    let zoneID = Self.zoneID()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let item = TripPackingItem(trip: trip, name: "Towel")

    let record = try TripPackingItemRecordTranslator.toRecord(item, in: zoneID)
    #expect(record["personSnapshotID"] == nil)
  }

  @Test("from links personSnapshotID to an existing TripPersonSnapshot in tripsLocal")
  func decodeLinksPersonSnapshotByID() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let zoneID = Self.zoneID()
    let trip = Trip(id: UUID(), name: "T")
    context.insert(trip)
    let snapshot = TripPersonSnapshot(
      personID: UUID(), name: "Alice", colourID: "cyan", trip: trip)
    context.insert(snapshot)
    try context.save()

    let id = UUID()
    let record = CKRecord(
      recordType: TripPackingItemRecordTranslator.recordType,
      recordID: CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    )
    record["tripID"] = trip.id.uuidString as CKRecordValue
    record["personSnapshotID"] = snapshot.id.uuidString as CKRecordValue
    record["name"] = "Toothbrush" as CKRecordValue

    try TripPackingItemRecordTranslator.from(record, into: context)
    try context.save()

    let stored = try #require(try context.fetch(FetchDescriptor<TripPackingItem>()).first)
    #expect(stored.personSnapshot?.id == snapshot.id)
    #expect(stored.trip?.id == trip.id)
  }

  @Test("from on a record whose stateRaw is missing leaves the Swift default in place")
  func decodeMissingEnumKeepsDefault() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let zoneID = Self.zoneID()
    let id = UUID()
    let record = CKRecord(
      recordType: TripPackingItemRecordTranslator.recordType,
      recordID: CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    )
    record["name"] = "Toothbrush" as CKRecordValue

    try TripPackingItemRecordTranslator.from(record, into: context)
    try context.save()

    let stored = try #require(try context.fetch(FetchDescriptor<TripPackingItem>()).first)
    #expect(stored.state == .unpacked)
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
