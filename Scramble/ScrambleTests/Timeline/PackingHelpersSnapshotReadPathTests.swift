import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Regression coverage for the V3 snapshot read path in `PackingListHelpers`.
///
/// The bug: V3 writes a `TripPackingItem`'s owner as `personSnapshotID` (the
/// `personSnapshot` computed bridge → a `TripPersonSnapshot` whose `personID`
/// is the owner `Person.id`) and a trip's roster as `participantSnapshots`.
/// The deprecated `TripPackingItem.person` relationship and `Trip.participants`
/// are intentionally left unwritten on every production path. The helpers must
/// therefore read the snapshot path, never `item.person` / `trip.participants`.
///
/// Every fixture below writes the owner via `personSnapshot:` only (the
/// deprecated `person:` arg is left nil) so a pass proves the snapshot path is
/// what the helpers actually traverse.
@Suite("PackingListHelpers snapshot read path (V3 regression)", .serialized)
@MainActor
struct PackingHelpersSnapshotReadPathTests {

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

  /// Bundles the container with its primary entities so callers can retain the
  /// container alongside its referents — SwiftData crashes if the container
  /// deallocates while a `ModelContext` is in use.
  private struct Seed {
    let container: ModelContainer
    let trip: Trip
    let person: Person
    let item: TripPackingItem
  }

  /// One participant snapshot, one packing item written via `personSnapshot:`
  /// only — the deprecated `person` relationship is left nil.
  private static func seed(state: PackingState) throws -> Seed {
    let container = try makeContainer()
    let context = container.mainContext
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    let person = Person(name: "Alice", colorKey: "blue")
    context.insert(person)
    let snapshot = TripPersonSnapshot(personID: person.id, name: person.name, trip: trip)
    context.insert(snapshot)
    trip.participantSnapshots = [snapshot]
    let item = TripPackingItem(
      trip: trip, name: "Socks", state: state, source: .rule, personSnapshot: snapshot)
    context.insert(item)
    try context.save()
    // The owner is carried only by the snapshot reference; the deprecated path
    // is unwritten exactly as on every production path.
    #expect(item.person == nil)
    return Seed(container: container, trip: trip, person: person, item: item)
  }

  @Test("itemsForPerson resolves the item via the snapshot, not item.person")
  func itemsForPersonReadsSnapshot() throws {
    let seed = try Self.seed(state: .unpacked)
    let items = PackingListHelpers.itemsForPerson(seed.trip, person: seed.person)
    #expect(items.map(\.id) == [seed.item.id])
    _ = seed.container
  }

  @Test("counts(for:in:) reflects the snapshot-owned item's state")
  func countsReadSnapshot() throws {
    let seed = try Self.seed(state: .packed)
    let counts = PackingListHelpers.counts(for: seed.person, in: seed.trip)
    #expect(counts.packed == 1)
    #expect(counts.toPack == 0)
    _ = seed.container
  }

  @Test("countsByPerson keys the snapshot-owned item under the owner Person.id")
  func countsByPersonReadsSnapshot() throws {
    let seed = try Self.seed(state: .unpacked)
    let byPerson = PackingListHelpers.countsByPerson(seed.trip)
    #expect(byPerson[seed.person.id]?.toPack == 1)
    _ = seed.container
  }

  @Test("phaseSubline counts the snapshot-owned item")
  func phaseSublineReadsSnapshot() throws {
    let seed = try Self.seed(state: .unpacked)
    #expect(PackingListHelpers.phaseSubline(seed.trip, mode: .pack) == "1 to pack")
    _ = seed.container
  }
}
