import Foundation
import SwiftData
import Testing

@testable import Scramble

@Suite("WhyResolver (TripPackingItem)", .serialized)
@MainActor
struct WhyResolverPackingTests {

  // MARK: - Container helper

  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV2.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }

  private static func rainyAttributes() -> TripAttributes {
    var a = TripAttributes()
    a.toggle(.weather, value: "rain")
    return a
  }

  private static func sunnyAttributes() -> TripAttributes {
    var a = TripAttributes()
    a.toggle(.weather, value: "sun")
    return a
  }

  // MARK: - .manual

  @Test("manual packing item → .manual reason")
  func manualReason() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "T", startDate: .now, endDate: .now, attributes: Self.rainyAttributes())
    context.insert(trip)
    let person = Person(name: "Alice", colorKey: "blue")
    context.insert(person)
    let item = TripPackingItem(
      trip: trip,
      person: person,
      masterItemID: nil,
      name: "Sunscreen",
      state: .unpacked,
      source: .manual
    )
    context.insert(item)
    try context.save()

    #expect(WhyResolver.reason(for: item, context: context) == .manual)
    _ = container
  }

  // MARK: - .ruleMasterDeleted

  @Test("rule packing item with nil masterItemID → .ruleMasterDeleted")
  func ruleMasterDeletedNilID() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "T", startDate: .now, endDate: .now, attributes: Self.rainyAttributes())
    context.insert(trip)
    let person = Person(name: "Alice", colorKey: "blue")
    context.insert(person)
    let item = TripPackingItem(
      trip: trip,
      person: person,
      masterItemID: nil,
      name: "Orphan",
      state: .unpacked,
      source: .rule
    )
    context.insert(item)
    try context.save()

    #expect(WhyResolver.reason(for: item, context: context) == .ruleMasterDeleted)
    _ = container
  }

  @Test("rule packing item whose masterItemID resolves to nothing → .ruleMasterDeleted")
  func ruleMasterDeletedNotFound() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "T", startDate: .now, endDate: .now, attributes: Self.rainyAttributes())
    context.insert(trip)
    let person = Person(name: "Alice", colorKey: "blue")
    context.insert(person)
    let danglingID = UUID()
    let item = TripPackingItem(
      trip: trip,
      person: person,
      masterItemID: danglingID,
      name: "Orphan",
      state: .unpacked,
      source: .rule
    )
    context.insert(item)
    try context.save()

    #expect(WhyResolver.reason(for: item, context: context) == .ruleMasterDeleted)
    _ = container
  }

  @Test("rule packing item whose master was deleted after save → .ruleMasterDeleted")
  func ruleMasterDeletedAfterCreation() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let person = Person(name: "Alice", colorKey: "blue")
    context.insert(person)
    let master = MasterPackingItem(
      name: "Rain jacket",
      person: person,
      conditions: .match(attribute: .weather, anyOf: ["rain"])
    )
    context.insert(master)
    let trip = Trip(name: "T", startDate: .now, endDate: .now, attributes: Self.rainyAttributes())
    context.insert(trip)
    let item = TripPackingItem(
      trip: trip,
      person: person,
      masterItemID: master.id,
      name: "Rain jacket",
      state: .unpacked,
      source: .rule
    )
    context.insert(item)
    try context.save()

    context.delete(master)
    try context.save()

    #expect(WhyResolver.reason(for: item, context: context) == .ruleMasterDeleted)
    _ = container
  }

  // MARK: - .ruleMatched

  @Test(
    "rule packing item with matching master + matching trip attrs → .ruleMatched with conditionsText"
  )
  func ruleMatched() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let person = Person(name: "Alice", colorKey: "blue")
    context.insert(person)
    let master = MasterPackingItem(
      name: "Rain jacket",
      person: person,
      conditions: .match(attribute: .weather, anyOf: ["rain"])
    )
    context.insert(master)
    let trip = Trip(name: "T", startDate: .now, endDate: .now, attributes: Self.rainyAttributes())
    context.insert(trip)
    let item = TripPackingItem(
      trip: trip,
      person: person,
      masterItemID: master.id,
      name: "Rain jacket",
      state: .unpacked,
      source: .rule
    )
    context.insert(item)
    try context.save()

    let reason = WhyResolver.reason(for: item, context: context)
    #expect(reason == .ruleMatched(conditionsText: "Rain"))
    _ = container
  }

  // MARK: - .ruleNoLongerMatches

  @Test(
    "rule packing item with master present but conditions no longer match trip → .ruleNoLongerMatches"
  )
  func ruleNoLongerMatches() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let person = Person(name: "Alice", colorKey: "blue")
    context.insert(person)
    let master = MasterPackingItem(
      name: "Rain jacket",
      person: person,
      conditions: .match(attribute: .weather, anyOf: ["rain"])
    )
    context.insert(master)
    let trip = Trip(name: "T", startDate: .now, endDate: .now, attributes: Self.sunnyAttributes())
    context.insert(trip)
    let item = TripPackingItem(
      trip: trip,
      person: person,
      masterItemID: master.id,
      name: "Rain jacket",
      state: .unpacked,
      source: .rule
    )
    context.insert(item)
    try context.save()

    #expect(WhyResolver.reason(for: item, context: context) == .ruleNoLongerMatches)
    _ = container
  }

  // MARK: - Regression: resolver re-reads current trip attributes on each call

  @Test("Resolver reflects new trip attributes after mutation (no stale snapshot)")
  func reflectsMutatedAttributes() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let person = Person(name: "Alice", colorKey: "blue")
    context.insert(person)
    let master = MasterPackingItem(
      name: "Rain jacket",
      person: person,
      conditions: .match(attribute: .weather, anyOf: ["rain"])
    )
    context.insert(master)
    let trip = Trip(name: "T", startDate: .now, endDate: .now, attributes: Self.rainyAttributes())
    context.insert(trip)
    let item = TripPackingItem(
      trip: trip,
      person: person,
      masterItemID: master.id,
      name: "Rain jacket",
      state: .unpacked,
      source: .rule
    )
    context.insert(item)
    try context.save()

    #expect(WhyResolver.reason(for: item, context: context) == .ruleMatched(conditionsText: "Rain"))

    trip.attributes = Self.sunnyAttributes()
    try context.save()

    #expect(WhyResolver.reason(for: item, context: context) == .ruleNoLongerMatches)
    _ = container
  }
}
