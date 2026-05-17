import CloudKit
import Foundation
import SwiftData
import Testing

@testable import Scramble

@Suite("LocalWriteHook", .serialized)
@MainActor
struct LocalWriteHookTests {

  // MARK: - Dirty bits

  @Test("Inserting a Trip flips its own dirty bit in TripZoneState.pendingUploadFlags")
  func insertTripMarksDirty() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let notifier = RecordingNotifier()
    let hook = LocalWriteHook(notifier: notifier)

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    try hook.commit(context)

    let state = try #require(try context.fetch(FetchDescriptor<TripZoneState>()).first)
    let flags = PendingUploadFlags.decode(state.pendingUploadFlags)
    #expect(flags.dirtyRecordNames.contains(trip.id.uuidString))
    #expect(flags.deletedRecordNames.isEmpty)
  }

  @Test("Editing a TripTask marks the task's record name dirty in its trip's zone state")
  func changeTaskMarksDirty() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let hook = LocalWriteHook(notifier: RecordingNotifier())

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack")
    context.insert(trip)
    context.insert(task)
    try hook.commit(context)

    // Now change the task and recommit. The task's name appears in dirty
    // again on this round even though it was dirty before.
    task.name = "Pack v2"
    try hook.commit(context)

    let state = try #require(try context.fetch(FetchDescriptor<TripZoneState>()).first)
    let flags = PendingUploadFlags.decode(state.pendingUploadFlags)
    #expect(flags.dirtyRecordNames.contains(task.id.uuidString))
  }

  @Test("Deleting a TripPackingItem marks its record as deleted, removes any prior dirty bit")
  func deleteItemMarksDeletedAndClearsDirty() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let hook = LocalWriteHook(notifier: RecordingNotifier())

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let item = TripPackingItem(trip: trip, name: "Towel")
    context.insert(trip)
    context.insert(item)
    try hook.commit(context)

    context.delete(item)
    try hook.commit(context)

    let state = try #require(try context.fetch(FetchDescriptor<TripZoneState>()).first)
    let flags = PendingUploadFlags.decode(state.pendingUploadFlags)
    #expect(flags.deletedRecordNames.contains(item.id.uuidString))
    #expect(!flags.dirtyRecordNames.contains(item.id.uuidString))
  }

  // MARK: - Save semantics

  @Test("commit calls context.save once per invocation (no orphan unsaved changes)")
  func savesOnce() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let hook = LocalWriteHook(notifier: RecordingNotifier())

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    #expect(context.hasChanges)
    try hook.commit(context)
    #expect(!context.hasChanges, "After commit, the context should have no pending changes")
  }

  // MARK: - Notifier integration

  @Test("Notifier is called with the correct record IDs and zone")
  func notifierReceivesRecordIDs() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let notifier = RecordingNotifier()
    let hook = LocalWriteHook(notifier: notifier)

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack")
    context.insert(trip)
    context.insert(task)
    try hook.commit(context)

    #expect(notifier.calls.count == 1)
    let call = try #require(notifier.calls.first)
    #expect(call.zoneID.zoneName == "trip-\(trip.id.uuidString)")
    let recordNames = Set(call.savedRecordIDs.map(\.recordName))
    #expect(recordNames.contains(trip.id.uuidString))
    #expect(recordNames.contains(task.id.uuidString))
  }

  @Test("Empty commit (no pending changes) is a no-op — no notifier call, no zone state row")
  func emptyCommitIsNoOp() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let notifier = RecordingNotifier()
    let hook = LocalWriteHook(notifier: notifier)

    try hook.commit(context)
    #expect(notifier.calls.isEmpty)
    #expect(try context.fetch(FetchDescriptor<TripZoneState>()).isEmpty)
  }

  // MARK: - commitDeletion mixed-zone partition (Phase 5.1)

  @Test(
    """
    commitDeletion: delete in vanishing zone Z1 + edit in surviving zone Z2 — \
    Z1 records produce notifier-deleted signals with no flag write; Z2 \
    pendingUploadFlags carries the Z2 dirty name only
    """
  )
  func commitDeletionPartitionsMixedZones() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let notifier = RecordingNotifier()
    let hook = LocalWriteHook(notifier: notifier)

    // Two trips → two zones → two TripZoneState rows.
    let tripA = Trip(name: "A", startDate: .now, endDate: .now)
    let tripB = Trip(name: "B", startDate: .now, endDate: .now)
    let taskA = TripTask(trip: tripA, name: "Pack A")
    let taskB = TripTask(trip: tripB, name: "Pack B")
    context.insert(tripA)
    context.insert(tripB)
    context.insert(taskA)
    context.insert(taskB)
    try hook.commit(context)

    let zoneIDA = CKRecordZone.ID(
      zoneName: "trip-\(tripA.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    let zoneIDB = CKRecordZone.ID(
      zoneName: "trip-\(tripB.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )

    // Same context, same transaction:
    //  - delete tripA + taskA (zone A is vanishing)
    //  - edit taskB (zone B is surviving)
    let taskAID = taskA.id
    let tripAID = tripA.id
    context.delete(taskA)
    context.delete(tripA)
    taskB.name = "Pack B v2"
    notifier.calls.removeAll()

    try hook.commitDeletion(context, zoneIDsBeingDeleted: [zoneIDA])

    // Notifier received: deleted IDs for the vanishing zone, dirty IDs for
    // the surviving zone — both in the same commit.
    let vanishingCall = try #require(notifier.calls.first { $0.zoneID == zoneIDA })
    let survivingCall = try #require(notifier.calls.first { $0.zoneID == zoneIDB })

    let vanishingDeleted = Set(vanishingCall.deletedRecordIDs.map(\.recordName))
    #expect(vanishingDeleted.contains(tripAID.uuidString))
    #expect(vanishingDeleted.contains(taskAID.uuidString))
    #expect(vanishingCall.savedRecordIDs.isEmpty)

    #expect(survivingCall.deletedRecordIDs.isEmpty)
    #expect(survivingCall.savedRecordIDs.map(\.recordName) == [taskB.id.uuidString])

    // Surviving-zone TripZoneState carries the surviving dirty name only;
    // the vanishing zone's flag write was skipped.
    let zoneStates = try context.fetch(FetchDescriptor<TripZoneState>())
    let survivingState = try #require(zoneStates.first { $0.tripID == tripB.id })
    let survivingFlags = PendingUploadFlags.decode(survivingState.pendingUploadFlags)
    #expect(survivingFlags.dirtyRecordNames.contains(taskB.id.uuidString))
    #expect(!survivingFlags.dirtyRecordNames.contains(taskAID.uuidString))
    #expect(!survivingFlags.dirtyRecordNames.contains(tripAID.uuidString))
  }

  @Test(
    """
    commitDeletion: TripZoneState rows in deletedModelsArray are invisible to \
    both the flag-update and notifier paths (mapping(for:) returns nil)
    """
  )
  func commitDeletionIgnoresNilMappingRows() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let notifier = RecordingNotifier()
    let hook = LocalWriteHook(notifier: notifier)

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    try hook.commit(context)

    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )

    // Delete the trip and its TripZoneState in the same transaction.
    let tripIDValue = trip.id
    let zoneStates = try context.fetch(
      FetchDescriptor<TripZoneState>(predicate: #Predicate { $0.tripID == tripIDValue })
    )
    let zoneState = try #require(zoneStates.first)
    context.delete(trip)
    context.delete(zoneState)
    notifier.calls.removeAll()

    try hook.commitDeletion(context, zoneIDsBeingDeleted: [zoneID])

    // The notifier sees the Trip's deletion but NOT the TripZoneState's
    // deletion (its mapping is nil — local-only row, never replicated).
    let call = try #require(notifier.calls.first { $0.zoneID == zoneID })
    let deletedNames = Set(call.deletedRecordIDs.map(\.recordName))
    #expect(deletedNames.contains(trip.id.uuidString))
    #expect(deletedNames.count == 1, "Only the Trip is replicated; TripZoneState is local")
  }

  @Test(
    """
    commitDeletion: when every change is in a vanishing zone, the notifier \
    still receives the deleted IDs but no TripZoneState flag write occurs
    """
  )
  func commitDeletionAllVanishingZoneSkipsFlagWriteStillNotifies() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let notifier = RecordingNotifier()
    let hook = LocalWriteHook(notifier: notifier)

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack")
    context.insert(trip)
    context.insert(task)
    try hook.commit(context)

    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )

    // Capture the pre-deletion flags on the zone state to confirm they are
    // unchanged after commitDeletion (flag write skipped).
    let zoneState = try #require(
      try context.fetch(FetchDescriptor<TripZoneState>()).first
    )
    let preFlags = PendingUploadFlags.decode(zoneState.pendingUploadFlags)

    let taskIDValue = task.id
    let tripIDValue = trip.id
    context.delete(task)
    context.delete(trip)
    notifier.calls.removeAll()

    try hook.commitDeletion(context, zoneIDsBeingDeleted: [zoneID])

    let call = try #require(notifier.calls.first)
    let deletedNames = Set(call.deletedRecordIDs.map(\.recordName))
    #expect(deletedNames.contains(taskIDValue.uuidString))
    #expect(deletedNames.contains(tripIDValue.uuidString))

    // The pendingUploadFlags blob on the zone state did NOT receive the
    // delete markers — the zone is vanishing, so no flag-write happened.
    let postFlags = PendingUploadFlags.decode(zoneState.pendingUploadFlags)
    #expect(postFlags.dirtyRecordNames == preFlags.dirtyRecordNames)
    #expect(postFlags.deletedRecordNames == preFlags.deletedRecordNames)
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
final class RecordingNotifier: PendingChangeNotifier {
  struct Call {
    let savedRecordIDs: [CKRecord.ID]
    let deletedRecordIDs: [CKRecord.ID]
    let zoneID: CKRecordZone.ID
  }
  var calls: [Call] = []

  func notifyPendingChanges(
    savedRecordIDs: [CKRecord.ID],
    deletedRecordIDs: [CKRecord.ID],
    in zoneID: CKRecordZone.ID
  ) {
    calls.append(
      Call(
        savedRecordIDs: savedRecordIDs,
        deletedRecordIDs: deletedRecordIDs,
        zoneID: zoneID
      ))
  }
}
