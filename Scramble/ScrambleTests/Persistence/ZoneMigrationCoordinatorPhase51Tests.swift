import CloudKit
import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Phase 5.1-specific `ZoneMigrationCoordinator` tests — the
/// four-quadrant existence branch, retroactive Stage A dirty-flagging,
/// and step-10 cross-run contamination guard. Kept separate from
/// `ZoneMigrationCoordinatorTests` so the parent struct stays under
/// SwiftLint's `type_body_length` warning threshold.
@Suite("ZoneMigrationCoordinator Phase 5.1", .serialized)
@MainActor
struct ZoneMigrationCoordinatorPhase51Tests {

  // MARK: - Phase 5.1 — four-quadrant existence branch

  @Test(".completed journal entries are terminal no-ops (step 2 short-circuit)")
  func completedJournalIsTerminalNoOp() throws {
    let setup = try ZoneMigrationCoordinatorTests.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    setup.tripsLocalContext.insert(trip)
    let journal = MigrationJournalEntry(
      tripID: trip.id,
      stateRaw: MigrationStageState.completed.rawValue,
      updatedAt: .now
    )
    setup.globalsContext.insert(journal)
    let state = TripZoneState(
      tripID: trip.id,
      zoneOwnerName: CKCurrentUserDefaultName,
      zoneScope: "private"
    )
    setup.tripsLocalContext.insert(state)
    try setup.tripsLocalContext.save()
    try setup.globalsContext.save()

    try setup.coordinator.runStageB()

    #expect(setup.driver.savedZones.isEmpty, ".completed never re-issues driver work")
    #expect(setup.driver.savedRecordIDs.isEmpty)
    let journals = try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.first?.state == .completed)
  }

  @Test("Branch (none, some): full relocation + delete-from-globals + Stage B start")
  func branchGlobalsOnlyRelocates() throws {
    let setup = try ZoneMigrationCoordinatorTests.makeSetup()
    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack")
    setup.globalsContext.insert(trip)
    setup.globalsContext.insert(task)
    try setup.globalsContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    let tripsLocalTrips = try setup.tripsLocalContext.fetch(FetchDescriptor<Trip>())
    let globalsTrips = try setup.globalsContext.fetch(FetchDescriptor<Trip>())
    #expect(tripsLocalTrips.count == 1, "Trip relocated to tripsLocal")
    #expect(globalsTrips.isEmpty, "Trip deleted from globals")
    let tripsLocalTasks = try setup.tripsLocalContext.fetch(FetchDescriptor<TripTask>())
    let globalsTasks = try setup.globalsContext.fetch(FetchDescriptor<TripTask>())
    #expect(tripsLocalTasks.count == 1, "Task relocated to tripsLocal")
    #expect(globalsTasks.isEmpty, "Task deleted from globals")
  }

  @Test("Branch (some, some): only the delete-from-globals step runs (resume after insert step)")
  func branchBothQuadrantSkipsInsert() throws {
    let setup = try ZoneMigrationCoordinatorTests.makeSetup()
    let tripID = UUID()
    // Both stores hold the trip — simulates resume after step 14a (the
    // tripsLocal save completed) but before step 14b (the globals
    // delete commit).
    let tripInGlobals = Trip(id: tripID, name: "T", startDate: .now, endDate: .now)
    let tripInTripsLocal = Trip(id: tripID, name: "T", startDate: .now, endDate: .now)
    setup.globalsContext.insert(tripInGlobals)
    setup.tripsLocalContext.insert(tripInTripsLocal)
    try setup.globalsContext.save()
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    let globalsTrips = try setup.globalsContext.fetch(FetchDescriptor<Trip>())
    let tripsLocalTrips = try setup.tripsLocalContext.fetch(FetchDescriptor<Trip>())
    #expect(globalsTrips.isEmpty, "Globals copy deleted")
    #expect(tripsLocalTrips.count == 1, "tripsLocal copy preserved")
  }

  @Test("Branch (some, none): relocation already complete; Stage B starts cleanly")
  func branchTripsLocalOnly() throws {
    let setup = try ZoneMigrationCoordinatorTests.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    setup.tripsLocalContext.insert(trip)
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    let journals = try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.first?.state == .stageBInProgress)
    let states = try setup.tripsLocalContext.fetch(FetchDescriptor<TripZoneState>())
    #expect(states.count == 1)
  }

  @Test("deleteFromGlobals removes any TripZoneState rows that exist in globals (defence)")
  func deleteFromGlobalsRemovesOrphanZoneStates() throws {
    let setup = try ZoneMigrationCoordinatorTests.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    // Seed a TripZoneState row directly in globals to simulate the
    // hypothetical pre-Phase-5.0 orphan the reviewer flagged. Production
    // never inserts here, but the defence should still sweep it.
    let state = TripZoneState(
      tripID: trip.id,
      zoneOwnerName: CKCurrentUserDefaultName,
      zoneScope: "private"
    )
    setup.globalsContext.insert(trip)
    setup.globalsContext.insert(state)
    try setup.globalsContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    let globalsZoneStates = try setup.globalsContext.fetch(FetchDescriptor<TripZoneState>())
    let tripsLocalZoneStates = try setup.tripsLocalContext.fetch(FetchDescriptor<TripZoneState>())
    #expect(globalsZoneStates.isEmpty, "Orphan zone state swept from globals")
    #expect(tripsLocalZoneStates.count == 1, "Fresh zone state in tripsLocal")
    #expect(tripsLocalZoneStates.first?.tripID == trip.id)
  }

  @Test("Branch (none, none): trip vanished — journal transitions to .failed")
  func branchTripVanishedMarksFailed() throws {
    let setup = try ZoneMigrationCoordinatorTests.makeSetup()
    let tripID = UUID()
    // Pre-seed a journal entry pointing at a trip that exists in neither
    // store. This mimics a stale journal row (Decision 11 / design §
    // "Concurrency and ordering contracts").
    let journal = MigrationJournalEntry(
      tripID: tripID,
      stateRaw: MigrationStageState.pending.rawValue
    )
    setup.globalsContext.insert(journal)
    try setup.globalsContext.save()

    try setup.coordinator.runStageB()

    let journals = try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.first?.state == .failed)
    #expect(journals.first?.errorMessage == "Trip not found")
  }

  // MARK: - Phase 5.1 — relocation preserves persisted fields (Req 4.2)

  // swiftlint:disable function_body_length
  @Test("Relocation preserves every persisted field per Req 4.2")
  func relocationPreservesAllFields() throws {
    let setup = try ZoneMigrationCoordinatorTests.makeSetup()
    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    var attributes = trip.attributes
    attributes.setSingle(.weather, value: "warm")
    trip.attributes = attributes
    trip.ckRecordSystemFields = Data([0x01, 0x02, 0x03])
    let masterID = UUID()
    let assigneeID = UUID()
    let task = TripTask(
      trip: trip,
      masterItemID: masterID,
      name: "Pack socks",
      phase: .dayBefore,
      isCompleted: true,
      source: .rule,
      currentlyMatchesRules: false,
      pinnedByUser: true,
      assigneePersonID: assigneeID,
      userDeletedOnThisTrip: true
    )
    task.ckRecordSystemFields = Data([0x10])
    let snapshot = TripPersonSnapshot(
      personID: assigneeID,
      name: "Alice",
      colourID: "cyan",
      initialSource: "manual",
      isRosterMember: false,
      trip: trip
    )
    snapshot.ckRecordSystemFields = Data([0x20])
    let item = TripPackingItem(
      trip: trip,
      masterItemID: masterID,
      name: "Socks",
      state: .packed,
      source: .rule,
      currentlyMatchesRules: false,
      pinnedByUser: true,
      personSnapshot: snapshot
    )
    item.ckRecordSystemFields = Data([0x30])
    setup.globalsContext.insert(trip)
    setup.globalsContext.insert(task)
    setup.globalsContext.insert(snapshot)
    setup.globalsContext.insert(item)
    try setup.globalsContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    let relocatedTrip = try #require(
      try setup.tripsLocalContext.fetch(FetchDescriptor<Trip>()).first
    )
    #expect(relocatedTrip.id == trip.id)
    #expect(relocatedTrip.name == trip.name)
    #expect(relocatedTrip.attributes.selected(.weather) == ["warm"])
    #expect(relocatedTrip.ckRecordSystemFields == Data([0x01, 0x02, 0x03]))

    let relocatedTask = try #require(
      try setup.tripsLocalContext.fetch(FetchDescriptor<TripTask>()).first
    )
    #expect(relocatedTask.masterItemID == masterID)
    #expect(relocatedTask.name == "Pack socks")
    #expect(relocatedTask.phase == .dayBefore)
    #expect(relocatedTask.isCompleted == true)
    #expect(relocatedTask.source == .rule)
    #expect(relocatedTask.currentlyMatchesRules == false)
    #expect(relocatedTask.pinnedByUser == true)
    #expect(relocatedTask.assigneePersonID == assigneeID)
    #expect(relocatedTask.userDeletedOnThisTrip == true)
    #expect(relocatedTask.ckRecordSystemFields == Data([0x10]))

    let relocatedSnapshot = try #require(
      try setup.tripsLocalContext.fetch(FetchDescriptor<TripPersonSnapshot>()).first
    )
    #expect(relocatedSnapshot.personID == assigneeID)
    #expect(relocatedSnapshot.name == "Alice")
    #expect(relocatedSnapshot.colourID == "cyan")
    #expect(relocatedSnapshot.initialSource == "manual")
    #expect(relocatedSnapshot.isRosterMember == false)
    #expect(relocatedSnapshot.ckRecordSystemFields == Data([0x20]))

    let relocatedItem = try #require(
      try setup.tripsLocalContext.fetch(FetchDescriptor<TripPackingItem>()).first
    )
    #expect(relocatedItem.masterItemID == masterID)
    #expect(relocatedItem.name == "Socks")
    #expect(relocatedItem.state == .packed)
    #expect(relocatedItem.source == .rule)
    #expect(relocatedItem.currentlyMatchesRules == false)
    #expect(relocatedItem.pinnedByUser == true)
    #expect(relocatedItem.ckRecordSystemFields == Data([0x30]))
    #expect(relocatedItem.personSnapshot?.id == snapshot.id)
  }
  // swiftlint:enable function_body_length

  // MARK: - packing-item-subitems — relocation carries note + subItems

  @Test("relocateTrip carries a packing item's note + subItemsData (feature regression guard)")
  func relocationCarriesNoteAndSubItems() throws {
    let setup = try ZoneMigrationCoordinatorTests.makeSetup()
    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    let snapshot = TripPersonSnapshot(
      personID: UUID(),
      name: "Alice",
      colourID: "cyan",
      initialSource: "manual",
      isRosterMember: true,
      trip: trip
    )
    let item = TripPackingItem(
      trip: trip,
      name: "Toys",
      personSnapshot: snapshot,
      note: "keep batteries out"
    )
    item.subItems = ["lego", "blocks", "lego"]  // duplicate + order preserved
    setup.globalsContext.insert(trip)
    setup.globalsContext.insert(snapshot)
    setup.globalsContext.insert(item)
    try setup.globalsContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    let relocated = try #require(
      try setup.tripsLocalContext.fetch(FetchDescriptor<TripPackingItem>()).first
    )
    #expect(relocated.note == "keep batteries out")
    #expect(relocated.subItems == ["lego", "blocks", "lego"])
  }

  @Test("relocateTrip leaves a nil-note nil-subItems item still nil (no empty blob)")
  func relocationNilFieldsStayNil() throws {
    let setup = try ZoneMigrationCoordinatorTests.makeSetup()
    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    let item = TripPackingItem(trip: trip, name: "Towel")
    // Both new fields untouched ⇒ nil.
    setup.globalsContext.insert(trip)
    setup.globalsContext.insert(item)
    try setup.globalsContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    let relocated = try #require(
      try setup.tripsLocalContext.fetch(FetchDescriptor<TripPackingItem>()).first
    )
    #expect(relocated.note == nil)
    #expect(relocated.subItemsData == nil, "nil must relocate as nil, not an empty Data()")
    #expect(relocated.subItems == [])
  }

  // MARK: - Phase 5.1 — Stage A snapshot retroactive dirty-flagging (Req 4.9)

  @Test("Stage A TripPersonSnapshot rows are retroactively dirty-flagged on Stage B entry")
  func stageASnapshotsRetroactivelyDirtyFlagged() throws {
    let setup = try ZoneMigrationCoordinatorTests.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    // Pre-seed a snapshot DIRECTLY in tripsLocal (the Stage A backfill
    // does this against the pre-Phase-5.1 empty production state, where
    // the trip itself lives in globals).
    let snapshot = TripPersonSnapshot(
      personID: UUID(),
      name: "Alice",
      colourID: "cyan",
      initialSource: "name",
      isRosterMember: true,
      trip: trip
    )
    setup.tripsLocalContext.insert(trip)
    setup.tripsLocalContext.insert(snapshot)
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    let state = try #require(
      try setup.tripsLocalContext.fetch(FetchDescriptor<TripZoneState>()).first
    )
    let flags = PendingUploadFlags.decode(state.pendingUploadFlags)
    #expect(
      flags.dirtyRecordNames.contains(snapshot.id.uuidString),
      "Snapshot row dirty-flagged retroactively (Req 4.9)"
    )
  }

  // MARK: - Phase 5.1 — Step 10 clear of sentRecordNames + zoneSaved

  @Test("Step 10 clear: prior-aborted-run events become no-ops on resume")
  func step10ClearPriorRunEventsAreNoOps() throws {
    let setup = try ZoneMigrationCoordinatorTests.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    setup.tripsLocalContext.insert(trip)
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )

    // Simulate prior aborted run that confirmed zoneSaved + the trip
    // record but never finished the journal.
    setup.coordinator.handleZoneSaved(zoneID)
    setup.coordinator.handleRecordsSaved([
      CKRecord.ID(recordName: trip.id.uuidString, zoneID: zoneID)
    ])

    let journals = try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    let priorJournal = try #require(journals.first)
    // With a single expected record (trip-only), the prior events fully
    // satisfy the journal — the run completes.
    #expect(priorJournal.state == .completed)

    // Now simulate that the journal was forced back to .stageBInProgress
    // by an out-of-band path (e.g., the retry path with a mid-flight
    // crash); resume must clear sentRecordNames + zoneSaved so the
    // prior-run events that arrive later become no-ops.
    priorJournal.state = .stageBInProgress
    try setup.globalsContext.save()

    // Replay startOrResume — this is what runStageB calls.
    try setup.coordinator.runStageB()

    let resumedJournal = try #require(
      try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>()).first
    )
    #expect(resumedJournal.zoneSaved == false, "zoneSaved cleared on resume (step 10)")
    #expect(resumedJournal.sentRecordNames.isEmpty, "sentRecordNames cleared on resume (step 10)")
  }
}
