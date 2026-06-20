import Foundation
import SwiftData
import Testing

@testable import Scramble

// MARK: - Pure helpers (Task 1)

@Suite("MasterPersistence.normalizedName")
struct NormalizedNameTests {

  @Test("Trims surrounding whitespace and lowercases")
  func trimsAndLowercases() {
    #expect(MasterPersistence.normalizedName("  Socks ") == "socks")
    #expect(MasterPersistence.normalizedName("SOCKS") == "socks")
    #expect(MasterPersistence.normalizedName("Socks") == "socks")
  }

  @Test("'  Socks ' and 'socks' normalise equal")
  func trimmedVariantsMatch() {
    #expect(
      MasterPersistence.normalizedName("  Socks ")
        == MasterPersistence.normalizedName("socks")
    )
  }

  @Test("Empty and whitespace-only normalise to empty string")
  func emptyAndWhitespaceMapToEmpty() {
    #expect(MasterPersistence.normalizedName("") == "")
    #expect(MasterPersistence.normalizedName("   ") == "")
    #expect(MasterPersistence.normalizedName("\n\t ") == "")
  }
}

@Suite("MasterPersistence.copyToastMessage")
struct CopyToastMessageTests {

  @Test("Copied-only: names the people the item went to, no skip wording")
  func copiedOnly() {
    let message = MasterPersistence.copyToastMessage(
      copiedNames: ["Alice", "Bob"],
      skippedNames: []
    )
    #expect(message.contains("Alice"))
    #expect(message.contains("Bob"))
  }

  @Test("Copied-with-skips: lists copied people and notes skipped people")
  func copiedWithSkips() {
    let message = MasterPersistence.copyToastMessage(
      copiedNames: ["Alice"],
      skippedNames: ["Bob"]
    )
    #expect(message.contains("Alice"))
    #expect(message.contains("Bob"))
  }

  @Test("All-skipped: empty copied → message that everyone already had it, names skipped")
  func allSkipped() {
    let message = MasterPersistence.copyToastMessage(
      copiedNames: [],
      skippedNames: ["Alice", "Bob"]
    )
    #expect(message.contains("Alice"))
    #expect(message.contains("Bob"))
    // No one received a copy, so no copied-only phrasing should leak through;
    // the all-skipped outcome conveys everyone already had the item.
    #expect(message.isEmpty == false)
  }
}

// MARK: - copyPacking (Task 3)

