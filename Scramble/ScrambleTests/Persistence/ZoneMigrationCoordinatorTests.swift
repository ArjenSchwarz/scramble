import CloudKit
import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Phase 5 / Phase 5.1 — `ZoneMigrationCoordinator` coverage.
///
/// The coordinator picks up trips that have no `TripZoneState` (i.e., have
/// not yet been moved out of the default CloudKit zone), inserts a
/// `MigrationJournalEntry`, computes the expected record-ID set, marks all
/// of the trip's records dirty in `TripZoneState.pendingUploadFlags`, and
/// asks the supplied `ZoneMigrationDriver` to create the zone + queue the
/// records for upload. Sync-engine events (`zoneSaved`, `recordsSaved`,
/// `recordsFailed`) feed back into the coordinator to drive each journal
/// row to a terminal state.
///
/// Tests use TWO in-memory SwiftData containers — globals + tripsLocal —
/// because Phase 5.1's algorithm branches on existence-in-each-store. The
/// driver is a recording fake; CloudKit is never reached.
@Suite("ZoneMigrationCoordinator", .serialized)
@MainActor
struct ZoneMigrationCoordinatorTests {

  // MARK: - enqueueAll

  @Test("enqueueAll inserts a .pending journal entry for each trip without a TripZoneState")
  func enqueuesPendingForUnmigratedTrips() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    setup.tripsLocalContext.insert(trip)
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()

