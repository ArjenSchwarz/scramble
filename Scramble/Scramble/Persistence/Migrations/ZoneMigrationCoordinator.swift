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

  /// Insert a `.pending` `MigrationJournalEntry` for every trip that has
  /// not been moved into its trip zone yet (no matching
  /// `TripZoneState`). Idempotent — skips trips that already have a
  /// journal row.
  ///
  /// Phase 5.1 — scans BOTH containers so that pre-Phase-5.1 trips still
  /// in `globals` get a journal entry (their records are relocated to
  /// `tripsLocal` by `startOrResume`'s relocation step) and trips
  /// already in `tripsLocal` (post-Phase-5.1 creates) also get a
  /// journal entry until their `TripZoneState` is created.
  func enqueueAll() throws {
    let existingJournals = try globalsContext.fetch(FetchDescriptor<MigrationJournalEntry>())
    let existingByTrip = Dictionary(
      uniqueKeysWithValues: existingJournals.map { ($0.tripID, $0) }
    )
    let existingStates = try tripsLocalContext.fetch(FetchDescriptor<TripZoneState>())
    let migratedTripIDs = Set(existingStates.map(\.tripID))

    var seenTripIDs: Set<UUID> = []
    let tripsLocalTrips = try tripsLocalContext.fetch(FetchDescriptor<Trip>())
    let globalsTrips = try globalsContext.fetch(FetchDescriptor<Trip>())
    let allTripIDs = tripsLocalTrips.map(\.id) + globalsTrips.map(\.id)

    for tripID in allTripIDs where !migratedTripIDs.contains(tripID) {
      guard seenTripIDs.insert(tripID).inserted else { continue }
      if existingByTrip[tripID] != nil { continue }
      let entry = MigrationJournalEntry(
        tripID: tripID,
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

  // swiftlint:disable cyclomatic_complexity function_body_length

  /// Phase 5.1 — 15-step relocation + Stage B start. See spec
  /// `phase-5.1-wire-trip-crud-tripslocal/design.md § ZoneMigrationCoordinator`.
  /// The algorithm derives its resume invariant from container contents,
  /// not from a journal field: which of the two stores currently holds
  /// the trip is the canonical signal of where the previous run was
  /// interrupted.
  private func startOrResume(_ journal: MigrationJournalEntry) throws {
    let tripID = journal.tripID

    // Step 2 — `.completed` is a terminal no-op. Re-running against a
    // completed entry must not re-issue driver work.
    if journal.state == .completed { return }

    // Step 3 — canonical zone ID for the trip (private DB, owner-side).
    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(tripID.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )

    // Steps 4–6 — four-quadrant existence branch over (tripsLocal, globals).
    // Each branch is written explicitly so the code maps 1:1 to the
    // design doc's algorithm sketch.
    let tripInTripsLocal = try fetchTrip(tripID: tripID, in: tripsLocalContext)
    let tripInGlobals = try fetchTrip(tripID: tripID, in: globalsContext)

    switch (tripInTripsLocal, tripInGlobals) {
    case (.some, .some):
      // Insert step done; only the delete remains.
      try deleteFromGlobals(tripID: tripID)
    case (.some, .none):
      // Relocation complete; continue with upload.
      break
    case (.none, .some):
      // Not yet relocated — perform both steps.
      try relocateToTripsLocal(tripID: tripID)
      try deleteFromGlobals(tripID: tripID)
    case (.none, .none):
      // Trip vanished — leave a `.failed` journal entry so the banner
      // surfaces something. The entry stays around as audit data.
      journal.state = .failed
      journal.errorMessage = "Trip not found"
      journal.updatedAt = now()
      try globalsContext.save()
      return
    }

    // After step 6 the trip lives in tripsLocal exclusively. Re-fetch
    // because the relocation inserts a new instance.
    guard let trip = try fetchTrip(tripID: tripID, in: tripsLocalContext) else {
      journal.state = .failed
      journal.errorMessage = "Trip not found after relocation"
      journal.updatedAt = now()
      try globalsContext.save()
      return
    }

    // Step 8 — ensure TripZoneState exists in tripsLocal.
    let state = try ensureZoneState(for: tripID, zoneID: zoneID)
    if trip.tripZoneID != tripID {
      trip.tripZoneID = tripID
    }

    // Step 9 — compute the expected record-name set from current state.
    let expectedNames = expectedRecordNames(for: trip)

    // Step 10 — clear stale sub-state from any prior aborted run before
    // re-marking the journal `.stageBInProgress` with fresh expected
    // names. This is the cross-run contamination guard (design §
    // "Concurrency and ordering contracts").
    journal.sentRecordNames = []
    journal.zoneSaved = false

    // Step 11 — mark journal `.stageBInProgress`.
    journal.expectedRecordNames = expectedNames
    journal.state = .stageBInProgress
    journal.updatedAt = now()
    if journal.errorMessage != nil {
      journal.errorMessage = nil
    }

    // Step 12 — dirty-flag every expected record name.
    var dirtyRecordNames = expectedNames
    var flags = PendingUploadFlags.decode(state.pendingUploadFlags)
    for name in expectedNames {
      flags.markDirty(recordName: name)
    }

    // Step 13 — retroactively dirty-flag every existing
    // TripPersonSnapshot for the trip (Req 4.9). The Stage A backfill
    // created these against the pre-Phase-5.1 empty production state and
    // they have never been marked dirty for upload; entering Stage B is
    // their first opportunity to be sent. Step 12 already covers the
    // snapshots reachable through `trip.participantSnapshots`; this
    // step also flags any snapshot rows that exist for this trip ID but
    // aren't in the in-memory collection (defensive — both should be
    // identical, but the requirement is for "every snapshot row for
    // the trip").
    let snapshots = try tripsLocalContext.fetch(
      FetchDescriptor<TripPersonSnapshot>(
        predicate: #Predicate { $0.trip?.id == tripID }
      )
    )
    for snapshot in snapshots {
      let name = snapshot.id.uuidString
      flags.markDirty(recordName: name)
      dirtyRecordNames.insert(name)
    }
    state.pendingUploadFlags = flags.encode()

    // Step 14 — sequential saves; the @MainActor invocations do not
    // await between, so no engine event can interleave.
    try tripsLocalContext.save()
    try globalsContext.save()

    // Step 15 — signal the driver after both saves return. Use the
    // in-memory `dirtyRecordNames` set built above rather than re-
    // decoding the freshly-saved flags: encode/decode is value-
    // preserving today, but the driver contract is "queue everything
    // this run dirty-flagged", and that set lives in this stack frame.
    driver.saveZone(zoneID)
    let recordIDs = dirtyRecordNames.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
    if !recordIDs.isEmpty {
      driver.saveRecords(recordIDs)
    }
  }

  /// Phase 5.1 — copy a Trip + dependents from `globals` into
  /// `tripsLocal`, preserving every persisted field per Req 4.2.
  /// Commits `tripsLocalContext` so a subsequent crash leaves the trip
  /// duplicated rather than vanished — the resume branch will then
  /// detect the (both) quadrant and only re-run the delete step.
  ///
  /// Only `startOrResume` calls this; the (none, some) branch is the
  /// single production caller. The function tolerates being invoked
  /// against a trip that already exists in tripsLocal (no-op).
  private func relocateToTripsLocal(tripID: UUID) throws {
    guard let trip = try fetchTrip(tripID: tripID, in: globalsContext) else { return }

    // Bail out if a copy already exists (defence-in-depth against
    // double-invocation — the public callers all check the existence
    // quadrant first).
    if try fetchTrip(tripID: tripID, in: tripsLocalContext) != nil { return }

    let copiedTrip = Trip(
      id: trip.id,
      name: trip.name,
      startDate: trip.startDate,
      endDate: trip.endDate,
      attributes: trip.attributes
    )
    copiedTrip.tripZoneID = trip.tripZoneID
    copiedTrip.ckRecordSystemFields = trip.ckRecordSystemFields
    tripsLocalContext.insert(copiedTrip)

    for task in trip.tasks ?? [] {
      let copiedTask = TripTask(
        id: task.id,
        trip: copiedTrip,
        masterItemID: task.masterItemID,
        name: task.name,
        phase: task.phase,
        isCompleted: task.isCompleted,
        source: task.source,
        currentlyMatchesRules: task.currentlyMatchesRules,
        pinnedByUser: task.pinnedByUser,
        assigneePersonID: task.assigneePersonID,
        userDeletedOnThisTrip: task.userDeletedOnThisTrip
      )
      copiedTask.ckRecordSystemFields = task.ckRecordSystemFields
      tripsLocalContext.insert(copiedTask)
    }

    // Build snapshots first so packing items can reference them.
    var snapshotsByID: [UUID: TripPersonSnapshot] = [:]
    for snapshot in trip.participantSnapshots ?? [] {
      let copiedSnapshot = TripPersonSnapshot(
        id: snapshot.id,
        personID: snapshot.personID,
        name: snapshot.name,
        colourID: snapshot.colourID,
        initialSource: snapshot.initialSource,
        isRosterMember: snapshot.isRosterMember,
        trip: copiedTrip
      )
      copiedSnapshot.ckRecordSystemFields = snapshot.ckRecordSystemFields
      tripsLocalContext.insert(copiedSnapshot)
      snapshotsByID[snapshot.id] = copiedSnapshot
    }

    for item in trip.packingItems ?? [] {
      let mappedSnapshot = item.personSnapshot.flatMap { snapshotsByID[$0.id] }
      let copiedItem = TripPackingItem(
        id: item.id,
        trip: copiedTrip,
        person: nil,  // V2 relationship is latent in V3; not relocated.
        masterItemID: item.masterItemID,
        name: item.name,
        state: item.state,
        source: item.source,
        currentlyMatchesRules: item.currentlyMatchesRules,
        pinnedByUser: item.pinnedByUser,
        personSnapshot: mappedSnapshot
      )
      copiedItem.ckRecordSystemFields = item.ckRecordSystemFields
      tripsLocalContext.insert(copiedItem)
    }

    try tripsLocalContext.save()
  }

  /// Phase 5.1 — delete a Trip + dependents from `globals` after the
  /// relocation has committed in `tripsLocal`. The single
  /// `globalsContext.save()` is the resume-from-(both) step.
  private func deleteFromGlobals(tripID: UUID) throws {
    guard let trip = try fetchTrip(tripID: tripID, in: globalsContext) else { return }
    // SwiftData cascades `tasks` / `packingItems` (deleteRule .cascade)
    // and nullifies `participants`. Snapshots use `.nullify` — see Trip
    // declaration for the V3 cascade-traversal workaround — so delete
    // them explicitly first.
    for snapshot in trip.participantSnapshots ?? [] {
      globalsContext.delete(snapshot)
    }
    globalsContext.delete(trip)
    try globalsContext.save()
  }

  // swiftlint:enable cyclomatic_complexity function_body_length

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

  private func fetchTrip(tripID: UUID, in context: ModelContext) throws -> Trip? {
    let descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == tripID })
    return try context.fetch(descriptor).first
  }

  private func fetchJournal(tripID: UUID) -> MigrationJournalEntry? {
    let descriptor = FetchDescriptor<MigrationJournalEntry>(
      predicate: #Predicate { $0.tripID == tripID }
    )
    // Surface the fetch error rather than swallowing it; every event
    // handler that calls this then no-ops, which is indistinguishable
    // from "no journal exists" — masked migration stalls.
    do {
      return try globalsContext.fetch(descriptor).first
    } catch {
      let message = error.localizedDescription
      modelLogger.error(
        "[ZoneMigrationCoordinator] fetchJournal(\(tripID, privacy: .public)) failed: \(message, privacy: .public)"
      )
      return nil
    }
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