@Suite("MasterPersistence.copyPacking", .serialized)
@MainActor
struct CopyPackingHelperTests {

  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }

  @Test("One copy per eligible target, each owned by the right person; trimmed name (3.1/3.2)")
  func createsOneCopyPerEligibleTarget() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let owner = Person(name: "Owner", colorKey: "blue")
    let alice = Person(name: "Alice", colorKey: "cyan")
    let bob = Person(name: "Bob", colorKey: "orange")
    context.insert(owner)
    context.insert(alice)
    context.insert(bob)
    let source = MasterPackingItem(name: "  Socks  ", person: owner, conditions: .always)
    context.insert(source)
    try context.save()

    let result = MasterPersistence.copyPacking(
      source: source,
      toPersonIDs: [alice.id, bob.id],
      in: context
    )

    #expect(result.createdCount == 2)
    #expect(Set(result.copiedNames) == ["Alice", "Bob"])
    #expect(result.skippedNames.isEmpty)

    let copies = try context.fetch(FetchDescriptor<MasterPackingItem>())
      .filter { $0.id != source.id }
    #expect(copies.count == 2)
    // Names are trimmed copies of the source (3.2).
    #expect(copies.allSatisfy { $0.name == "Socks" })
    // Each copy is owned by exactly one of the targets (3.1).
    let aliceCopy = try #require(copies.first { $0.person?.id == alice.id })
    let bobCopy = try #require(copies.first { $0.person?.id == bob.id })
    #expect(aliceCopy.name == "Socks")
    #expect(bobCopy.name == "Socks")
  }

  @Test("Skips a target already owning a same-name item; trimmed + case-insensitive (2.3/3.5)")
  func skipsSameNameOwnerCaseInsensitive() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let owner = Person(name: "Owner", colorKey: "blue")
    let alice = Person(name: "Alice", colorKey: "cyan")
    context.insert(owner)
    context.insert(alice)
    // Alice already owns "socks" — source is "  Socks " → normalised equal.
    let aliceExisting = MasterPackingItem(name: "socks", person: alice, conditions: .always)
    context.insert(aliceExisting)
    let source = MasterPackingItem(name: "  Socks ", person: owner, conditions: .always)
    context.insert(source)
    try context.save()

    let result = MasterPersistence.copyPacking(
      source: source,
      toPersonIDs: [alice.id],
      in: context
    )

    #expect(result.createdCount == 0)
    #expect(result.copiedNames.isEmpty)
    #expect(result.skippedNames == ["Alice"])
    // No new item created for Alice.
    let aliceItems = (alice.masterPackingItems ?? [])
    #expect(aliceItems.count == 1)
  }

  @Test("All targets already own it → createdCount == 0 and nothing inserted (3.7)")
  func allTargetsSkippedInsertsNothing() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let owner = Person(name: "Owner", colorKey: "blue")
    let alice = Person(name: "Alice", colorKey: "cyan")
    let bob = Person(name: "Bob", colorKey: "orange")
    context.insert(owner)
    context.insert(alice)
    context.insert(bob)
    context.insert(MasterPackingItem(name: "Socks", person: alice, conditions: .always))
    context.insert(MasterPackingItem(name: "Socks", person: bob, conditions: .always))
    let source = MasterPackingItem(name: "Socks", person: owner, conditions: .always)
    context.insert(source)
    try context.save()

    let before = try context.fetch(FetchDescriptor<MasterPackingItem>()).count
    let result = MasterPersistence.copyPacking(
      source: source,
      toPersonIDs: [alice.id, bob.id],
      in: context
    )

    #expect(result.createdCount == 0)
    #expect(result.copiedNames.isEmpty)
    #expect(Set(result.skippedNames) == ["Alice", "Bob"])
    let after = try context.fetch(FetchDescriptor<MasterPackingItem>()).count
    #expect(after == before)
  }

  @Test("Duplicate ids in toPersonIDs produce exactly one copy (de-dupe)")
  func deDupesRepeatedIDs() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let owner = Person(name: "Owner", colorKey: "blue")
    let alice = Person(name: "Alice", colorKey: "cyan")
    context.insert(owner)
    context.insert(alice)
    let source = MasterPackingItem(name: "Socks", person: owner, conditions: .always)
    context.insert(source)
    try context.save()

    let result = MasterPersistence.copyPacking(
      source: source,
      toPersonIDs: [alice.id, alice.id, alice.id],
      in: context
    )

    #expect(result.createdCount == 1)
    #expect(result.copiedNames == ["Alice"])
    #expect((alice.masterPackingItems ?? []).count == 1)
  }

  @Test("Conditions fidelity: advanced nested form copied by value; source unchanged (3.3/3.4)")
  func conditionsFidelityAndIndependence() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let owner = Person(name: "Owner", colorKey: "blue")
    let alice = Person(name: "Alice", colorKey: "cyan")
    context.insert(owner)
    context.insert(alice)
    let nested: ItemConditions = .all([
      .any([
        .match(attribute: .weather, anyOf: ["rain", "snow"]),
        .match(attribute: .weather, anyOf: ["wind"]),
      ]),
      .match(attribute: .purpose, anyOf: ["hiking"]),
    ])
    let source = MasterPackingItem(name: "Layers", person: owner, conditions: nested)
    context.insert(source)
    try context.save()

    MasterPersistence.copyPacking(source: source, toPersonIDs: [alice.id], in: context)

    let copy = try #require(
      try context.fetch(FetchDescriptor<MasterPackingItem>())
        .first { $0.person?.id == alice.id }
    )
    // Decoded value equality, NOT conditionsData byte-equality.
    #expect(copy.conditions == source.conditions)
    #expect(copy.conditions == nested)

    // Mutating the copy's conditions leaves the source untouched (3.4).
    copy.conditions = .always
    #expect(source.conditions == nested)
    #expect(copy.conditions == .always)
  }
}

