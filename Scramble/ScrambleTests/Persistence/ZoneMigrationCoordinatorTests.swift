import CloudKit
import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Phase 5 — Stage B (`ZoneMigrationCoordinator`) coverage.
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
/// Tests use an in-memory SwiftData container (the same store satisfies
/// both globals + tripsLocal lookups since `SchemaV3` declares every
/// entity). The driver is a recording fake; CloudKit is never reached.
@Suite("ZoneMigrationCoordinator", .serialized)
@MainActor
struct ZoneMigrationCoordinatorTests {

  // MARK: - enqueueAll

  @Test("enqueueAll inserts a .pending journal entry for each trip without a TripZoneState")
  func enqueuesPendingForUnmigratedTrips() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let driver = RecordingDriver()
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: driver
    )

    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()

    try coordinator.enqueueAll()

    let journals = try context.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.count == 1)
    #expect(journals.first?.tripID == trip.id)
    #expect(journals.first?.state == .pending)
  }

  @Test("enqueueAll skips trips that already have a TripZoneState")
  func skipsAlreadyMigratedTrips() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let driver = RecordingDriver()
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: driver
    )

    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    let state = TripZoneState(
      tripID: trip.id,
      zoneOwnerName: CKCurrentUserDefaultName,
      zoneScope: "private"
    )
    context.insert(trip)
    context.insert(state)
    try context.save()

    try coordinator.enqueueAll()

    let journals = try context.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.isEmpty, "Trip already has zone state; no journal entry needed")
  }

  @Test("enqueueAll is idempotent — second call does not duplicate journal entries")
  func enqueueAllIsIdempotent() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let driver = RecordingDriver()
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: driver
    )

    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()

    try coordinator.enqueueAll()
    try coordinator.enqueueAll()

    let journals = try context.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.count == 1)
  }

  // MARK: - runStageB

  @Test("runStageB skips entirely when cloud is unavailable (signed-out)")
  func skipsStageBWhenSignedOut() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let driver = RecordingDriver()
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: driver,
      isCloudAvailable: { false }
    )

    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()

    try coordinator.enqueueAll()
    try coordinator.runStageB()

    #expect(driver.savedZones.isEmpty)
    #expect(driver.savedRecordIDs.isEmpty)
    let journals = try context.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.first?.state == .pending, "Stage B remains queued until cloud returns")
  }

  @Test("runStageB transitions pending entries to .stageBInProgress and inserts TripZoneState")
  func transitionsPendingToInProgress() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let driver = RecordingDriver()
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: driver
    )

    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()

    try coordinator.enqueueAll()
    try coordinator.runStageB()

    let journals = try context.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.first?.state == .stageBInProgress)

    let states = try context.fetch(FetchDescriptor<TripZoneState>())
    #expect(states.count == 1)
    #expect(states.first?.tripID == trip.id)
    #expect(states.first?.zoneScope == "private")
    #expect(states.first?.zoneOwnerName == CKCurrentUserDefaultName)
  }

  @Test(
    "runStageB populates expectedRecordNames with Trip + tasks + packing items + snapshots")
  func populatesExpectedRecordNames() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let driver = RecordingDriver()
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: driver
    )

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
    context.insert(trip)
    context.insert(task)
    context.insert(snapshot)
    context.insert(item)
    try context.save()

    try coordinator.enqueueAll()
    try coordinator.runStageB()

    let journals = try context.fetch(FetchDescriptor<MigrationJournalEntry>())
    let expected = journals.first?.expectedRecordNames ?? []
    #expect(expected.contains(trip.id.uuidString))
    #expect(expected.contains(task.id.uuidString))
    #expect(expected.contains(item.id.uuidString))
    #expect(expected.contains(snapshot.id.uuidString))
    #expect(expected.count == 4)
  }

  @Test("runStageB signals driver to save the zone and queue all expected record IDs")
  func signalsDriverOnRun() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let driver = RecordingDriver()
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: driver
    )

    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack")
    context.insert(trip)
    context.insert(task)
    try context.save()

    try coordinator.enqueueAll()
    try coordinator.runStageB()

    let expectedZone = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    #expect(driver.savedZones.contains(expectedZone))
    let names = Set(driver.savedRecordIDs.map(\.recordName))
    #expect(names.contains(trip.id.uuidString))
    #expect(names.contains(task.id.uuidString))
  }

  @Test("runStageB marks every expected record dirty in TripZoneState.pendingUploadFlags")
  func marksRecordsDirty() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let driver = RecordingDriver()
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: driver
    )

    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack")
    context.insert(trip)
    context.insert(task)
    try context.save()

    try coordinator.enqueueAll()
    try coordinator.runStageB()

    let state = try #require(try context.fetch(FetchDescriptor<TripZoneState>()).first)
    let flags = PendingUploadFlags.decode(state.pendingUploadFlags)
    #expect(flags.dirtyRecordNames.contains(trip.id.uuidString))
    #expect(flags.dirtyRecordNames.contains(task.id.uuidString))
  }

  @Test("runStageB sets trip.tripZoneID to link the Trip to its TripZoneState")
  func setsTripZoneIDLink() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let driver = RecordingDriver()
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: driver
    )

    let trip = Trip(name: "Iceland", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()

    try coordinator.enqueueAll()
    try coordinator.runStageB()

    let stored = try #require(try context.fetch(FetchDescriptor<Trip>()).first)
    #expect(stored.tripZoneID == trip.id)
  }

  // MARK: - Event handlers

  @Test("handleZoneSaved + all records sent transitions the journal to .completed")
  func zoneSavedAndAllRecordsSentCompletes() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let driver = RecordingDriver()
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: driver
    )

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack")
    context.insert(trip)
    context.insert(task)
    try context.save()

    try coordinator.enqueueAll()
    try coordinator.runStageB()

    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    coordinator.handleZoneSaved(zoneID)
    coordinator.handleRecordsSaved([
      CKRecord.ID(recordName: trip.id.uuidString, zoneID: zoneID),
      CKRecord.ID(recordName: task.id.uuidString, zoneID: zoneID),
    ])

    let journals = try context.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.first?.state == .completed)
  }

  @Test("Zone saved but not all records sent keeps state at .stageBInProgress")
  func partialRecordsKeepsInProgress() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let driver = RecordingDriver()
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: driver
    )

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack")
    context.insert(trip)
    context.insert(task)
    try context.save()

    try coordinator.enqueueAll()
    try coordinator.runStageB()

    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    coordinator.handleZoneSaved(zoneID)
    coordinator.handleRecordsSaved([
      CKRecord.ID(recordName: trip.id.uuidString, zoneID: zoneID)
    ])

    let journals = try context.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.first?.state == .stageBInProgress)
  }

  @Test("All records sent but zone not saved keeps state at .stageBInProgress")
  func zoneNotSavedKeepsInProgress() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let driver = RecordingDriver()
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: driver
    )

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()

    try coordinator.enqueueAll()
    try coordinator.runStageB()

    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    coordinator.handleRecordsSaved([
      CKRecord.ID(recordName: trip.id.uuidString, zoneID: zoneID)
    ])

    let journals = try context.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.first?.state == .stageBInProgress)
  }

  @Test("handleRecordsFailed transitions state to .failed and records the error")
  func failedRecordsTransitionsToFailed() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let driver = RecordingDriver()
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: driver
    )

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()

    try coordinator.enqueueAll()
    try coordinator.runStageB()

    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    coordinator.handleRecordsFailed(
      [CKRecord.ID(recordName: trip.id.uuidString, zoneID: zoneID)],
      error: "quota exceeded"
    )

    let journals = try context.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.first?.state == .failed)
    #expect(journals.first?.errorMessage == "quota exceeded")
  }

  // MARK: - Resume after kill

  @Test("Resume re-signals the driver for .stageBInProgress entries on next launch")
  func resumeReSignalsDriver() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let driver = RecordingDriver()
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: driver
    )

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()

    try coordinator.enqueueAll()
    try coordinator.runStageB()
    let firstRunZoneSaves = driver.savedZones.count
    let firstRunRecordSaves = driver.savedRecordIDs.count

    // Simulate process restart: a new coordinator + driver picks up the
    // same persisted journal entry.
    let driver2 = RecordingDriver()
    let coordinator2 = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: driver2
    )

    try coordinator2.runStageB()

    #expect(driver2.savedZones.count >= 1, "Resume re-issues the zone-save instruction")
    #expect(driver2.savedRecordIDs.count >= 1, "Resume re-issues the record-save instructions")
    // Sanity: the first coordinator's recordings are unaffected.
    #expect(driver.savedZones.count == firstRunZoneSaves)
    #expect(driver.savedRecordIDs.count == firstRunRecordSaves)
  }

  @Test(
    "Resume does not re-enqueue trips already past .pending (no duplicate journal entries)")
  func resumeDoesNotDuplicateJournalEntries() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: RecordingDriver()
    )

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()

    try coordinator.enqueueAll()
    try coordinator.runStageB()

    let coordinator2 = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: RecordingDriver()
    )
    try coordinator2.enqueueAll()
    try coordinator2.runStageB()

    let journals = try context.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.count == 1)
  }

  // MARK: - Retry

  @Test("retry transitions .failed -> .stageBInProgress and re-signals the driver")
  func retryResumesFailedEntry() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let driver = RecordingDriver()
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: driver
    )

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()

    try coordinator.enqueueAll()
    try coordinator.runStageB()
    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    coordinator.handleRecordsFailed(
      [CKRecord.ID(recordName: trip.id.uuidString, zoneID: zoneID)],
      error: "transient"
    )

    let savedZonesBefore = driver.savedZones.count
    try coordinator.retry(tripID: trip.id)

    let journals = try context.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.first?.state == .stageBInProgress)
    #expect(journals.first?.errorMessage == nil)
    #expect(driver.savedZones.count > savedZonesBefore, "Retry re-issues the zone-save")
  }

  // MARK: - PBT: Idempotence

  @Test(
    "PBT — enqueueAll + runStageB twice yields the same end state",
    arguments: [1, 2, 3, 5])
  func pbtIdempotence(tripCount: Int) throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: RecordingDriver()
    )

    var trips: [Trip] = []
    for index in 0..<tripCount {
      let trip = Trip(name: "Trip\(index)", startDate: .now, endDate: .now)
      context.insert(trip)
      trips.append(trip)
    }
    try context.save()

    try coordinator.enqueueAll()
    try coordinator.runStageB()
    let stateAfterFirst = try Self.snapshotState(from: context)

    try coordinator.enqueueAll()
    try coordinator.runStageB()
    let stateAfterSecond = try Self.snapshotState(from: context)

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
      [true],                  // single success
      [false],                 // single failure (terminal but not completed)
      [false, true],           // failure then retry to success
      [false, false, true],    // two failures then success
      [true, false],           // success then unrelated failure has no effect
    ] as [[Bool]]
  )
  func pbtConvergenceOverFailureRetrySequences(sequence: [Bool]) throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let driver = RecordingDriver()
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: driver
    )

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack")
    context.insert(trip)
    context.insert(task)
    try context.save()

    try coordinator.enqueueAll()
    try coordinator.runStageB()

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
        coordinator.handleZoneSaved(zoneID)
        coordinator.handleRecordsSaved(allRecordIDs)
      } else {
        coordinator.handleRecordsFailed(allRecordIDs, error: "transient")
        // Resume the failed entry so the test's next outcome can transition it.
        try coordinator.retry(tripID: trip.id)
      }
    }

    let journals = try context.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.count == 1, "No duplicate entries created across the sequence")
    let final = try #require(journals.first)
    let isTerminal = final.state == .completed || final.state == .failed
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
    let container = try Self.makeContainer()
    let context = container.mainContext

    // Seed a trip + journal entry already in the parameterised state.
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    let journal = MigrationJournalEntry(tripID: trip.id, stateRaw: initialState.rawValue)
    context.insert(journal)
    if initialState != .pending {
      // Seed a TripZoneState too — anything past .pending implies the
      // coordinator has already inserted the zone state.
      let state = TripZoneState(
        tripID: trip.id,
        zoneOwnerName: CKCurrentUserDefaultName,
        zoneScope: "private"
      )
      context.insert(state)
    }
    try context.save()

    let driver = RecordingDriver()
    let coordinator = ZoneMigrationCoordinator(
      globalsContext: context,
      tripsLocalContext: context,
      driver: driver
    )

    // Resume — must not throw and must converge the journal entry to a
    // defined state. Concretely: completed/failed are left alone, pending
    // and stageBInProgress are (re-)started.
    try coordinator.runStageB()

    let journals = try context.fetch(FetchDescriptor<MigrationJournalEntry>())
    #expect(journals.count == 1, "Resume must not duplicate the journal row")
    switch initialState {
    case .pending, .stageBInProgress:
      #expect(journals.first?.state == .stageBInProgress)
      #expect(driver.savedZones.count == 1, "Resume re-issues the zone-save")
    case .completed, .failed:
      #expect(journals.first?.state == initialState)
      #expect(driver.savedZones.isEmpty, "Terminal entries are not re-run")
    }
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

  /// Snapshot of the persisted state used by idempotence tests.
  struct StoreSnapshot: Equatable {
    let journalCount: Int
    let zoneStateCount: Int
    let journalsByTrip: [UUID: String]
    let zoneScopesByTrip: [UUID: String]
  }

  private static func snapshotState(from context: ModelContext) throws -> StoreSnapshot {
    let journals = try context.fetch(FetchDescriptor<MigrationJournalEntry>())
    let states = try context.fetch(FetchDescriptor<TripZoneState>())
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
