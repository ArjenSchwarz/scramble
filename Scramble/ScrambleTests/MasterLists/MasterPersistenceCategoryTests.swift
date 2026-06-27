import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Category carry-through for the three `MasterPersistence` write paths
/// (`createPacking`, `applyPacking`, `copyPacking`). Each path must persist the
/// category and apply `PackingCategory.storageValue` normalization on store
/// (trim + internal-whitespace collapse; empty/whitespace ⇒ nil). The
/// same-name dedup key in `copyPacking` stays name-only — category does not
/// participate in dedup (Decision 6 / design touch-point note).
@Suite("MasterPersistence category carry-through", .serialized)
@MainActor
struct MasterPersistenceCategoryTests {

  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }

  private static func draft(
    name: String = "Rain jacket",
    personID: UUID?,
    category: String?
  ) -> MasterPackingDraft {
    MasterPackingDraft(name: name, personID: personID, conditions: .always, category: category)
  }

  // MARK: - createPacking

  @Test("createPacking persists a normalized category (trim + internal collapse)")
  func createPersistsNormalizedCategory() throws {
    let context = try Self.makeContainer().mainContext
    let owner = Person(name: "Owner", colorKey: "blue")
    context.insert(owner)
    try context.save()

    let item = MasterPersistence.createPacking(
      from: Self.draft(personID: owner.id, category: "  First   Aid  "),
      in: context
    )

    #expect(item.category == "First Aid")
  }

  @Test("createPacking stores nil for an empty/whitespace category")
  func createStoresNilForBlankCategory() throws {
    let context = try Self.makeContainer().mainContext
    let owner = Person(name: "Owner", colorKey: "blue")
    context.insert(owner)
    try context.save()

    let blank = MasterPersistence.createPacking(
      from: Self.draft(personID: owner.id, category: "   \t "),
      in: context
    )
    let none = MasterPersistence.createPacking(
      from: Self.draft(personID: owner.id, category: nil),
      in: context
    )

    #expect(blank.category == nil)
    #expect(none.category == nil)
  }

  @Test("createPacking preserves case and diacritics in the stored category")
  func createPreservesCaseAndDiacritics() throws {
    let context = try Self.makeContainer().mainContext
    let owner = Person(name: "Owner", colorKey: "blue")
    context.insert(owner)
    try context.save()

    let item = MasterPersistence.createPacking(
      from: Self.draft(personID: owner.id, category: "  Café WORDS "),
      in: context
    )

    #expect(item.category == "Café WORDS")
  }

  // MARK: - applyPacking

  @Test("applyPacking writes a normalized category onto an existing item")
  func applyWritesNormalizedCategory() throws {
    let context = try Self.makeContainer().mainContext
    let owner = Person(name: "Owner", colorKey: "blue")
    context.insert(owner)
    let item = MasterPackingItem(name: "Rain jacket", person: owner, category: "Old")
    context.insert(item)
    try context.save()

    MasterPersistence.applyPacking(
      Self.draft(personID: owner.id, category: "  New   Cat "),
      to: item,
      in: context
    )

    #expect(item.category == "New Cat")
  }

  @Test("applyPacking clears the category when the draft is empty/whitespace")
  func applyClearsCategoryOnBlank() throws {
    let context = try Self.makeContainer().mainContext
    let owner = Person(name: "Owner", colorKey: "blue")
    context.insert(owner)
    let item = MasterPackingItem(name: "Rain jacket", person: owner, category: "Clothes")
    context.insert(item)
    try context.save()

    MasterPersistence.applyPacking(
      Self.draft(personID: owner.id, category: "   "),
      to: item,
      in: context
    )

    #expect(item.category == nil)
  }

  // MARK: - copyPacking

  @Test("copyPacking carries the source's normalized category onto each copy")
  func copyCarriesNormalizedCategory() throws {
    let context = try Self.makeContainer().mainContext
    let owner = Person(name: "Owner", colorKey: "blue")
    let alice = Person(name: "Alice", colorKey: "cyan")
    let bob = Person(name: "Bob", colorKey: "orange")
    context.insert(owner)
    context.insert(alice)
    context.insert(bob)
    // Set a non-normalized category directly on the source (bypassing the
    // editor) to prove copyPacking applies storageValue on store.
    let source = MasterPackingItem(name: "Socks", person: owner)
    source.category = "  Clothes   Stuff "
    context.insert(source)
    try context.save()

    let result = MasterPersistence.copyPacking(
      source: source,
      toPersonIDs: [alice.id, bob.id],
      in: context
    )

    #expect(result.createdCount == 2)
    let copies = try context.fetch(FetchDescriptor<MasterPackingItem>())
      .filter { $0.id != source.id }
    #expect(copies.count == 2)
    #expect(copies.allSatisfy { $0.category == "Clothes Stuff" })
  }

  @Test("copyPacking carries a nil category as nil")
  func copyCarriesNilCategory() throws {
    let context = try Self.makeContainer().mainContext
    let owner = Person(name: "Owner", colorKey: "blue")
    let alice = Person(name: "Alice", colorKey: "cyan")
    context.insert(owner)
    context.insert(alice)
    let source = MasterPackingItem(name: "Socks", person: owner, category: nil)
    context.insert(source)
    try context.save()

    MasterPersistence.copyPacking(source: source, toPersonIDs: [alice.id], in: context)

    let copy = try #require(
      try context.fetch(FetchDescriptor<MasterPackingItem>())
        .first { $0.person?.id == alice.id }
    )
    #expect(copy.category == nil)
  }

  @Test("copyPacking dedup stays name-only — a differing category does not bypass the skip")
  func copyDedupIsNameOnlyRegardlessOfCategory() throws {
    let context = try Self.makeContainer().mainContext
    let owner = Person(name: "Owner", colorKey: "blue")
    let alice = Person(name: "Alice", colorKey: "cyan")
    context.insert(owner)
    context.insert(alice)
    // Alice already owns a same-NAME item but with a different category.
    context.insert(MasterPackingItem(name: "Socks", person: alice, category: "Footwear"))
    let source = MasterPackingItem(name: "Socks", person: owner, category: "Clothes")
    context.insert(source)
    try context.save()

    let result = MasterPersistence.copyPacking(
      source: source,
      toPersonIDs: [alice.id],
      in: context
    )

    // Skipped on name alone; category never participates in dedup.
    #expect(result.createdCount == 0)
    #expect(result.skippedNames == ["Alice"])
    #expect((alice.masterPackingItems ?? []).count == 1)
  }
}
