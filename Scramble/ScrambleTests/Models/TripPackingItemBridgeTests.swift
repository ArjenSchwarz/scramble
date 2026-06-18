import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Post-fix coverage for the `TripPackingItem.personSnapshot` computed
/// bridge over the `personSnapshotID` value reference (Phase 5 Decision 14).
/// The bridge resolves via the owning trip's `participantSnapshots`
/// in-memory and falls back to a `modelContext` fetch when the trip-side
/// array isn't wired (e.g. a freshly decoded CloudKit record, or a snapshot
/// reachable only via the one-way `TripPersonSnapshot.trip` back-link). This
/// suite locks in both paths plus the nil / dangling cases.
@Suite("TripPackingItem.personSnapshot bridge", .serialized)
@MainActor
struct TripPackingItemBridgeTests {

  @Test("Fast path: resolves via trip.participantSnapshots")
  func resolvesViaParticipantSnapshots() throws {
    let context = try Self.makeContext()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    let snapshot = TripPersonSnapshot(personID: UUID(), name: "Alice", trip: trip)
    context.insert(snapshot)
    trip.participantSnapshots = [snapshot]
    let item = TripPackingItem(trip: trip, name: "Socks", personSnapshot: snapshot)
    context.insert(item)
    try context.save()

    #expect(item.personSnapshotID == snapshot.id)
    #expect(item.personSnapshot?.id == snapshot.id)
  }

  @Test("Fallback path: resolves via modelContext fetch when the trip side isn't wired")
  func resolvesViaContextFetchWhenTripNil() throws {
    let context = try Self.makeContext()
    let snapshot = TripPersonSnapshot(personID: UUID(), name: "Bob")
    context.insert(snapshot)
    // No trip relationship and no participantSnapshots, so the in-memory
    // fast path misses; the bridge must fall back to a fetch by id from
    // the item's own context. Mirrors a freshly decoded CloudKit record.
    let item = TripPackingItem(name: "Hat", personSnapshot: snapshot)
    context.insert(item)
    try context.save()

    #expect(item.trip == nil)
    #expect(item.personSnapshot?.id == snapshot.id)
  }

  @Test("Nil personSnapshotID resolves to nil")
  func nilIDResolvesNil() throws {
    let context = try Self.makeContext()
    let item = TripPackingItem(name: "Towel")
    context.insert(item)
    try context.save()

    #expect(item.personSnapshotID == nil)
    #expect(item.personSnapshot == nil)
  }

  @Test("Dangling personSnapshotID (no matching snapshot) resolves to nil")
  func danglingIDResolvesNil() throws {
    let context = try Self.makeContext()
    let item = TripPackingItem(name: "Boots")
    item.personSnapshotID = UUID()  // points at nothing
    context.insert(item)
    try context.save()

    #expect(item.personSnapshot == nil)
  }

  @Test("Setter stores the snapshot's id and clears on nil")
  func setterStoresID() throws {
    let context = try Self.makeContext()
    let snapshot = TripPersonSnapshot(personID: UUID(), name: "Cara")
    context.insert(snapshot)
    let item = TripPackingItem(name: "Map")
    context.insert(item)

    item.personSnapshot = snapshot
    #expect(item.personSnapshotID == snapshot.id)
    item.personSnapshot = nil
    #expect(item.personSnapshotID == nil)
  }

  private static func makeContext() throws -> ModelContext {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config]).mainContext
  }
}
