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

  // The three branches share name fragments ("Alice", "Bob"), so a bare
  // `contains(name)` check would still pass if two branches were transposed.
  // Each assertion below pins a DISTINGUISHING phrase from the source string so
  // swapping the copied-only / copied-with-skips / all-skipped arms fails a test.
  // Source phrasing (MasterPersistence.copyToastMessage):
  //   copied-only:        "Copied to \(copied)."
  //   copied-with-skips:  "Copied to \(copied). Skipped \(skipped) — already had it."
  //   all-skipped:        "Everyone already had this item — skipped \(skipped)."
  private static let skippedClause = "already had it"
  private static let copiedClause = "Copied to"
  private static let allSkippedLead = "Everyone already had this item"

  @Test("Copied-only: copied-clause present, skipped-clause absent")
  func copiedOnly() {
    let message = MasterPersistence.copyToastMessage(
      copiedNames: ["Alice", "Bob"],
      skippedNames: []
    )
    #expect(message.contains("Alice"))
    #expect(message.contains("Bob"))
    // Distinguishes from copied-with-skips: it copies, it does NOT skip anyone.
    #expect(message.contains(Self.copiedClause))
    #expect(message.contains(Self.skippedClause) == false)
    #expect(message.contains("Skipped") == false)
    #expect(message.contains(Self.allSkippedLead) == false)
  }

  @Test("Copied-with-skips: BOTH the copied-clause and the skipped-clause present")
  func copiedWithSkips() {
    let message = MasterPersistence.copyToastMessage(
      copiedNames: ["Alice"],
      skippedNames: ["Bob"]
    )
    #expect(message.contains("Alice"))
    #expect(message.contains("Bob"))
    // Distinguishes from BOTH other branches: copies AND notes a skip.
    #expect(message.contains(Self.copiedClause))
    #expect(message.contains(Self.skippedClause))
    // Not the all-skipped branch, which would lead with "Everyone…".
    #expect(message.contains(Self.allSkippedLead) == false)
  }

  @Test("All-skipped: 'already had it' wording, no 'Copied to' clause")
  func allSkipped() {
    let message = MasterPersistence.copyToastMessage(
      copiedNames: [],
      skippedNames: ["Alice", "Bob"]
    )
    #expect(message.contains("Alice"))
    #expect(message.contains("Bob"))
    // Distinguishes from the two copied branches: nobody received a copy, so the
    // "Copied to" clause must NOT leak through. The all-skipped string leads with
    // "Everyone already had this item — skipped …" and uses the verb "skipped";
    // it does NOT carry the copied-with-skips-only trailing "— already had it"
    // clause, so asserting that clause is ABSENT here guards against transposing
    // these two skip-bearing branches.
    #expect(message.contains(Self.allSkippedLead))
    #expect(message.contains("skipped"))
    #expect(message.contains(Self.skippedClause) == false)
    #expect(message.contains(Self.copiedClause) == false)
  }

  // Exercises the formatNames joiner indirectly through copyToastMessage (the
  // helper is private). Single name → bare name; two → "X and Y"; three+ →
  // oxford "A, B, and C". Asserted against the copied-only branch so the joined
  // string is the whole list of names.
  @Test("formatNames join: 1 name renders the bare name")
  func formatNamesSingle() {
    let message = MasterPersistence.copyToastMessage(
      copiedNames: ["Alice"],
      skippedNames: []
    )
    #expect(message.contains("Copied to Alice."))
    // No join words for a single name.
    #expect(message.contains(" and ") == false)
    #expect(message.contains(",") == false)
  }

  @Test("formatNames join: 2 names use the 'X and Y' join, no comma")
  func formatNamesPair() {
    let message = MasterPersistence.copyToastMessage(
      copiedNames: ["Alice", "Bob"],
      skippedNames: []
    )
    #expect(message.contains("Copied to Alice and Bob."))
    // Two names join with " and " and NO comma (distinguishes from 3+).
    #expect(message.contains(", and ") == false)
  }

  @Test("formatNames join: 3+ names use the oxford 'A, B, and C' join")
  func formatNamesOxford() {
    let message = MasterPersistence.copyToastMessage(
      copiedNames: ["Alice", "Bob", "Carol"],
      skippedNames: []
    )
    #expect(message.contains("Copied to Alice, Bob, and Carol."))
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

  @Test("Skips a same-name owner whose item was inserted but NOT saved (3.5 race)")
  func skipsUnsavedSameNameInsert() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let owner = Person(name: "Owner", colorKey: "blue")
    let alice = Person(name: "Alice", colorKey: "cyan")
    context.insert(owner)
    context.insert(alice)
    let source = MasterPackingItem(name: "Socks", person: owner, conditions: .always)
    context.insert(source)
    try context.save()

    // The load-bearing race (Req 3.5): a same-name item lands for the target
    // AFTER the picker opened but BEFORE the copy runs — and crucially before
    // any save(). The skip re-check reads `Person.masterPackingItems`, so it
    // must surface this pending in-context insert. We deliberately do NOT call
    // context.save() here.
    let aliceUnsaved = MasterPackingItem(name: "Socks", person: alice, conditions: .always)
    context.insert(aliceUnsaved)
    #expect(context.hasChanges == true)

    let result = MasterPersistence.copyPacking(
      source: source,
      toPersonIDs: [alice.id],
      in: context
    )

    // If this fails — i.e. the unsaved insert is invisible through the
    // relationship and the helper creates a duplicate — that is a real defect,
    // NOT a test to relax.
    #expect(result.createdCount == 0)
    #expect(result.copiedNames.isEmpty)
    #expect(result.skippedNames == ["Alice"])
    // Only the one pending insert exists for Alice; no copy was added.
    #expect((alice.masterPackingItems ?? []).count == 1)
  }

  @Test("Unresolvable person id is neither copied nor skipped (off-roster contract)")
  func unresolvableIDIsNeitherCopiedNorSkipped() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let owner = Person(name: "Owner", colorKey: "blue")
    context.insert(owner)
    let source = MasterPackingItem(name: "Socks", person: owner, conditions: .always)
    context.insert(source)
    try context.save()

    // A random id resolves to no Person in the store.
    let ghost = UUID()
    let result = MasterPersistence.copyPacking(
      source: source,
      toPersonIDs: [ghost],
      in: context
    )

    // An unresolved id is dropped silently: not a copy, and NOT a skip (a skip
    // means "a real person already had it"). Pin that asymmetry.
    #expect(result.createdCount == 0)
    #expect(result.copiedNames.isEmpty)
    #expect(result.skippedNames.isEmpty)
  }

  @Test("Pure mechanism: does NOT guard an empty/whitespace source name (Decision 6)")
  func doesNotGuardEmptySourceName() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let owner = Person(name: "Owner", colorKey: "blue")
    let alice = Person(name: "Alice", colorKey: "cyan")
    context.insert(owner)
    context.insert(alice)
    // Source name trims to "" — the UI source-eligibility gate (Decision 6 /
    // Req 1.3) blocks this upstream; the helper itself does NOT, so it copies an
    // empty-named item. This test documents the helper's actual behaviour, not a
    // guard we want it to grow.
    let source = MasterPackingItem(name: "   ", person: owner, conditions: .always)
    context.insert(source)
    try context.save()

    let result = MasterPersistence.copyPacking(
      source: source,
      toPersonIDs: [alice.id],
      in: context
    )

    // The helper is a pure mechanism: it creates a copy with the trimmed
    // (empty) name and reports Alice as copied.
    #expect(result.createdCount == 1)
    #expect(result.copiedNames == ["Alice"])
    #expect(result.skippedNames.isEmpty)
    let copy = try #require(
      try context.fetch(FetchDescriptor<MasterPackingItem>())
        .first { $0.person?.id == alice.id }
    )
    #expect(copy.name == "")
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

