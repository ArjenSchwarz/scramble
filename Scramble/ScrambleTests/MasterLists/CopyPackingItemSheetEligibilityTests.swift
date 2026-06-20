import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Task 6 — drives `CopyPackingItemSheet.eligibleTargets(source:people:)`, the
/// static helper that resolves the eligible target people for the picker. It
/// excludes the source owner (2.1) and any person who already owns a same-name
/// item (2.3), using `MasterPersistence.normalizedName` as the SAME comparator
/// `copyPacking` applies. When every other person is ineligible the set is
/// empty, which drives the picker's 2.5 empty-state.
@Suite("CopyPackingItemSheet.eligibleTargets", .serialized)
@MainActor
struct CopyPackingItemSheetEligibilityTests {

  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }

  @Test("Source owner is excluded from the eligible set (2.1)")
  func ownerExcluded() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let owner = Person(name: "Owner", colorKey: "blue")
    let alice = Person(name: "Alice", colorKey: "cyan")
    let bob = Person(name: "Bob", colorKey: "orange")
    context.insert(owner)
    context.insert(alice)
    context.insert(bob)
    let source = MasterPackingItem(name: "Socks", person: owner, conditions: .always)
    context.insert(source)
    try context.save()

    let eligible = CopyPackingItemSheet.eligibleTargets(
      source: source,
      people: [owner, alice, bob]
    )

    let ids = Set(eligible.map(\.id))
    #expect(ids == [alice.id, bob.id])
    #expect(ids.contains(owner.id) == false)
  }

  @Test("A person already owning a same-name item is ineligible; trimmed + case-insensitive (2.3)")
  func sameNameOwnerIneligible() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let owner = Person(name: "Owner", colorKey: "blue")
    let alice = Person(name: "Alice", colorKey: "cyan")
    let bob = Person(name: "Bob", colorKey: "orange")
    context.insert(owner)
    context.insert(alice)
    context.insert(bob)
    // Alice already owns "socks" — source is "  Socks " → normalises equal.
    context.insert(MasterPackingItem(name: "socks", person: alice, conditions: .always))
    let source = MasterPackingItem(name: "  Socks ", person: owner, conditions: .always)
    context.insert(source)
    try context.save()

    let eligible = CopyPackingItemSheet.eligibleTargets(
      source: source,
      people: [owner, alice, bob]
    )

    let ids = Set(eligible.map(\.id))
    // Alice is dropped (same-name owner); Bob remains; owner is always excluded.
    #expect(ids == [bob.id])
    #expect(ids.contains(alice.id) == false)
  }

  @Test("When every other person is ineligible the eligible set is empty (drives 2.5)")
  func everyoneIneligibleYieldsEmpty() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let owner = Person(name: "Owner", colorKey: "blue")
    let alice = Person(name: "Alice", colorKey: "cyan")
    let bob = Person(name: "Bob", colorKey: "orange")
    context.insert(owner)
    context.insert(alice)
    context.insert(bob)
    context.insert(MasterPackingItem(name: "Socks", person: alice, conditions: .always))
    context.insert(MasterPackingItem(name: "SOCKS", person: bob, conditions: .always))
    let source = MasterPackingItem(name: "Socks", person: owner, conditions: .always)
    context.insert(source)
    try context.save()

    let eligible = CopyPackingItemSheet.eligibleTargets(
      source: source,
      people: [owner, alice, bob]
    )

    #expect(eligible.isEmpty)
  }
}
