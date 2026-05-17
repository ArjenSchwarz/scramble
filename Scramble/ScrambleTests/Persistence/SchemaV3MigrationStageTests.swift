import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Phase 5 — `SchemaV3MigrationStage.backfillSnapshots(in:)` coverage.
///
/// The custom step rebuilds V3 person snapshots from the V2-shaped trip
/// roster (`Trip.participants`, `TripPackingItem.person`). The tests below
/// seed a V3 container with V2-shaped data — i.e., trips with `participants`
/// populated and packing items with `person` set, but no
/// `participantSnapshots` and no `personSnapshot` — then invoke the
/// backfill and assert the V3 fields are populated.
///
/// Operating against a V3 container (rather than a V2 → V3 migration round
/// trip) sidesteps the same SwiftData two-`@Model`-named-`TripTask`
/// constraint that drove `SchemaV2MigrationTests` to plan-shape coverage.
/// It still exercises the actual production code path: the custom stage's
/// `didMigrate` callback runs against a V3-shaped store immediately after
/// SwiftData applies the lightweight V2 → V3 schema diff.
@Suite("SchemaV3 Stage A — TripPersonSnapshot backfill", .serialized)
@MainActor
struct SchemaV3MigrationStageTests {

  // MARK: - Backfill semantics

  @Test("Backfill inserts a TripPersonSnapshot per person on every trip's roster")
  func insertsSnapshotPerRosterPerson() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let alice = Person(name: "Alice", colorKey: "cyan")
    let bob = Person(name: "Bob", colorKey: "green")
    context.insert(alice)
    context.insert(bob)
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    trip.participants = [alice, bob]
    try context.save()

    try SchemaV3MigrationStage.backfillSnapshots(in: context)
    try context.save()

    let snapshots = try context.fetch(FetchDescriptor<TripPersonSnapshot>())
    #expect(snapshots.count == 2)
    let personIDs = Set(snapshots.map(\.personID))
    #expect(personIDs == Set([alice.id, bob.id]))
    #expect(snapshots.allSatisfy { $0.isRosterMember })
  }

  @Test("Backfill populates Trip.participantSnapshots with the inserted snapshots")
  func populatesTripParticipantSnapshots() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let alice = Person(name: "Alice", colorKey: "cyan")
    context.insert(alice)
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    trip.participants = [alice]
    try context.save()

    try SchemaV3MigrationStage.backfillSnapshots(in: context)
    try context.save()

    let trips = try context.fetch(FetchDescriptor<Trip>())
    let stored = try #require(trips.first)
    let snapshots = stored.participantSnapshots ?? []
    #expect(snapshots.count == 1)
    #expect(snapshots.first?.personID == alice.id)
    #expect(snapshots.first?.name == "Alice")
    #expect(snapshots.first?.colourID == "cyan")
  }

  @Test("Backfill links TripPackingItem.personSnapshot to the matching trip snapshot")
  func linksTripPackingItemToSnapshot() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let alice = Person(name: "Alice", colorKey: "cyan")
    context.insert(alice)
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    trip.participants = [alice]
    let item = TripPackingItem(trip: trip, person: alice, name: "Toothbrush")
    context.insert(item)
    try context.save()

    try SchemaV3MigrationStage.backfillSnapshots(in: context)
    try context.save()

    let items = try context.fetch(FetchDescriptor<TripPackingItem>())
    let stored = try #require(items.first)
    let snapshot = try #require(stored.personSnapshot)
    #expect(snapshot.personID == alice.id)
    #expect(snapshot.trip?.id == trip.id)
  }

  @Test(
    "Backfill leaves deprecated V2 fields (Trip.participants, TripPackingItem.person) untouched")
  func deprecatedV2FieldsUntouched() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let alice = Person(name: "Alice", colorKey: "cyan")
    context.insert(alice)
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    trip.participants = [alice]
    let item = TripPackingItem(trip: trip, person: alice, name: "Toothbrush")
    context.insert(item)
    try context.save()

    try SchemaV3MigrationStage.backfillSnapshots(in: context)
    try context.save()

    let trips = try context.fetch(FetchDescriptor<Trip>())
    #expect(trips.first?.participants?.first?.id == alice.id)
    let items = try context.fetch(FetchDescriptor<TripPackingItem>())
    #expect(items.first?.person?.id == alice.id)
  }

  // MARK: - Idempotence

  @Test("Backfill on an already-migrated trip is a no-op (no duplicate snapshots)")
  func idempotentOnSecondRun() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let alice = Person(name: "Alice", colorKey: "cyan")
    context.insert(alice)
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    trip.participants = [alice]
    try context.save()

    try SchemaV3MigrationStage.backfillSnapshots(in: context)
    try context.save()
    try SchemaV3MigrationStage.backfillSnapshots(in: context)
    try context.save()

    let snapshots = try context.fetch(FetchDescriptor<TripPersonSnapshot>())
    #expect(snapshots.count == 1, "Second run must not insert a duplicate snapshot")
  }

  @Test("Backfill on a trip with snapshots already linked leaves packing-item links intact")
  func idempotentLinksPackingItems() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let alice = Person(name: "Alice", colorKey: "cyan")
    context.insert(alice)
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    trip.participants = [alice]
    let item = TripPackingItem(trip: trip, person: alice, name: "Toothbrush")
    context.insert(item)
    try context.save()

    try SchemaV3MigrationStage.backfillSnapshots(in: context)
    try context.save()
    let firstRunSnapshotID = try #require(
      try context.fetch(FetchDescriptor<TripPackingItem>()).first?.personSnapshot?.id
    )

    try SchemaV3MigrationStage.backfillSnapshots(in: context)
    try context.save()
    let secondRunSnapshotID = try #require(
      try context.fetch(FetchDescriptor<TripPackingItem>()).first?.personSnapshot?.id
    )
    #expect(firstRunSnapshotID == secondRunSnapshotID)
  }

  // MARK: - Empty / edge cases

  @Test("Backfill on a trip with no participants does nothing")
  func emptyRosterNoOp() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()

    try SchemaV3MigrationStage.backfillSnapshots(in: context)
    try context.save()

    let snapshots = try context.fetch(FetchDescriptor<TripPersonSnapshot>())
    #expect(snapshots.isEmpty)
  }

  @Test("Backfill on a packing item with nil person leaves personSnapshot nil")
  func packingItemWithoutPersonStaysUnsnapshotted() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    let item = TripPackingItem(trip: trip, person: nil, name: "Toothbrush")
    context.insert(item)
    try context.save()

    try SchemaV3MigrationStage.backfillSnapshots(in: context)
    try context.save()

    let items = try context.fetch(FetchDescriptor<TripPackingItem>())
    #expect(items.first?.personSnapshot == nil)
  }

  // MARK: - Helpers

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
