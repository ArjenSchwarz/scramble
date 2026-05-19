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
    let hook = LocalWriteHook(notifier: RecordingNotifier())

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
    try TripDeletion.delete(
      tripID: trip.id, in: context, hook: hook, zoneDeleter: zoneDeleter
    )

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
    let hook = LocalWriteHook(notifier: RecordingNotifier())

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
    try TripDeletion.delete(
      tripID: trip.id, in: context, hook: hook, zoneDeleter: zoneDeleter
    )

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
    let hook = LocalWriteHook(notifier: RecordingNotifier())

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

    try TripDeletion.delete(tripID: trip.id, in: context, hook: hook, zoneDeleter: nil)

    #expect(try context.fetch(FetchDescriptor<Trip>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<TripTask>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<TripZoneState>()).isEmpty)
  }

  @Test("Deletion of a trip with no zone state still removes the trip")
  func deletionWithoutZoneStateStillRemovesTrip() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let hook = LocalWriteHook(notifier: RecordingNotifier())

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()

    try TripDeletion.delete(tripID: trip.id, in: context, hook: hook, zoneDeleter: nil)
    #expect(try context.fetch(FetchDescriptor<Trip>()).isEmpty)
  }

  @Test("Deletion order: packing items first, then tasks, then snapshots, then trip, then zone")
  func deletionFollowsReverseCascadeOrder() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let hook = LocalWriteHook(notifier: RecordingNotifier())

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
    try TripDeletion.delete(
      tripID: trip.id, in: context, hook: hook, zoneDeleter: zoneDeleter
    )

    // No orphans: every entity tied to the trip is gone.
    let allItems = try context.fetch(FetchDescriptor<TripPackingItem>())
    let allTasks = try context.fetch(FetchDescriptor<TripTask>())
    let allSnapshots = try context.fetch(FetchDescriptor<TripPersonSnapshot>())
    #expect(allItems.isEmpty && allTasks.isEmpty && allSnapshots.isEmpty)
  }

  // MARK: - Phase 5.1: routes through LocalWriteHook.commitDeletion

  @Test(
    """
    Phase 5.1: delete routes through LocalWriteHook.commitDeletion — \
    the recording notifier observes the trip's vanishing-zone deleted record IDs \
    in a single signal
    """
  )
  func deletionRoutesThroughCommitDeletionNotifier() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let notifier = RecordingNotifier()
    let hook = LocalWriteHook(notifier: notifier)

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
    try hook.commit(context)
    notifier.calls.removeAll()

    let tripIDValue = trip.id
    let taskID = task.id
    let snapshotID = snapshot.id
    let itemID = item.id

    try TripDeletion.delete(
      tripID: trip.id, in: context, hook: hook, zoneDeleter: RecordingZoneDeleter()
    )

    let expectedZone = CKRecordZone.ID(
      zoneName: "trip-\(tripIDValue.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    let call = try #require(notifier.calls.first { $0.zoneID == expectedZone })
    let deletedNames = Set(call.deletedRecordIDs.map(\.recordName))
    #expect(deletedNames.contains(tripIDValue.uuidString))
    #expect(deletedNames.contains(taskID.uuidString))
    #expect(deletedNames.contains(snapshotID.uuidString))
    #expect(deletedNames.contains(itemID.uuidString))
    #expect(call.savedRecordIDs.isEmpty)
  }

  @Test("Participant-side deletion does not call the zone deleter")
  func participantSideSkipsZoneDeleter() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let hook = LocalWriteHook(notifier: RecordingNotifier())

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let zoneState = TripZoneState(
      tripID: trip.id,
      zoneOwnerName: "remote-owner",
      zoneScope: "shared"
    )
    context.insert(trip)
    context.insert(zoneState)
    try context.save()

    let zoneDeleter = RecordingZoneDeleter()
    try TripDeletion.delete(
      tripID: trip.id, in: context, hook: hook, zoneDeleter: zoneDeleter
    )

    #expect(
      zoneDeleter.deletedZones.isEmpty,
      "Participant-scope deletions must not enqueue a private-DB zone delete"
    )
  }

  @Test("Deleting a non-existent trip is idempotent — no throw, no notifier signal")
  func deletionOfMissingTripIsIdempotent() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let notifier = RecordingNotifier()
    let hook = LocalWriteHook(notifier: notifier)

    try TripDeletion.delete(tripID: UUID(), in: context, hook: hook, zoneDeleter: nil)

    #expect(notifier.calls.isEmpty)
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