    let journals = try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.count == 1)
    #expect(journals.first?.tripID == trip.id)
    #expect(journals.first?.state == .pending)
  }

  @Test("enqueueAll skips trips that already have a TripZoneState")
  func skipsAlreadyMigratedTrips() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    let state = TripZoneState(
      tripID: trip.id,
      zoneOwnerName: CKCurrentUserDefaultName,
      zoneScope: "private"
    )
    setup.tripsLocalContext.insert(trip)
    setup.tripsLocalContext.insert(state)
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()

    let journals = try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.isEmpty, "Trip already has zone state; no journal entry needed")
  }

  @Test("enqueueAll is idempotent — second call does not duplicate journal entries")
  func enqueueAllIsIdempotent() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    setup.tripsLocalContext.insert(trip)
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.enqueueAll()

    let journals = try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.count == 1)
  }

  @Test("enqueueAll discovers trips still in globals (pre-Phase-5.1 state)")
  func enqueueAllDiscoversPrePhase51TripsInGlobals() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    setup.globalsContext.insert(trip)
    try setup.globalsContext.save()

    try setup.coordinator.enqueueAll()

    let journals = try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.count == 1)
    #expect(journals.first?.tripID == trip.id)
  }

  // MARK: - runStageB

  @Test("runStageB skips entirely when cloud is unavailable (signed-out)")
  func skipsStageBWhenSignedOut() throws {
    let setup = try Self.makeSetup(isCloudAvailable: { false })
    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    setup.tripsLocalContext.insert(trip)
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    #expect(setup.driver.savedZones.isEmpty)
    #expect(setup.driver.savedRecordIDs.isEmpty)
    let journals = try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.first?.state == .pending, "Stage B remains queued until cloud returns")
  }

  @Test("Signed-out launch with trip in globals: relocation completes; Stage B deferred (Req 4.7)")
  func signedOutCompletesRelocationButDefersStageB() throws {
    let setup = try Self.makeSetup(isCloudAvailable: { false })
    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    setup.globalsContext.insert(trip)
    try setup.globalsContext.save()

    try setup.coordinator.enqueueAll()
    // Signed-out: runStageB short-circuits per Req 11.3.
    try setup.coordinator.runStageB()

    // The trip is still in globals because runStageB never ran.
    let tripsLocal = try setup.tripsLocalContext.fetch(FetchDescriptor<Trip>())
    let globals = try setup.globalsContext.fetch(FetchDescriptor<Trip>())
    #expect(tripsLocal.isEmpty)
    #expect(globals.count == 1)

    // Sign in: now Stage B runs, relocation completes, trip moves to tripsLocal.
    let signedInSetup = Self.coordinatorOnly(
      from: setup,
      isCloudAvailable: { true }
    )
    try signedInSetup.runStageB()

    let tripsLocalAfter = try setup.tripsLocalContext.fetch(FetchDescriptor<Trip>())
    let globalsAfter = try setup.globalsContext.fetch(FetchDescriptor<Trip>())
    #expect(tripsLocalAfter.count == 1, "Trip relocated to tripsLocal after sign-in (Req 4.7/4.8)")
    #expect(globalsAfter.isEmpty, "Trip removed from globals after sign-in relocation")
  }

  @Test("runStageB transitions pending entries to .stageBInProgress and inserts TripZoneState")
  func transitionsPendingToInProgress() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    setup.tripsLocalContext.insert(trip)
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    let journals = try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.first?.state == .stageBInProgress)

    let states = try setup.tripsLocalContext.fetch(FetchDescriptor<TripZoneState>())
    #expect(states.count == 1)
    #expect(states.first?.tripID == trip.id)
    #expect(states.first?.zoneScope == "private")
    #expect(states.first?.zoneOwnerName == CKCurrentUserDefaultName)
  }

  @Test(
    "runStageB populates expectedRecordNames with Trip + tasks + packing items + snapshots")
  func populatesExpectedRecordNames() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
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
    setup.tripsLocalContext.insert(trip)
    setup.tripsLocalContext.insert(task)
    setup.tripsLocalContext.insert(snapshot)
    setup.tripsLocalContext.insert(item)
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    let journals = try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    let expected = journals.first?.expectedRecordNames ?? []
    #expect(expected.contains(trip.id.uuidString))
    #expect(expected.contains(task.id.uuidString))
    #expect(expected.contains(item.id.uuidString))
    #expect(expected.contains(snapshot.id.uuidString))
    #expect(expected.count == 4)
  }

  @Test("runStageB signals driver to save the zone and queue all expected record IDs")
  func signalsDriverOnRun() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack")
    setup.tripsLocalContext.insert(trip)
    setup.tripsLocalContext.insert(task)
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    let expectedZone = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    #expect(setup.driver.savedZones.contains(expectedZone))
    let names = Set(setup.driver.savedRecordIDs.map(\.recordName))
    #expect(names.contains(trip.id.uuidString))
    #expect(names.contains(task.id.uuidString))
  }

  @Test("runStageB marks every expected record dirty in TripZoneState.pendingUploadFlags")
  func marksRecordsDirty() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack")
    setup.tripsLocalContext.insert(trip)
    setup.tripsLocalContext.insert(task)
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    let state = try #require(
      try setup.tripsLocalContext.fetch(FetchDescriptor<TripZoneState>()).first
    )
    let flags = PendingUploadFlags.decode(state.pendingUploadFlags)
    #expect(flags.dirtyRecordNames.contains(trip.id.uuidString))
    #expect(flags.dirtyRecordNames.contains(task.id.uuidString))
  }

  @Test("runStageB sets trip.tripZoneID to link the Trip to its TripZoneState")
  func setsTripZoneIDLink() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    setup.tripsLocalContext.insert(trip)
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    let stored = try #require(
      try setup.tripsLocalContext.fetch(FetchDescriptor<Trip>()).first
    )
    #expect(stored.tripZoneID == trip.id)
  }

  // Phase 5.1-specific tests (four-quadrant branch, retroactive
  // dirty-flagging, step-10 clear, field preservation) live in
  // `ZoneMigrationCoordinatorPhase51Tests` so this file stays under the
  // SwiftLint type_body_length threshold.

  // MARK: - Event handlers

  @Test("handleZoneSaved + all records sent transitions the journal to .completed")
  func zoneSavedAndAllRecordsSentCompletes() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack")
    setup.tripsLocalContext.insert(trip)
    setup.tripsLocalContext.insert(task)
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    setup.coordinator.handleZoneSaved(zoneID)
    setup.coordinator.handleRecordsSaved([
      CKRecord.ID(recordName: trip.id.uuidString, zoneID: zoneID),
      CKRecord.ID(recordName: task.id.uuidString, zoneID: zoneID),
    ])

    let journals = try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.first?.state == .completed)
  }

  @Test("Zone saved but not all records sent keeps state at .stageBInProgress")
  func partialRecordsKeepsInProgress() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack")
    setup.tripsLocalContext.insert(trip)
    setup.tripsLocalContext.insert(task)
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    setup.coordinator.handleZoneSaved(zoneID)
    setup.coordinator.handleRecordsSaved([
      CKRecord.ID(recordName: trip.id.uuidString, zoneID: zoneID)
    ])

    let journals = try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.first?.state == .stageBInProgress)
  }

  @Test("All records sent but zone not saved keeps state at .stageBInProgress")
  func zoneNotSavedKeepsInProgress() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    setup.tripsLocalContext.insert(trip)
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    setup.coordinator.handleRecordsSaved([
      CKRecord.ID(recordName: trip.id.uuidString, zoneID: zoneID)
    ])

    let journals = try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.first?.state == .stageBInProgress)
  }

  @Test("handleRecordsFailed transitions state to .failed and records the error")
  func failedRecordsTransitionsToFailed() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    setup.tripsLocalContext.insert(trip)
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    setup.coordinator.handleRecordsFailed(
      [CKRecord.ID(recordName: trip.id.uuidString, zoneID: zoneID)],
      error: "quota exceeded"
    )

    let journals = try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.first?.state == .failed)
    #expect(journals.first?.errorMessage == "quota exceeded")
  }

  // MARK: - Resume after kill

  @Test("Resume re-signals the driver for .stageBInProgress entries on next launch")
  func resumeReSignalsDriver() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    setup.tripsLocalContext.insert(trip)
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()
    let firstRunZoneSaves = setup.driver.savedZones.count
    let firstRunRecordSaves = setup.driver.savedRecordIDs.count

    let coordinator2 = Self.coordinatorOnly(from: setup)
    try coordinator2.runStageB()

    #expect(setup.driver.savedZones.count == firstRunZoneSaves)
    #expect(setup.driver.savedRecordIDs.count == firstRunRecordSaves)
  }

  @Test(
    "Resume does not re-enqueue trips already past .pending (no duplicate journal entries)")
  func resumeDoesNotDuplicateJournalEntries() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    setup.tripsLocalContext.insert(trip)
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    let coordinator2 = Self.coordinatorOnly(from: setup)
    try coordinator2.enqueueAll()
    try coordinator2.runStageB()

    let journals = try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.count == 1)
  }

  // MARK: - Retry

  @Test("retry transitions .failed -> .stageBInProgress and re-signals the driver")
  func retryResumesFailedEntry() throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    setup.tripsLocalContext.insert(trip)
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()
    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    setup.coordinator.handleRecordsFailed(
      [CKRecord.ID(recordName: trip.id.uuidString, zoneID: zoneID)],
      error: "transient"
    )

    let savedZonesBefore = setup.driver.savedZones.count
    try setup.coordinator.retry(tripID: trip.id)

    let journals = try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.first?.state == .stageBInProgress)
    #expect(journals.first?.errorMessage == nil)
    #expect(setup.driver.savedZones.count > savedZonesBefore, "Retry re-issues the zone-save")
  }

  // MARK: - PBT: Idempotence

  @Test(
    "PBT — enqueueAll + runStageB twice yields the same end state",
    arguments: [1, 2, 3, 5])
  func pbtIdempotence(tripCount: Int) throws {
    let setup = try Self.makeSetup()
    for index in 0..<tripCount {
      let trip = Trip(name: "Trip\(index)", startDate: .now, endDate: .now)
      setup.tripsLocalContext.insert(trip)
    }
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()
    let stateAfterFirst = try Self.snapshotState(
      globals: setup.globalsContext, tripsLocal: setup.tripsLocalContext
    )

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()
    let stateAfterSecond = try Self.snapshotState(
      globals: setup.globalsContext, tripsLocal: setup.tripsLocalContext
    )

    #expect(stateAfterFirst == stateAfterSecond)
    #expect(stateAfterFirst.journalCount == tripCount)
    #expect(stateAfterFirst.zoneStateCount == tripCount)
  }

  // MARK: - PBT: Convergence

  /// Convergence — any sequence of partial failures + retries reaches a
  /// terminal state with no duplicated journal entries.
  @Test(
    "PBT — partial-failure-then-retry sequences converge to a terminal state",
    arguments: [
      [true],  // single success
      [false],  // single failure (terminal but not completed)
      [false, true],  // failure then retry to success
      [false, false, true],  // two failures then success
      [true, false],  // success then unrelated failure has no effect
    ] as [[Bool]]
  )
  func pbtConvergenceOverFailureRetrySequences(sequence: [Bool]) throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack")
    setup.tripsLocalContext.insert(trip)
    setup.tripsLocalContext.insert(task)
    try setup.tripsLocalContext.save()

    try setup.coordinator.enqueueAll()
    try setup.coordinator.runStageB()

    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    let allRecordIDs: [CKRecord.ID] = [
      CKRecord.ID(recordName: trip.id.uuidString, zoneID: zoneID),
      CKRecord.ID(recordName: task.id.uuidString, zoneID: zoneID),
    ]

    var lastIsSuccess = false
    for isSuccess in sequence {
      lastIsSuccess = isSuccess
      if isSuccess {
        setup.coordinator.handleZoneSaved(zoneID)
        setup.coordinator.handleRecordsSaved(allRecordIDs)
      } else {
        setup.coordinator.handleRecordsFailed(allRecordIDs, error: "transient")
        try setup.coordinator.retry(tripID: trip.id)
      }
    }

    let journals = try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.count == 1, "No duplicate entries created across the sequence")
    let final = try #require(journals.first)
    let isTerminal =
      final.state == .completed || final.state == .failed
      || final.state == .stageBInProgress
    #expect(isTerminal, "Each sequence reaches a defined state")
    if lastIsSuccess {
      #expect(final.state == .completed)
    }
  }

  // MARK: - PBT: Resume totality

  @Test(
    "PBT — resume is a total function: any persisted state has a defined action",
    arguments: [
      MigrationStageState.pending,
      .stageBInProgress,
      .completed,
      .failed,
    ]
  )
  func pbtResumeTotality(initialState: MigrationStageState) throws {
    let setup = try Self.makeSetup()
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    setup.tripsLocalContext.insert(trip)
    let journal = MigrationJournalEntry(tripID: trip.id, stateRaw: initialState.rawValue)
    setup.globalsContext.insert(journal)
    if initialState != .pending {
      let state = TripZoneState(
        tripID: trip.id,
        zoneOwnerName: CKCurrentUserDefaultName,
        zoneScope: "private"
      )
      setup.tripsLocalContext.insert(state)
    }
    try setup.tripsLocalContext.save()
    try setup.globalsContext.save()

    try setup.coordinator.runStageB()

    let journals = try setup.globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.count == 1, "Resume must not duplicate the journal row")
    switch initialState {
    case .pending, .stageBInProgress:
      #expect(journals.first?.state == .stageBInProgress)
      #expect(setup.driver.savedZones.count == 1, "Resume re-issues the zone-save")
    case .completed, .failed:
      #expect(journals.first?.state == initialState)
      #expect(setup.driver.savedZones.isEmpty, "Terminal entries are not re-run")
    }
  }

  // MARK: - Helpers

  /// Per-test setup bundling the two containers, both `ModelContext`s,
  /// the recording driver, and the coordinator under test.
  struct Setup {
    let globalsContainer: ModelContainer
    let tripsLocalContainer: ModelContainer
    let globalsContext: ModelContext
    let tripsLocalContext: ModelContext
    let driver: RecordingDriver
    let coordinator: ZoneMigrationCoordinator
  }

  static func makeSetup(isCloudAvailable: @escaping () -> Bool = { true }) throws -> Setup {
    let pair = try makeContainerPair()
    let driver = RecordingDriver()
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: pair.globals.mainContext,
      tripsLocalContext: pair.tripsLocal.mainContext,
      driver: driver,
      isCloudAvailable: isCloudAvailable
    )
    return Setup(
      globalsContainer: pair.globals,
      tripsLocalContainer: pair.tripsLocal,
      globalsContext: pair.globals.mainContext,
      tripsLocalContext: pair.tripsLocal.mainContext,
      driver: driver,
      coordinator: coordinator
    )
  }

  /// Build a fresh coordinator over the same containers as `setup` —
  /// simulates a process restart by giving the new coordinator its own
  /// (empty) driver while the persisted journal + trip rows continue.
  static func coordinatorOnly(
    from setup: Setup,
    isCloudAvailable: @escaping () -> Bool = { true }
  ) -> ZoneMigrationCoordinator {
    ZoneMigrationCoordinator(
      globalsContext: setup.globalsContext,
      tripsLocalContext: setup.tripsLocalContext,
      driver: RecordingDriver(),
      isCloudAvailable: isCloudAvailable
    )
  }

  static func makeContainerPair() throws -> (globals: ModelContainer, tripsLocal: ModelContainer) {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let globalsConfig = ModelConfiguration(
      "globals",
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    let tripsLocalConfig = ModelConfiguration(
      "tripsLocal",
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    let globals = try ModelContainer(for: schema, configurations: [globalsConfig])
    let tripsLocal = try ModelContainer(for: schema, configurations: [tripsLocalConfig])
    return (globals, tripsLocal)
  }

  /// Snapshot of the persisted state used by idempotence tests.
  struct StoreSnapshot: Equatable {
    let journalCount: Int
    let zoneStateCount: Int
    let journalsByTrip: [UUID: String]
    let zoneScopesByTrip: [UUID: String]
  }

  private static func snapshotState(
    globals: ModelContext, tripsLocal: ModelContext
  ) throws -> StoreSnapshot {
    let journals = try globals.fetch(FetchDescriptor<MigrationJournalEntry>())
    let states = try tripsLocal.fetch(FetchDescriptor<TripZoneState>())
    return StoreSnapshot(
      journalCount: journals.count,
      zoneStateCount: states.count,
      journalsByTrip: Dictionary(uniqueKeysWithValues: journals.map { ($0.tripID, $0.stateRaw) }),
      zoneScopesByTrip: Dictionary(uniqueKeysWithValues: states.map { ($0.tripID, $0.zoneScope) })
    )
  }
}

/// Recording fake `ZoneMigrationDriver` used by the coordinator tests.
@MainActor
final class RecordingDriver: ZoneMigrationDriver {
  private(set) var savedZones: [CKRecordZone.ID] = []
  private(set) var savedRecordIDs: [CKRecord.ID] = []

  func saveZone(_ zoneID: CKRecordZone.ID) {
    savedZones.append(zoneID)
  }

  func saveRecords(_ recordIDs: [CKRecord.ID]) {
    savedRecordIDs.append(contentsOf: recordIDs)
  }
}
