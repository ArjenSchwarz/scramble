import Foundation
import SwiftData
import Testing

@testable import Scramble

@Suite("PackingListHelpers.counts", .serialized)
@MainActor
struct PackingCountsTests {

  // MARK: - Container helper

  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }

  // MARK: - Fixtures

  /// Bundles the container with its primary entities so callers can retain the
  /// container alongside its referents — SwiftData crashes if the container
  /// deallocates while a `ModelContext` is in use.
  private struct Seed {
    let container: ModelContainer
    let trip: Trip
    let person: Person
  }

  private static func seed(
    states: [PackingState],
    matches: [Bool]? = nil,
    pinned: [Bool]? = nil
  ) throws -> Seed {
    let container = try makeContainer()
    let context = container.mainContext
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    let person = Person(name: "Alice", colorKey: "blue")
    context.insert(person)
    let snapshot = TripPersonSnapshot(personID: person.id, name: person.name, trip: trip)
    context.insert(snapshot)
    trip.participantSnapshots = [snapshot]

    for (idx, state) in states.enumerated() {
      let item = TripPackingItem(
        trip: trip,
        name: "item-\(idx)",
        state: state,
        source: .rule,
        currentlyMatchesRules: matches?[idx] ?? true,
        pinnedByUser: pinned?[idx] ?? false,
        personSnapshot: snapshot
      )
      context.insert(item)
    }
    try context.save()
    return Seed(container: container, trip: trip, person: person)
  }

  // MARK: - Empty cases

  @Test("Person with zero items has all-zero counts")
  func zeroItems() throws {
    let seed = try Self.seed(states: [])
    let counts = PackingListHelpers.counts(for: seed.person, in: seed.trip)
    #expect(counts.toPack == 0)
    #expect(counts.packed == 0)
    #expect(counts.repacked == 0)
    #expect(counts.excluded == 0)
    _ = seed.container
  }

  @Test("Empty participants — counts for an unrelated Person are zero")
  func emptyParticipants() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    let person = Person(name: "Stranger", colorKey: "red")
    context.insert(person)
    try context.save()

    let counts = PackingListHelpers.counts(for: person, in: trip)
    #expect(counts.toPack == 0)
    #expect(counts.packed == 0)
    #expect(counts.repacked == 0)
    #expect(counts.excluded == 0)
  }

  // MARK: - All-state population

  @Test("All four states populated → counts split correctly")
  func allStatesPopulated() throws {
    let seed = try Self.seed(
      states: [.unpacked, .unpacked, .packed, .repacked, .repacked, .repacked, .excluded])
    let counts = PackingListHelpers.counts(for: seed.person, in: seed.trip)
    #expect(counts.toPack == 2)
    #expect(counts.packed == 1)
    #expect(counts.repacked == 3)
    #expect(counts.excluded == 1)
    _ = seed.container
  }

  @Test("Person with only excluded items")
  func onlyExcluded() throws {
    let seed = try Self.seed(states: [.excluded, .excluded, .excluded])
    let counts = PackingListHelpers.counts(for: seed.person, in: seed.trip)
    #expect(counts.toPack == 0)
    #expect(counts.packed == 0)
    #expect(counts.repacked == 0)
    #expect(counts.excluded == 3)
    _ = seed.container
  }

  // MARK: - Other-person isolation

  @Test("Items for other people are not counted")
  func otherPeopleIgnored() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    let alice = Person(name: "Alice", colorKey: "blue")
    let bob = Person(name: "Bob", colorKey: "green")
    context.insert(alice)
    context.insert(bob)
    let aliceSnapshot = TripPersonSnapshot(personID: alice.id, name: alice.name, trip: trip)
    let bobSnapshot = TripPersonSnapshot(personID: bob.id, name: bob.name, trip: trip)
    context.insert(aliceSnapshot)
    context.insert(bobSnapshot)
    trip.participantSnapshots = [aliceSnapshot, bobSnapshot]

    context.insert(
      TripPackingItem(
        trip: trip, name: "alice-thing", state: .packed, source: .rule,
        personSnapshot: aliceSnapshot))
    context.insert(
      TripPackingItem(
        trip: trip, name: "bob-thing", state: .packed, source: .rule, personSnapshot: bobSnapshot))
    context.insert(
      TripPackingItem(
        trip: trip, name: "bob-other", state: .unpacked, source: .rule,
        personSnapshot: bobSnapshot))
    try context.save()

    let counts = PackingListHelpers.counts(for: alice, in: trip)
    #expect(counts.toPack == 0)
    #expect(counts.packed == 1)
    #expect(counts.repacked == 0)
    #expect(counts.excluded == 0)
  }

  // MARK: - Items from other trips are not counted

  @Test("Items belonging to a different trip are excluded")
  func otherTripIgnored() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let tripA = Trip(name: "A", startDate: .now, endDate: .now)
    let tripB = Trip(name: "B", startDate: .now, endDate: .now)
    context.insert(tripA)
    context.insert(tripB)
    let person = Person(name: "Alice", colorKey: "blue")
    context.insert(person)
    let snapshotA = TripPersonSnapshot(personID: person.id, name: person.name, trip: tripA)
    let snapshotB = TripPersonSnapshot(personID: person.id, name: person.name, trip: tripB)
    context.insert(snapshotA)
    context.insert(snapshotB)
    tripA.participantSnapshots = [snapshotA]
    tripB.participantSnapshots = [snapshotB]

    context.insert(
      TripPackingItem(
        trip: tripA, name: "a", state: .packed, source: .rule, personSnapshot: snapshotA))
    context.insert(
      TripPackingItem(
        trip: tripB, name: "b", state: .packed, source: .rule, personSnapshot: snapshotB))
    try context.save()

    let countsA = PackingListHelpers.counts(for: person, in: tripA)
    #expect(countsA.packed == 1)
    let countsB = PackingListHelpers.counts(for: person, in: tripB)
    #expect(countsB.packed == 1)
  }

  // MARK: - countsByPerson matches per-person counts(for:in:)

  @Test("countsByPerson agrees with per-person counts(for:in:) across a multi-person trip")
  func countsByPersonMatchesPerPersonOverload() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    let alice = Person(name: "Alice", colorKey: "blue")
    let bob = Person(name: "Bob", colorKey: "green")
    let cara = Person(name: "Cara", colorKey: "purple")
    context.insert(alice)
    context.insert(bob)
    context.insert(cara)
    let aliceSnapshot = TripPersonSnapshot(personID: alice.id, name: alice.name, trip: trip)
    let bobSnapshot = TripPersonSnapshot(personID: bob.id, name: bob.name, trip: trip)
    let caraSnapshot = TripPersonSnapshot(personID: cara.id, name: cara.name, trip: trip)
    context.insert(aliceSnapshot)
    context.insert(bobSnapshot)
    context.insert(caraSnapshot)
    trip.participantSnapshots = [aliceSnapshot, bobSnapshot, caraSnapshot]

    // Alice: 2 unpacked, 1 packed.
    context.insert(
      TripPackingItem(trip: trip, name: "a1", state: .unpacked, personSnapshot: aliceSnapshot))
    context.insert(
      TripPackingItem(trip: trip, name: "a2", state: .unpacked, personSnapshot: aliceSnapshot))
    context.insert(
      TripPackingItem(trip: trip, name: "a3", state: .packed, personSnapshot: aliceSnapshot))
    // Bob: 1 packed, 2 repacked, 1 excluded.
    context.insert(
      TripPackingItem(trip: trip, name: "b1", state: .packed, personSnapshot: bobSnapshot))
    context.insert(
      TripPackingItem(trip: trip, name: "b2", state: .repacked, personSnapshot: bobSnapshot))
    context.insert(
      TripPackingItem(trip: trip, name: "b3", state: .repacked, personSnapshot: bobSnapshot))
    context.insert(
      TripPackingItem(trip: trip, name: "b4", state: .excluded, personSnapshot: bobSnapshot))
    // Cara: zero items — must still produce an all-zero entry.
    try context.save()

    let byPerson = PackingListHelpers.countsByPerson(trip)
    for person in [alice, bob, cara] {
      let expected = PackingListHelpers.counts(for: person, in: trip)
      let actual = byPerson[person.id]
      #expect(actual == expected, "Mismatch for \(person.name)")
    }
    #expect(byPerson.count == 3)
  }
}
