import CloudKit
import Foundation
import SwiftData
import os

/// Phase 5 Stage B — moves a user's existing trips out of the CloudKit
/// default zone and into per-trip custom zones via `CKSyncEngine`
/// (Decision 13). Owner-only (`zoneScope = "private"`); participants
/// receive trip zones through `acceptShare` instead.
///
/// Two-phase API so `MigrationGate` can release the UI quickly:
///
/// 1. `enqueueAll()` — for every trip without a `TripZoneState`, inserts a
///    `MigrationJournalEntry(.pending)`. Runs unconditionally, including
///    when signed out.
/// 2. `runStageB()` — for every `.pending` or `.stageBInProgress` entry,
///    inserts the `TripZoneState`, marks every expected record dirty in
///    `pendingUploadFlags`, captures the expected record-name set on the
///    journal, and asks the supplied `ZoneMigrationDriver` to save the
///    zone + queue the records. Skipped when `isCloudAvailable()` returns
///    false (Req 11.3).
///
/// The coordinator does not block on CloudKit itself; the
/// `TripSyncEngine`-driven event loop calls `handleZoneSaved`,
/// `handleRecordsSaved`, and `handleRecordsFailed` as the events arrive.
@MainActor
final class ZoneMigrationCoordinator {
  let globalsContext: ModelContext
  let tripsLocalContext: ModelContext
  let driver: ZoneMigrationDriver
  let isCloudAvailable: () -> Bool
  let now: () -> Date

  init(
    globalsContext: ModelContext,
    tripsLocalContext: ModelContext,
    driver: ZoneMigrationDriver,
    isCloudAvailable: @escaping () -> Bool = { true },
    now: @escaping () -> Date = { .now }
  ) {
    self.globalsContext = globalsContext
    self.tripsLocalContext = tripsLocalContext
    self.driver = driver
    self.isCloudAvailable = isCloudAvailable
    self.now = now
  }

  // MARK: - Phase 1: enqueue

  /// Insert a `.pending` `MigrationJournalEntry` for every trip in
  /// `tripsLocal` that has not been moved into its trip zone yet (no
  /// matching `TripZoneState`). Idempotent — skips trips that already
  /// have a journal row.
  ///
  /// Until Phase 5.1 routes Trip CRUD through `tripsLocal`, the source
  /// fetch deliberately stays on `tripsLocalContext`. Switching it to
  /// `globalsContext` in isolation queues journals for trips whose
  /// records the engine can't find on upload, leaving every entry stuck
  /// in `.stageBInProgress` indefinitely (with a permanent "Syncing…"
  /// badge per trip). The cleaner state is the current silent no-op:
  /// nothing queues until Phase 5.1 lands the record-relocation step at
  /// the same time. See `docs/implementation-phases.md`.
  func enqueueAll() throws {
    let existingJournals = try globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    let existingByTrip = Dictionary(
      uniqueKeysWithValues: existingJournals.map { ($0.tripID, $0) }
    )
    let existingStates = try tripsLocalContext.fetch(FetchDescriptor<TripZoneState>())
    let migratedTripIDs = Set(existingStates.map(\.tripID))

    let trips = try tripsLocalContext.fetch(FetchDescriptor<Trip>())
    for trip in trips where !migratedTripIDs.contains(trip.id) {
      if existingByTrip[trip.id] != nil { continue }
      let entry = MigrationJournalEntry(
        tripID: trip.id,
        stateRaw: MigrationStageState.pending.rawValue,
        updatedAt: now()
      )
      globalsContext.insert(entry)
    }
    try globalsContext.save()
  }

  // MARK: - Phase 2: run Stage B

  /// Drive every `.pending` / `.stageBInProgress` journal entry forward.
  /// Inserts `TripZoneState`, marks every record dirty, persists the
  /// expected record-name set on the journal, then signals the driver.
  /// No-op when `isCloudAvailable()` is false.
  func runStageB() throws {
    guard isCloudAvailable() else {
      modelLogger.info("[ZoneMigrationCoordinator] cloud unavailable — Stage B deferred")
      return
    }
    let journals = try globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    for journal in journals {
      switch journal.state {
      case .pending, .stageBInProgress:
        try startOrResume(journal)
      case .completed, .failed:
        continue
      }
    }
  }

