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
  private(set) var calls: [Call] = []

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
