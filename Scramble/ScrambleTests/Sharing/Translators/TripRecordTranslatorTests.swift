import CloudKit
import Foundation
import SwiftData
import Testing

@testable import Scramble

@Suite("TripRecordTranslator", .serialized)
@MainActor
struct TripRecordTranslatorTests {

  // MARK: - Encoding (toRecord)

  @Test("toRecord stores trip name, dates, and attribute blob")
  func encodesAllScalarFields() throws {
    let zoneID = Self.zoneID()
    let trip = Self.makeTrip(name: "Iceland", days: 7)
    var attrs = trip.attributes
    attrs.setSingle(.weather, value: "cold")
    trip.attributes = attrs

    let record = try TripRecordTranslator.toRecord(trip, in: zoneID, existing: nil)

    #expect(record.recordType == TripRecordTranslator.recordType)
    #expect(record["name"] as? String == "Iceland")
    #expect(record["startDate"] is Date)
    #expect(record["endDate"] is Date)
    let blob = try #require(record["attributesData"] as? Data)
    let decoded = try JSONDecoder().decode(TripAttributes.self, from: blob)
    #expect(decoded.selected(.weather) == ["cold"])
  }

  @Test("toRecord on an existing record preserves system fields by reusing the record")
  func preservesSystemFieldsAcrossRoundtrip() throws {
    let zoneID = Self.zoneID()
    let trip = Self.makeTrip(name: "T", days: 1)
    let initial = try TripRecordTranslator.toRecord(trip, in: zoneID, existing: nil)

    let blob = encodeSystemFields(of: initial)
    let rebuilt = try #require(decodeSystemFields(from: blob))

    trip.name = "Renamed"
    let updated = try TripRecordTranslator.toRecord(trip, in: zoneID, existing: rebuilt)

    #expect(updated.recordID == initial.recordID)
    #expect(updated["name"] as? String == "Renamed")
  }