  /// Re-runs Stage B for a `.failed` entry. Clears the error, transitions
  /// back to `.stageBInProgress`, and re-signals the driver. No-op for
  /// entries in other states.
  func retry(tripID: UUID) throws {
    let descriptor = FetchDescriptor<MigrationJournalEntry>(
      predicate: #Predicate { $0.tripID == tripID }
    )
    guard let journal = try globalsContext.fetch(descriptor).first else { return }
    guard journal.state == .failed else { return }
    journal.errorMessage = nil
    journal.state = .stageBInProgress
    journal.updatedAt = now()
    try globalsContext.save()
    try startOrResume(journal)
  }

  // MARK: - Event handlers

  /// Called when `TripSyncEngine` confirms a zone-save event succeeded.
  /// Sets the journal's `zoneSaved` flag and (if completion criteria are
  /// met) transitions the entry to `.completed`.
  func handleZoneSaved(_ zoneID: CKRecordZone.ID) {
    guard let tripID = Self.parseTripID(from: zoneID.zoneName) else { return }
    guard let journal = fetchJournal(tripID: tripID) else { return }
    journal.zoneSaved = true
    journal.updatedAt = now()
    finaliseIfComplete(journal)
    try? globalsContext.save()
  }

  /// Called when `TripSyncEngine` confirms records were saved. Adds the
  /// record names to the journal's `sentRecordNames` set and finalises
  /// when the expected set is fully covered.
  func handleRecordsSaved(_ recordIDs: [CKRecord.ID]) {
    var dirty: Set<MigrationJournalEntry> = []
    for recordID in recordIDs {
      guard let tripID = Self.parseTripID(from: recordID.zoneID.zoneName) else { continue }
      guard let journal = fetchJournal(tripID: tripID) else { continue }
      var sent = journal.sentRecordNames
      sent.insert(recordID.recordName)
      journal.sentRecordNames = sent
      journal.updatedAt = now()
      dirty.insert(journal)
    }
    for journal in dirty {
      finaliseIfComplete(journal)
    }
    try? globalsContext.save()
  }

  /// Called when `TripSyncEngine` reports a save failure for one or more
  /// records. Transitions every affected journal entry to `.failed` with
  /// the supplied message.
  func handleRecordsFailed(_ recordIDs: [CKRecord.ID], error: String) {
    var seen: Set<UUID> = []
    for recordID in recordIDs {
      guard let tripID = Self.parseTripID(from: recordID.zoneID.zoneName) else { continue }
      guard seen.insert(tripID).inserted else { continue }
      guard let journal = fetchJournal(tripID: tripID) else { continue }
      journal.state = .failed
      journal.errorMessage = error
      journal.updatedAt = now()
    }
    try? globalsContext.save()
  }

  // MARK: - Private

  private func startOrResume(_ journal: MigrationJournalEntry) throws {
    let tripID = journal.tripID
    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(tripID.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )

    let trip = try fetchTrip(tripID: tripID)
    guard let trip else {
      // Trip vanished between enqueue and run — leave the journal in
      // place but mark it failed so the banner surfaces something.
      journal.state = .failed
      journal.errorMessage = "Trip not found"
      journal.updatedAt = now()
      try globalsContext.save()
      return
    }

    let state = try ensureZoneState(for: tripID, zoneID: zoneID)
    if trip.tripZoneID != tripID {
      trip.tripZoneID = tripID
    }

    let expectedNames = expectedRecordNames(for: trip)
    journal.expectedRecordNames = expectedNames
    journal.state = .stageBInProgress
    journal.updatedAt = now()
    if journal.errorMessage != nil {
      journal.errorMessage = nil
    }

    var flags = PendingUploadFlags.decode(state.pendingUploadFlags)
    for name in expectedNames {
      flags.markDirty(recordName: name)
    }
    state.pendingUploadFlags = flags.encode()

    try tripsLocalContext.save()
    try globalsContext.save()

    driver.saveZone(zoneID)
    let recordIDs = expectedNames.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
    if !recordIDs.isEmpty {
      driver.saveRecords(recordIDs)
    }
  }

