import CloudKit
import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Phase 5 — owner-side trip deletion order
/// (Req [1.4](../../../specs/phase-5-cloudkit-sharing/requirements.md#1.4),
/// design § "Trip-deletion ordering"). The reverse-cascade order avoids
/// orphaned snapshots and the SwiftData cascade-traversal panic that
/// drove `Trip.participantSnapshots` to a one-way relationship
/// (persistence note).
@Suite("TripDeletion", .serialized)
@MainActor
struct TripDeletionTests {

  @Test("Owner-side deletion removes packing items, tasks, snapshots, trip, and zone state")
  func deletionCascadesEverythingLocally() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack")
    let snapshot = TripPersonSnapshot(
      personID: UUID(),
      name: "Alice",
      colourID: "cyan",
      initialSource: "name",
      isRosterMember: true,
      trip: trip
    )
    let item = TripPackingItem(trip: trip, name: "Socks", personSnapshot: snapshot)
    let zoneState = TripZoneState(
      tripID: trip.id,
      zoneOwnerName: CKCurrentUserDefaultName,
      zoneScope: "private"
    )
    context.insert(trip)
    context.insert(task)
    context.insert(snapshot)
    context.insert(item)
    context.insert(zoneState)
    try context.save()

    let zoneDeleter = RecordingZoneDeleter()
    try TripDeletion.delete(tripID: trip.id, in: context, zoneDeleter: zoneDeleter)

    #expect(try context.fetch(FetchDescriptor<TripPackingItem>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<TripTask>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<TripPersonSnapshot>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<Trip>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<TripZoneState>()).isEmpty)
  }

  @Test("Owner-side deletion calls the zone deleter with the trip's zone ID")
  func deletionAsksDriverToDeleteZone() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let zoneState = TripZoneState(
      tripID: trip.id,
      zoneOwnerName: CKCurrentUserDefaultName,
      zoneScope: "private"
    )
    context.insert(trip)
    context.insert(zoneState)
    try context.save()

    let zoneDeleter = RecordingZoneDeleter()
    try TripDeletion.delete(tripID: trip.id, in: context, zoneDeleter: zoneDeleter)

    let expectedZone = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    #expect(zoneDeleter.deletedZones == [expectedZone])
  }

  @Test("Participant-side deletion (no zone deleter) still cleans up local rows")
  func participantSideCleanupWithoutZoneDeletion() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack")
    let zoneState = TripZoneState(
      tripID: trip.id,
      zoneOwnerName: "remote-owner",
      zoneScope: "shared"
    )
    context.insert(trip)
    context.insert(task)
    context.insert(zoneState)
    try context.save()

    try TripDeletion.delete(tripID: trip.id, in: context, zoneDeleter: nil)

    #expect(try context.fetch(FetchDescriptor<Trip>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<TripTask>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<TripZoneState>()).isEmpty)
  }

  @Test("Deletion of a trip with no zone state still removes the trip")
  func deletionWithoutZoneStateStillRemovesTrip() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()

    try TripDeletion.delete(tripID: trip.id, in: context, zoneDeleter: nil)
    #expect(try context.fetch(FetchDescriptor<Trip>()).isEmpty)
  }

  @Test("Deletion order: packing items first, then tasks, then snapshots, then trip, then zone")
  func deletionFollowsReverseCascadeOrder() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack")
    let snapshot = TripPersonSnapshot(
      personID: UUID(),
      name: "Alice",
      colourID: "cyan",
      initialSource: "name",
      isRosterMember: true,
      trip: trip
    )
    let item = TripPackingItem(trip: trip, name: "Socks", personSnapshot: snapshot)
    let zoneState = TripZoneState(
      tripID: trip.id,
      zoneOwnerName: CKCurrentUserDefaultName,
      zoneScope: "private"
    )
    context.insert(trip)
    context.insert(task)
    context.insert(snapshot)
    context.insert(item)
    context.insert(zoneState)
    try context.save()

    let zoneDeleter = RecordingZoneDeleter()
    try TripDeletion.delete(tripID: trip.id, in: context, zoneDeleter: zoneDeleter)

    // No orphans: every entity tied to the trip is gone.
    let allItems = try context.fetch(FetchDescriptor<TripPackingItem>())
    let allTasks = try context.fetch(FetchDescriptor<TripTask>())
    let allSnapshots = try context.fetch(FetchDescriptor<TripPersonSnapshot>())
    #expect(allItems.isEmpty && allTasks.isEmpty && allSnapshots.isEmpty)
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

@MainActor
final class RecordingZoneDeleter: TripZoneDeleter {
  private(set) var deletedZones: [CKRecordZone.ID] = []

  func deleteZone(_ zoneID: CKRecordZone.ID) {
    deletedZones.append(zoneID)
  }
}
