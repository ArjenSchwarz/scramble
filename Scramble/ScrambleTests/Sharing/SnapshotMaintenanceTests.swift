import CloudKit
import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Phase 5 / Phase 5.1 — snapshot maintenance coverage (Reqs
/// [2.3](../../../specs/phase-5-cloudkit-sharing/requirements.md#2.3),
/// [2.4](../../../specs/phase-5-cloudkit-sharing/requirements.md#2.4),
/// Phase 5.1 [2.3](../../../specs/phase-5.1-wire-trip-crud-tripslocal/requirements.md#2.3),
/// [6.1](../../../specs/phase-5.1-wire-trip-crud-tripslocal/requirements.md#6.1)–
/// [6.4](../../../specs/phase-5.1-wire-trip-crud-tripslocal/requirements.md#6.4)).
///
/// Three cleanup triggers + `Person → TripPersonSnapshot` propagation, all
/// owner-only. Phase 5.1 made every routine mutate-only — the tests drive
/// the routine and then call `LocalWriteHook.commit(_:)`, asserting both
/// the behavioural outcome (snapshots updated / removed) and the dirty /
/// deleted notifier signals the hook emits.
@Suite("SnapshotMaintenance", .serialized)
@MainActor
struct SnapshotMaintenanceTests {

  // MARK: - Person edit propagation

  @Test("Person edit propagates name/colour/initial to every TripPersonSnapshot for that person")
  func personEditPropagatesAcrossTrips() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let hook = LocalWriteHook(notifier: RecordingNotifier())

    let person = Person(name: "Alice", colorKey: "cyan")
    context.insert(person)
    let trip1 = Trip(name: "Trip1", startDate: .now, endDate: .now)
    let trip2 = Trip(name: "Trip2", startDate: .now, endDate: .now)
    context.insert(trip1)
    context.insert(trip2)
    let snap1 = Self.makeSnapshot(person: person, trip: trip1, in: context)
    let snap2 = Self.makeSnapshot(person: person, trip: trip2, in: context)
    try context.save()

    person.name = "Alicia"
    person.colorKey = "violet"

    try SnapshotMaintenance.propagatePersonEdit(
      person, in: context, ownerIdentity: { _ in .currentUser })
    try hook.commit(context)

    #expect(snap1.name == "Alicia")
    #expect(snap1.colourID == "violet")
    #expect(snap2.name == "Alicia")
    #expect(snap2.colourID == "violet")
  }

  @Test(
    "Person edit propagation: the post-routine LocalWriteHook commit marks each affected snapshot dirty"
  )
  func personEditFlagsSnapshotsDirty() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let notifier = RecordingNotifier()
    let hook = LocalWriteHook(notifier: notifier)

    let person = Person(name: "Alice", colorKey: "cyan")
    context.insert(person)
    let trip = Trip(name: "Trip", startDate: .now, endDate: .now)
    context.insert(trip)
    let zoneState = TripZoneState(
      tripID: trip.id,
      zoneOwnerName: CKCurrentUserDefaultName,
      zoneScope: "private"
    )
    context.insert(zoneState)
    let snapshot = Self.makeSnapshot(person: person, trip: trip, in: context)
    try context.save()

    person.name = "Alicia"
    notifier.calls.removeAll()

    try SnapshotMaintenance.propagatePersonEdit(
      person, in: context, ownerIdentity: { _ in .currentUser })
    try hook.commit(context)

    let flags = PendingUploadFlags.decode(zoneState.pendingUploadFlags)
    #expect(flags.dirtyRecordNames.contains(snapshot.id.uuidString))

    let snapshotIDs = notifier.calls.flatMap { $0.savedRecordIDs.map(\.recordName) }
    #expect(snapshotIDs.contains(snapshot.id.uuidString))
  }

  @Test("Person edit propagation is a no-op for trips not owned by the current user")
  func personEditSkipsParticipantOwnedTrips() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let hook = LocalWriteHook(notifier: RecordingNotifier())

    let person = Person(name: "Alice", colorKey: "cyan")
    context.insert(person)
    let trip = Trip(name: "Shared", startDate: .now, endDate: .now)
    context.insert(trip)
    let snapshot = Self.makeSnapshot(person: person, trip: trip, in: context)
    try context.save()

    person.name = "Alicia"

    try SnapshotMaintenance.propagatePersonEdit(
      person,
      in: context,
      ownerIdentity: { _ in .otherUser(displayName: "Friend") }
    )
    try hook.commit(context)

    #expect(snapshot.name == "Alice", "Participant-owned trip's snapshot must not be touched")
  }

  // MARK: - Roster removal cleanup

  @Test(
    "Roster removal: snapshot with no referring TripPackingItem is deleted in same transaction")
  func rosterRemovalDeletesUnreferencedSnapshot() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let notifier = RecordingNotifier()
    let hook = LocalWriteHook(notifier: notifier)

    let person = Person(name: "Alice", colorKey: "cyan")
    context.insert(person)
    let trip = Trip(name: "Trip", startDate: .now, endDate: .now)
    context.insert(trip)
    let snapshot = Self.makeSnapshot(person: person, trip: trip, in: context)
    try context.save()
    let snapshotID = snapshot.id

    try SnapshotMaintenance.handleRosterRemoval(
      tripID: trip.id,
      personID: person.id,
      in: context
    )
    try hook.commit(context)

    let snapshots = try context.fetch(FetchDescriptor<TripPersonSnapshot>())
    #expect(snapshots.isEmpty, "Unreferenced snapshot must be deleted")

    let deletedNames = notifier.calls.flatMap { $0.deletedRecordIDs.map(\.recordName) }
    #expect(deletedNames.contains(snapshotID.uuidString))
  }

  @Test("Roster removal: snapshot referenced by packing items stays but is flagged non-roster")
  func rosterRemovalKeepsReferencedSnapshotAsNonRoster() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let notifier = RecordingNotifier()
    let hook = LocalWriteHook(notifier: notifier)

    let person = Person(name: "Alice", colorKey: "cyan")
    context.insert(person)
    let trip = Trip(name: "Trip", startDate: .now, endDate: .now)
    context.insert(trip)
    let snapshot = Self.makeSnapshot(person: person, trip: trip, in: context)
    let item = TripPackingItem(trip: trip, name: "Socks", personSnapshot: snapshot)
    context.insert(item)
    try context.save()
    notifier.calls.removeAll()

    try SnapshotMaintenance.handleRosterRemoval(
      tripID: trip.id,
      personID: person.id,
      in: context
    )
    try hook.commit(context)

    let snapshots = try context.fetch(FetchDescriptor<TripPersonSnapshot>())
    #expect(snapshots.count == 1)
    #expect(snapshots.first?.isRosterMember == false)

    let dirtyNames = notifier.calls.flatMap { $0.savedRecordIDs.map(\.recordName) }
    #expect(dirtyNames.contains(snapshot.id.uuidString))
  }

  // MARK: - Packing item deletion cleanup

  @Test(
    """
    Packing item delete: orphan-snapshot cleanup + caller's context.delete(item) \
    + single LocalWriteHook commit deletes the non-roster snapshot and the item in one transaction
    """
  )
  func packingItemDeleteRemovesNonRosterSnapshotWithLastItem() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let notifier = RecordingNotifier()
    let hook = LocalWriteHook(notifier: notifier)

    let person = Person(name: "Alice", colorKey: "cyan")
    context.insert(person)
    let trip = Trip(name: "Trip", startDate: .now, endDate: .now)
    context.insert(trip)
    let snapshot = Self.makeSnapshot(person: person, trip: trip, in: context)
    snapshot.isRosterMember = false
    let item = TripPackingItem(trip: trip, name: "Socks", personSnapshot: snapshot)
    context.insert(item)
    try context.save()
    notifier.calls.removeAll()
    let snapshotID = snapshot.id
    let itemID = item.id

    // Caller invariant: mutate-only routine runs, then delete the item,
    // then commit once via the hook so the user action is one transaction.
    try SnapshotMaintenance.handlePackingItemDeletion(item, in: context)
    context.delete(item)
    try hook.commit(context)

    let snapshots = try context.fetch(FetchDescriptor<TripPersonSnapshot>())
    #expect(snapshots.isEmpty, "Non-roster snapshot with no remaining items must be deleted")

    // Both deletions go through the same hook commit and show up in one
    // notifier call for the trip's zone.
    let deletedNames = notifier.calls.flatMap { $0.deletedRecordIDs.map(\.recordName) }
    #expect(deletedNames.contains(snapshotID.uuidString))
    #expect(deletedNames.contains(itemID.uuidString))
  }

  @Test(
    "Packing item delete: snapshot is roster member -> snapshot is preserved")
  func packingItemDeleteKeepsRosterSnapshot() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let hook = LocalWriteHook(notifier: RecordingNotifier())

    let person = Person(name: "Alice", colorKey: "cyan")
    context.insert(person)
    let trip = Trip(name: "Trip", startDate: .now, endDate: .now)
    context.insert(trip)
    let snapshot = Self.makeSnapshot(person: person, trip: trip, in: context)
    snapshot.isRosterMember = true
    let item = TripPackingItem(trip: trip, name: "Socks", personSnapshot: snapshot)
    context.insert(item)
    try context.save()

    try SnapshotMaintenance.handlePackingItemDeletion(item, in: context)
    try hook.commit(context)

    let snapshots = try context.fetch(FetchDescriptor<TripPersonSnapshot>())
    #expect(snapshots.count == 1, "Roster-member snapshot must survive item deletion")
  }

  @Test(
    "Packing item delete: more items still reference the snapshot -> snapshot preserved")
  func packingItemDeleteKeepsSnapshotWithRemainingReferences() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let hook = LocalWriteHook(notifier: RecordingNotifier())

    let person = Person(name: "Alice", colorKey: "cyan")
    context.insert(person)
    let trip = Trip(name: "Trip", startDate: .now, endDate: .now)
    context.insert(trip)
    let snapshot = Self.makeSnapshot(person: person, trip: trip, in: context)
    snapshot.isRosterMember = false
    let item1 = TripPackingItem(trip: trip, name: "Socks", personSnapshot: snapshot)
    let item2 = TripPackingItem(trip: trip, name: "Hat", personSnapshot: snapshot)
    context.insert(item1)
    context.insert(item2)
    try context.save()

    try SnapshotMaintenance.handlePackingItemDeletion(item1, in: context)
    try hook.commit(context)

    let snapshots = try context.fetch(FetchDescriptor<TripPersonSnapshot>())
    #expect(snapshots.count == 1, "Other items still reference the snapshot")
    _ = item2
  }

  // MARK: - Periodic sweep

  @Test("Sweep deletes non-roster snapshots with no remaining packing-item references")
  func sweepDeletesOrphanedSnapshots() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let notifier = RecordingNotifier()
    let hook = LocalWriteHook(notifier: notifier)

    let person = Person(name: "Alice", colorKey: "cyan")
    context.insert(person)
    let trip = Trip(name: "Trip", startDate: .now, endDate: .now)
    context.insert(trip)
    let orphan = Self.makeSnapshot(person: person, trip: trip, in: context)
    orphan.isRosterMember = false
    let active = Self.makeSnapshot(person: person, trip: trip, in: context)
    active.isRosterMember = true
    try context.save()
    notifier.calls.removeAll()
    let orphanID = orphan.id

    try SnapshotMaintenance.sweep(in: context)
    try hook.commit(context)

    let snapshots = try context.fetch(FetchDescriptor<TripPersonSnapshot>())
    #expect(snapshots.count == 1, "Only the orphan should be removed")
    #expect(snapshots.first?.id == active.id)

    let deletedNames = notifier.calls.flatMap { $0.deletedRecordIDs.map(\.recordName) }
    #expect(deletedNames.contains(orphanID.uuidString))
  }

  @Test("Sweep is a no-op when there are no orphaned snapshots")
  func sweepLeavesActiveSnapshotsAlone() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let hook = LocalWriteHook(notifier: RecordingNotifier())

    let person = Person(name: "Alice", colorKey: "cyan")
    context.insert(person)
    let trip = Trip(name: "Trip", startDate: .now, endDate: .now)
    context.insert(trip)
    _ = Self.makeSnapshot(person: person, trip: trip, in: context)
    try context.save()

    try SnapshotMaintenance.sweep(in: context)
    try hook.commit(context)

    let snapshots = try context.fetch(FetchDescriptor<TripPersonSnapshot>())
    #expect(snapshots.count == 1)
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

  @discardableResult
  private static func makeSnapshot(
    person: Person,
    trip: Trip,
    in context: ModelContext
  ) -> TripPersonSnapshot {
    let snapshot = TripPersonSnapshot(
      personID: person.id,
      name: person.name,
      colourID: person.colorKey,
      initialSource: "name",
      isRosterMember: true,
      trip: trip
    )
    context.insert(snapshot)
    return snapshot
  }
}