  private func ensureZoneState(
    for tripID: UUID, zoneID: CKRecordZone.ID
  ) throws -> TripZoneState {
    let descriptor = FetchDescriptor<TripZoneState>(predicate: #Predicate { $0.tripID == tripID })
    if let existing = try tripsLocalContext.fetch(descriptor).first {
      return existing
    }
    let state = TripZoneState(
      tripID: tripID,
      zoneOwnerName: zoneID.ownerName,
      zoneScope: "private"
    )
    tripsLocalContext.insert(state)
    return state
  }

  private func expectedRecordNames(for trip: Trip) -> Set<String> {
    var names: Set<String> = [trip.id.uuidString]
    for task in trip.tasks ?? [] {
      names.insert(task.id.uuidString)
    }
    for item in trip.packingItems ?? [] {
      names.insert(item.id.uuidString)
    }
    for snapshot in trip.participantSnapshots ?? [] {
      names.insert(snapshot.id.uuidString)
    }
    return names
  }

  private func fetchTrip(tripID: UUID) throws -> Trip? {
    let descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == tripID })
    return try tripsLocalContext.fetch(descriptor).first
  }

  private func fetchJournal(tripID: UUID) -> MigrationJournalEntry? {
    let descriptor = FetchDescriptor<MigrationJournalEntry>(
      predicate: #Predicate { $0.tripID == tripID }
    )
    return try? globalsContext.fetch(descriptor).first
  }

  private func finaliseIfComplete(_ journal: MigrationJournalEntry) {
    guard journal.state == .stageBInProgress else { return }
    guard journal.isStageBComplete else { return }
    journal.state = .completed
    journal.updatedAt = now()
  }

  static func parseTripID(from zoneName: String) -> UUID? {
    guard zoneName.hasPrefix("trip-") else { return nil }
    let suffix = zoneName.dropFirst("trip-".count)
    return UUID(uuidString: String(suffix))
  }
}

// MARK: - Driver seam

/// Test seam over the engine operations the coordinator needs. Production
/// wires this to `TripSyncEngine.privateEngine`; tests use a recording
/// fake (`RecordingDriver`).
@MainActor
protocol ZoneMigrationDriver: AnyObject {
  /// Queue a zone-save (`CKSyncEngine.State.add(pendingDatabaseChanges:
  /// [.saveZone(zoneID)])`).
  func saveZone(_ zoneID: CKRecordZone.ID)

  /// Queue record-save changes
  /// (`CKSyncEngine.State.add(pendingRecordZoneChanges: [.saveRecord(id)])`).
  func saveRecords(_ recordIDs: [CKRecord.ID])
}

/// Production driver that wraps the `privateEngine` exposed by
/// `TripSyncEngine`. The engine starts uploads automatically when
/// `automaticallySync` is enabled.
@MainActor
final class TripSyncEngineZoneMigrationDriver: ZoneMigrationDriver {
  let syncEngine: TripSyncEngine

  init(syncEngine: TripSyncEngine) {
    self.syncEngine = syncEngine
  }

  func saveZone(_ zoneID: CKRecordZone.ID) {
    syncEngine.privateEngine?.state.add(
      pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))]
    )
  }

  func saveRecords(_ recordIDs: [CKRecord.ID]) {
    let changes: [CKSyncEngine.PendingRecordZoneChange] = recordIDs.map { .saveRecord($0) }
    syncEngine.privateEngine?.state.add(pendingRecordZoneChanges: changes)
    syncEngine.markSelfOriginated(recordIDs)
  }
}
