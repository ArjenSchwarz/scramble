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

  // MARK: - note + subItems round-trip (feature packing-item-subitems, Req 6.2)

  @Test("note + subItems survive a toRecord → from round-trip without loss or reorder")
  func noteAndSubItemsRoundTrip() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let zoneID = Self.zoneID()
    let id = UUID()
    let source = TripPackingItem(id: id, name: "Toys", note: "keep batteries out")
    source.subItems = ["lego", "blocks", "lego"]  // duplicate kept (Req 2.6)

    let record = try TripPackingItemRecordTranslator.toRecord(source, in: zoneID)
    try TripPackingItemRecordTranslator.from(record, into: context)
    try context.save()

    let stored = try #require(try context.fetch(FetchDescriptor<TripPackingItem>()).first)
    #expect(stored.note == "keep batteries out")
    // Order preserved exactly, duplicate retained (Req 1.3, 2.6, 6.2).
    #expect(stored.subItems == ["lego", "blocks", "lego"])
  }

  // MARK: - Clear matrix (Req 6.5, Decision 10/12)

  @Test(
    "toRecord serialises {nil, empty Data(), non-empty} subItemsData as {absent, absent, present}")
  func subItemsDataClearMatrixEncodes() throws {
    let zoneID = Self.zoneID()

    let nilItem = TripPackingItem(name: "A")
    nilItem.subItemsData = nil
    let nilRecord = try TripPackingItemRecordTranslator.toRecord(nilItem, in: zoneID)
    #expect(nilRecord["subItemsData"] == nil, "nil ⇒ absent field")

    // A non-nil empty Data() must serialise as an ABSENT field, not an
    // empty blob, so a cleared list reads back as [] on the receiver.
    let emptyItem = TripPackingItem(name: "B")
    emptyItem.subItemsData = Data()
    let emptyRecord = try TripPackingItemRecordTranslator.toRecord(emptyItem, in: zoneID)
    #expect(emptyRecord["subItemsData"] == nil, "empty Data() ⇒ absent field, not empty blob")

    let fullItem = TripPackingItem(name: "C")
    fullItem.subItems = ["x"]
    let fullRecord = try TripPackingItemRecordTranslator.toRecord(fullItem, in: zoneID)
    #expect((fullRecord["subItemsData"] as Any?) is Data, "non-empty ⇒ present blob")
  }

  @Test("toRecord serialises {nil, non-empty} note as {absent, present}")
  func noteClearMatrixEncodes() throws {
    let zoneID = Self.zoneID()

    let nilItem = TripPackingItem(name: "A", note: nil)
    let nilRecord = try TripPackingItemRecordTranslator.toRecord(nilItem, in: zoneID)
    #expect(nilRecord["note"] == nil, "nil note ⇒ absent field")

    let setItem = TripPackingItem(name: "B", note: "hello")
    let setRecord = try TripPackingItemRecordTranslator.toRecord(setItem, in: zoneID)
    #expect(setRecord["note"] as? String == "hello")
  }

  @Test("populated → cleared note propagates nil to the receiver (Req 6.5)")
  func populatedThenClearedNotePropagates() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let zoneID = Self.zoneID()
    let id = UUID()

    // Receiver already holds a populated note + sub-items.
    let existing = TripPackingItem(id: id, name: "Toys", note: "old note")
    existing.subItems = ["a", "b"]
    context.insert(existing)
    try context.save()

    // Sender cleared both — toRecord emits absent fields.
    let cleared = TripPackingItem(id: id, name: "Toys")
    cleared.note = nil
    cleared.subItemsData = nil
    let record = try TripPackingItemRecordTranslator.toRecord(cleared, in: zoneID)

    try TripPackingItemRecordTranslator.from(record, into: context)
    try context.save()

    let stored = try #require(try context.fetch(FetchDescriptor<TripPackingItem>()).first)
    #expect(stored.note == nil, "cleared note must reach the receiver")
    #expect(stored.subItems == [], "cleared list must reach the receiver")
    #expect(stored.subItemsData == nil)
  }

  // MARK: - blobTooLarge guard (Req 6.4)

  @Test("toRecord throws blobTooLarge when subItemsData is forced over the cap")
  func subItemsBlobTooLargeThrows() throws {
    let zoneID = Self.zoneID()
    let item = TripPackingItem(name: "Toys")
    // Force the blob past the cap directly (the inline caps make this
    // unreachable in normal use, but the guard must still fire).
    item.subItemsData = Data(repeating: 0x41, count: kRecordBlobSizeCap + 16)

    #expect(throws: TranslatorError.self) {
      _ = try TripPackingItemRecordTranslator.toRecord(item, in: zoneID)
    }
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