  @Test("toRecord throws blobTooLarge when attributes JSON exceeds 256 KB")
  func throwsWhenBlobExceedsSizeCap() throws {
    let zoneID = Self.zoneID()
    let trip = Self.makeTrip(name: "T", days: 1)
    // Build an oversized blob deterministically by injecting a value
    // larger than the cap.
    let huge = String(repeating: "x", count: kRecordBlobSizeCap + 16)
    var attrs = trip.attributes
    attrs.setSingle(.purpose, value: huge)
    trip.attributes = attrs

    #expect(throws: TranslatorError.self) {
      _ = try TripRecordTranslator.toRecord(trip, in: zoneID, existing: nil)
    }
  }

  // MARK: - Decoding (from)

  @Test("from inserts a Trip when none exists locally")
  func decodeInsertsNewTrip() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let zoneID = Self.zoneID()
    let id = UUID()
    let record = CKRecord(
      recordType: TripRecordTranslator.recordType,
      recordID: CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    )
    record["name"] = "Reykjavík" as CKRecordValue
    record["startDate"] = Date(timeIntervalSince1970: 1_700_000_000) as CKRecordValue
    record["endDate"] = Date(timeIntervalSince1970: 1_700_500_000) as CKRecordValue
    record["attributesData"] = Data() as CKRecordValue

    try TripRecordTranslator.from(record, into: context)
    try context.save()

    let stored = try context.fetch(FetchDescriptor<Trip>())
    #expect(stored.count == 1)
    #expect(stored.first?.id == id)
    #expect(stored.first?.name == "Reykjavík")
    #expect(stored.first?.ckRecordSystemFields != nil)
  }

  @Test("from on an existing Trip merges scalar fields without duplicating the row")
  func decodeMergesIntoExistingTrip() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let zoneID = Self.zoneID()
    let id = UUID()
    let trip = Trip(id: id, name: "Old")
    context.insert(trip)
    try context.save()

    let record = CKRecord(
      recordType: TripRecordTranslator.recordType,
      recordID: CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    )
    record["name"] = "New" as CKRecordValue
    try TripRecordTranslator.from(record, into: context)
    try context.save()

    let stored = try context.fetch(FetchDescriptor<Trip>())
    #expect(stored.count == 1, "Decode must update, not duplicate")
    #expect(stored.first?.name == "New")
  }

  @Test("from throws recordTypeMismatch when fed a record of a different type")
  func decodeRejectsWrongRecordType() throws {
    let container = try Self.makeContainer()
    let zoneID = Self.zoneID()
    let record = CKRecord(
      recordType: "SomethingElse",
      recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)
    )
    #expect(throws: TranslatorError.self) {
      try TripRecordTranslator.from(record, into: container.mainContext)
    }
  }

  // MARK: - countryCode round-trip (Phase 6 Req 6.1, 6.5)

  @Test("toRecord stores countryCode when set; from(_:into:) writes it back")
  func encodesAndDecodesCountryCodeWhenSet() throws {
    let zoneID = Self.zoneID()
    let trip = Self.makeTrip(name: "Iceland", days: 7)
    trip.countryCode = "IS"

    let record = try TripRecordTranslator.toRecord(trip, in: zoneID, existing: nil)
    #expect(record["countryCode"] as? String == "IS")

    let container = try Self.makeContainer()
    let context = container.mainContext
    try TripRecordTranslator.from(record, into: context)
    try context.save()

    let decoded = try #require(try context.fetch(FetchDescriptor<Trip>()).first)
    #expect(decoded.countryCode == "IS")
  }

  @Test("toRecord clears countryCode on the CKRecord when trip.countryCode is nil")
  func encodesNilCountryCodeAsAbsentField() throws {
    let zoneID = Self.zoneID()
    let trip = Self.makeTrip(name: "Iceland", days: 7)
    trip.countryCode = nil

    let record = try TripRecordTranslator.toRecord(trip, in: zoneID, existing: nil)
    #expect(record["countryCode"] == nil)
  }

  @Test("Set → unset → set toggle round-trips countryCode through the same CKRecord")
  func togglesCountryCodeThroughExistingRecord() throws {
    let zoneID = Self.zoneID()
    let trip = Self.makeTrip(name: "Toggle", days: 2)
    trip.countryCode = "NL"

    let initial = try TripRecordTranslator.toRecord(trip, in: zoneID, existing: nil)
    #expect(initial["countryCode"] as? String == "NL")

    trip.countryCode = nil
    let cleared = try TripRecordTranslator.toRecord(trip, in: zoneID, existing: initial)
    #expect(cleared["countryCode"] == nil)

    trip.countryCode = "JP"
    let updated = try TripRecordTranslator.toRecord(trip, in: zoneID, existing: cleared)
    #expect(updated["countryCode"] as? String == "JP")
  }

  @Test(
    """
    from(_:into:) clears countryCode when the record omits the field — \
    propagating an owner-side clear (which toRecord serialises by removing \
    the field) to participants.
    """
  )
  func decodeClearsCountryCodeOnMissingField() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let zoneID = Self.zoneID()
    let id = UUID()
    let trip = Trip(id: id, name: "Existing")
    trip.countryCode = "DE"
    context.insert(trip)
    try context.save()

    let record = CKRecord(
      recordType: TripRecordTranslator.recordType,
      recordID: CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    )
    record["name"] = "Renamed" as CKRecordValue
    try TripRecordTranslator.from(record, into: context)
    try context.save()

    let stored = try #require(try context.fetch(FetchDescriptor<Trip>()).first)
    #expect(stored.countryCode == nil)
    #expect(stored.name == "Renamed")
  }

  // MARK: - Helpers

  private static func zoneID() -> CKRecordZone.ID {
    CKRecordZone.ID(zoneName: "trip-\(UUID().uuidString)", ownerName: CKCurrentUserDefaultName)
  }

  private static func makeTrip(name: String, days: Int) -> Trip {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end =
      Calendar(identifier: .gregorian)
      .date(byAdding: .day, value: days, to: start) ?? start
    return Trip(name: name, startDate: start, endDate: end)
  }

  static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }
}
