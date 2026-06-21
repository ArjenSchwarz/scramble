import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Coverage for the `TripPackingItem.note` / `subItems` per-trip content
/// fields (feature `packing-item-subitems`). `subItems` is a `CodableBridge`
/// blob over `subItemsData: Data?` whose invariant is "empty list => no
/// sub-items", treated identically whether `subItemsData` is `nil` or a
/// non-nil empty `Data()`. `note` is a plain `String?`. Both ride on
/// `SchemaV3` as Optionals (no `SchemaV4`).
@Suite("TripPackingItem.note / subItems bridge", .serialized)
@MainActor
struct TripPackingItemContentBridgeTests {

  @Test("subItems get/set round-trips through subItemsData")
  func subItemsRoundTrip() throws {
    let context = try Self.makeContext()
    let item = TripPackingItem(name: "Toys")
    context.insert(item)

    item.subItems = ["dice", "cards", "blocks"]
    try context.save()

    #expect(item.subItems == ["dice", "cards", "blocks"])
    #expect(item.subItemsData != nil)
  }

  @Test("setting subItems = [] clears subItemsData to nil")
  func emptyListClearsData() throws {
    let context = try Self.makeContext()
    let item = TripPackingItem(name: "Books")
    context.insert(item)

    item.subItems = ["one", "two"]
    #expect(item.subItemsData != nil)

    item.subItems = []
    #expect(item.subItemsData == nil)
    #expect(item.subItems == [])
  }

  @Test("non-nil empty Data() reads back as []")
  func nonNilEmptyDataReadsAsEmpty() throws {
    let context = try Self.makeContext()
    let item = TripPackingItem(name: "Snacks")
    context.insert(item)

    // CodableBridge.encode returns empty Data() (never nil) on its degrade
    // path; the getter must normalise that to [].
    item.subItemsData = Data()
    #expect(item.subItems == [])
  }

  @Test("garbage Data decodes to []")
  func garbageDataDecodesToEmpty() throws {
    let context = try Self.makeContext()
    let item = TripPackingItem(name: "Gear")
    context.insert(item)

    item.subItemsData = Data([0x00, 0xFF, 0x42])
    #expect(item.subItems == [])
  }

  @Test("note set then cleared")
  func noteSetThenCleared() throws {
    let context = try Self.makeContext()
    let item = TripPackingItem(name: "Camera")
    context.insert(item)

    item.note = "keep batteries out"
    try context.save()
    #expect(item.note == "keep batteries out")

    item.note = nil
    try context.save()
    #expect(item.note == nil)
  }

  @Test("note via init")
  func noteViaInit() throws {
    let context = try Self.makeContext()
    let item = TripPackingItem(name: "Charger", note: "USB-C only")
    context.insert(item)
    try context.save()
    #expect(item.note == "USB-C only")
  }

  @Test("skip -> restore leaves note and subItems unchanged")
  func skipRestorePreservesContent() throws {
    let context = try Self.makeContext()
    let item = TripPackingItem(name: "Toys", note: "soft ones only")
    context.insert(item)
    item.subItems = ["bear", "blocks"]
    try context.save()

    item.state = .excluded
    try context.save()
    #expect(item.note == "soft ones only")
    #expect(item.subItems == ["bear", "blocks"])

    item.state = .unpacked
    try context.save()
    #expect(item.note == "soft ones only")
    #expect(item.subItems == ["bear", "blocks"])
  }

  private static func makeContext() throws -> ModelContext {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config]).mainContext
  }
}