// MARK: - copyOutcome branch selection (pure orchestration)

/// Drives `MasterPackingList.copyOutcome`, the pure branch-selection extracted
/// from `performCopy`. These tests assert the control flow ONLY — which closures
/// run and the returned `CopyOutcome` — using recording flags, so they need no
/// SwiftData. The toast wording and rollback side effects stay in `performCopy`.
@Suite("MasterPackingList.copyOutcome")
@MainActor
struct CopyOutcomeTests {

  struct CopyError: Error {}

  @Test("createdCount 0 → .nothingToCopy; neither save nor runEngine runs (3.7)")
  func nothingToCopySkipsSaveAndEngine() {
    var didSave = false
    var didRun = false
    let outcome = MasterPackingList.copyOutcome(
      createdCount: 0,
      save: { didSave = true },
      runEngine: { didRun = true }
    )
    #expect(outcome == .nothingToCopy)
    #expect(didSave == false)
    #expect(didRun == false)
  }

  @Test("save throws → .saveFailed; runEngine is NOT invoked (3.6)")
  func saveFailureSkipsEngine() {
    var didRun = false
    let outcome = MasterPackingList.copyOutcome(
      createdCount: 2,
      save: { throw CopyError() },
      runEngine: { didRun = true }
    )
    #expect(outcome == .saveFailed)
    #expect(didRun == false)
  }

  @Test("save ok + runEngine throws → .copied(deferred: true) (4.2)")
  func engineFailureIsDeferred() {
    var didSave = false
    let outcome = MasterPackingList.copyOutcome(
      createdCount: 2,
      save: { didSave = true },
      runEngine: { throw CopyError() }
    )
    #expect(outcome == .copied(deferred: true))
    #expect(didSave == true)
  }

  @Test("save ok + runEngine ok → .copied(deferred: false)")
  func cleanCopyIsNotDeferred() {
    var didSave = false
    var didRun = false
    let outcome = MasterPackingList.copyOutcome(
      createdCount: 2,
      save: { didSave = true },
      runEngine: { didRun = true }
    )
    #expect(outcome == .copied(deferred: false))
    #expect(didSave == true)
    #expect(didRun == true)
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
    // items exist (no recompute ran). (A notifier assertion was removed here: an
    // unwired LocalWriteHook can never record a call, so it was vacuous —
    // copyPacking touches globals, not a trip zone, and never goes through the
    // hook; only the engine run would, and the engine never runs on rollback.)
    let packs = try context.fetch(FetchDescriptor<TripPackingItem>())
    #expect(packs.isEmpty)
  }
}
