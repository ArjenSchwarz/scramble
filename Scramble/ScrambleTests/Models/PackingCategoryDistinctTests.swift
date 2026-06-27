import Foundation
import SwiftData
import Testing

@testable import Scramble

/// `PackingCategory.distinctCategories(globals:tripsLocal:)` gathers the
/// suggestion vocabulary from both SwiftData containers — `MasterPackingItem`
/// (globals) and `TripPackingItem` (tripsLocal) — deduped by normalized key,
/// each key rendered with its canonical spelling (`displayLabel`) and ordered
/// by `keyOrder`. A participant device (no masters in globals) yields only the
/// trip-visible categories (Req 2.5). Uses two separate in-memory containers to
/// model the dual-container split.
@Suite("PackingCategory.distinctCategories", .serialized)
@MainActor
struct PackingCategoryDistinctTests {

  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }

  @Test("Merges both containers, dedupes by normalized key, orders by keyOrder")
  func mergesAndDedupesOrdered() throws {
    let globalsContainer = try Self.makeContainer()
    let tripsLocalContainer = try Self.makeContainer()
    let globals = globalsContainer.mainContext
    let tripsLocal = tripsLocalContainer.mainContext

    globals.insert(MasterPackingItem(name: "Jacket", category: "Clothes"))
    globals.insert(MasterPackingItem(name: "Soap", category: "toiletries"))
    try globals.save()

    // "clothes" is a case variant of the master's "Clothes" → one suggestion.
    tripsLocal.insert(TripPackingItem(name: "Shirt", category: "clothes"))
    tripsLocal.insert(TripPackingItem(name: "Plasters", category: "First Aid"))
    try tripsLocal.save()

    let result = PackingCategory.distinctCategories(globals: globals, tripsLocal: tripsLocal)

    // Keys ordered by Unicode scalar: clothes < first aid < toiletries.
    // Canonical spelling per key: "Clothes" wins over "clothes" (uppercase
    // sorts first under rawOrder); "First Aid" and "toiletries" are sole spellings.
    #expect(result == ["Clothes", "First Aid", "toiletries"])
  }

  @Test("Canonical spelling is the rawOrder-first variant across both containers")
  func canonicalSpellingAcrossContainers() throws {
    let globalsContainer = try Self.makeContainer()
    let tripsLocalContainer = try Self.makeContainer()
    let globals = globalsContainer.mainContext
    let tripsLocal = tripsLocalContainer.mainContext

    // Lowercase master, uppercase trip — both normalize to "clothes".
    globals.insert(MasterPackingItem(name: "Jacket", category: "clothes"))
    try globals.save()
    tripsLocal.insert(TripPackingItem(name: "Shirt", category: "Clothes"))
    try tripsLocal.save()

    let result = PackingCategory.distinctCategories(globals: globals, tripsLocal: tripsLocal)

    #expect(result == ["Clothes"])
  }

  @Test("Participant device (empty globals) yields trip-visible categories only (2.5)")
  func participantSeesTripCategoriesOnly() throws {
    let globalsContainer = try Self.makeContainer()  // no masters — participant
    let tripsLocalContainer = try Self.makeContainer()
    let globals = globalsContainer.mainContext
    let tripsLocal = tripsLocalContainer.mainContext

    tripsLocal.insert(TripPackingItem(name: "Shirt", category: "Clothes"))
    tripsLocal.insert(TripPackingItem(name: "Soap", category: "Toiletries"))
    try tripsLocal.save()

    let result = PackingCategory.distinctCategories(globals: globals, tripsLocal: tripsLocal)

    #expect(result == ["Clothes", "Toiletries"])
  }

  @Test("Uncategorised items (nil / blank category) contribute no suggestion")
  func uncategorisedContributesNothing() throws {
    let globalsContainer = try Self.makeContainer()
    let tripsLocalContainer = try Self.makeContainer()
    let globals = globalsContainer.mainContext
    let tripsLocal = tripsLocalContainer.mainContext

    globals.insert(MasterPackingItem(name: "Jacket", category: "Clothes"))
    globals.insert(MasterPackingItem(name: "Passport", category: nil))
    try globals.save()
    tripsLocal.insert(TripPackingItem(name: "Wallet", category: "   "))
    try tripsLocal.save()

    let result = PackingCategory.distinctCategories(globals: globals, tripsLocal: tripsLocal)

    #expect(result == ["Clothes"])
  }

  @Test("No categories anywhere yields an empty suggestion list")
  func emptyWhenNoCategories() throws {
    let globalsContainer = try Self.makeContainer()
    let tripsLocalContainer = try Self.makeContainer()
    let globals = globalsContainer.mainContext
    let tripsLocal = tripsLocalContainer.mainContext

    globals.insert(MasterPackingItem(name: "Passport", category: nil))
    tripsLocal.insert(TripPackingItem(name: "Wallet", category: nil))
    try globals.save()
    try tripsLocal.save()

    let result = PackingCategory.distinctCategories(globals: globals, tripsLocal: tripsLocal)

    #expect(result.isEmpty)
  }
}