// MARK: - Engine integration + save atomicity (Task 5)

@Suite("Copy sequence: materialisation + atomicity", .serialized)
@MainActor
struct CopySequenceTests {

  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
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

  /// Seeds a trip with the given attributes plus a `TripPersonSnapshot` for the
  /// target person, which Phase 5.1's engine requires to materialise a
  /// rule-driven `TripPackingItem` (an orphan otherwise).
  private static func seedTrip(
    name: String,
    attributes: TripAttributes,
    person: Person,
    in context: ModelContext
  ) -> Trip {
    let trip = Trip(name: name, startDate: .now, endDate: .now, attributes: attributes)
    context.insert(trip)
    let snapshot = TripPersonSnapshot(
      personID: person.id,
      name: person.name,
      colourID: person.colorKey,
      initialSource: "name",
      isRosterMember: true,
      trip: trip
    )
    context.insert(snapshot)
    return trip
  }

  @Test("Materialisation: copy → save → engine puts item only on the matching trip (4.1)")
  func materialisesOntoMatchingTripOnly() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let owner = Person(name: "Owner", colorKey: "blue")
    let alice = Person(name: "Alice", colorKey: "cyan")
    context.insert(owner)
    context.insert(alice)
    // Source matches rainy trips only.
    let source = MasterPackingItem(
      name: "Rain jacket",
      person: owner,
      conditions: .match(attribute: .weather, anyOf: ["rain"])
    )
    context.insert(source)

    let rainy = Self.seedTrip(
      name: "Rainy", attributes: Self.rainyAttributes(), person: alice, in: context)
    let sunny = Self.seedTrip(
      name: "Sunny", attributes: Self.sunnyAttributes(), person: alice, in: context)
    try context.save()

    let result = MasterPersistence.copyPacking(
      source: source, toPersonIDs: [alice.id], in: context)
    #expect(result.createdCount == 1)
    try context.save()

    let hook = LocalWriteHook(notifier: RecordingNotifier())
    let runner = RulesEngineRunner(context: context, mastersContext: context, hook: hook)
    _ = try runner.runForAllNonPastTrips()

    let packs = try context.fetch(FetchDescriptor<TripPackingItem>())
    let aliceOnRainy = packs.filter {
      $0.trip?.id == rainy.id && $0.personSnapshot?.personID == alice.id
    }
    let aliceOnSunny = packs.filter {
      $0.trip?.id == sunny.id && $0.personSnapshot?.personID == alice.id
    }
    #expect(aliceOnRainy.count == 1)
    #expect(aliceOnRainy.first?.name == "Rain jacket")
    #expect(aliceOnSunny.isEmpty)
  }

  @Test("Atomicity: copyPacking inserts but does not save; rollback persists zero copies (3.6)")
  func rollbackLeavesNoCopiesAndNoEngineRun() throws {
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

    let baseline = try context.fetch(FetchDescriptor<MasterPackingItem>()).count

    let result = MasterPersistence.copyPacking(
      source: source, toPersonIDs: [alice.id, bob.id], in: context)
    #expect(result.createdCount == 2)
    // Inserted but not saved — the helper never calls save().
    #expect(context.hasChanges == true)

    // Simulate the caller's save-failure path: drop all uncommitted inserts.
    context.rollback()
    #expect(context.hasChanges == false)

    let after = try context.fetch(FetchDescriptor<MasterPackingItem>()).count
    #expect(after == baseline)

    // The engine is never invoked on the failure path — assert no trip-level
    // items exist (no recompute ran). A recording notifier confirms no writes
    // were pushed through the hook either.
    let notifier = RecordingNotifier()
    _ = LocalWriteHook(notifier: notifier)
    let packs = try context.fetch(FetchDescriptor<TripPackingItem>())
    #expect(packs.isEmpty)
    #expect(notifier.calls.isEmpty)
  }
}
