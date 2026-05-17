import CloudKit
import Foundation
import SwiftData
import os

/// Façade around the two `CKSyncEngine` instances Phase 5 relies on:
/// `privateEngine` for owner-side trip zones and `sharedEngine` for
/// participant-accepted zones (Decision 13).
///
/// The bulk of the testable logic lives in pure-Swift helpers
/// (`buildBatch(scope:pendingChanges:)`, `apply(fetchedRecords:)`,
/// `apply(deletedRecordIDs:)`, `recordSelfOriginated(_:)` /
/// `wasSelfOriginated(_:)`). The `CKSyncEngine`-driven IO layer is
/// constructed via `start()`; tests that only need the helpers can
/// instantiate the engine without ever calling `start()`.
@MainActor
final class TripSyncEngine: NSObject, PendingChangeNotifier {
  /// JSONEncoder/Decoder for `CKSyncEngine.State.Serialization` blobs.
  /// Hoisted to `static let` because state writes fire on every engine
  /// event; reallocating per call is hot-path overhead.
  private static let stateEncoder = JSONEncoder()
  private static let stateDecoder = JSONDecoder()

  /// Local cache of trip-zone entities. The engine reads from this on
  /// `nextRecordZoneChangeBatch` and writes into it on `handleEvent`.
  let context: ModelContext
  let container: CKContainer
  let stateStore: TripSyncStateStore

  private(set) var privateEngine: CKSyncEngine?
  private(set) var sharedEngine: CKSyncEngine?

  /// Echo guard. Records the record IDs the engine has just sent so the
  /// next inbound `fetchedRecordZoneChanges` carrying the same IDs is
  /// flagged `isSelfOriginated`. Bounded; entries age out once
  /// `wasSelfOriginated(_:)` consumes them.
  private var sentRecordIDs: Set<CKRecord.ID> = []

  /// Outbound `CKShare` instances waiting to be returned by the engine's
  /// record provider. `CKShare` doesn't live in SwiftData, so the
  /// translator-based `encodeRecord(for:scope:)` path can't reconstruct
  /// it — the actual instance has to be cached here from
  /// `enqueueShareSave(_:)` until `handleSentChanges` confirms upload.
  private var pendingShares: [CKRecord.ID: CKShare] = [:]

  let events: AsyncStream<TripSyncEvent>
  private let eventContinuation: AsyncStream<TripSyncEvent>.Continuation

  init(
    context: ModelContext,
    container: CKContainer,
    stateStore: TripSyncStateStore = FileTripSyncStateStore()
  ) {
    self.context = context
    self.container = container
    self.stateStore = stateStore
    var continuation: AsyncStream<TripSyncEvent>.Continuation!
    self.events = AsyncStream { continuation = $0 }
    self.eventContinuation = continuation
    super.init()
  }

  /// Construct both `CKSyncEngine` instances and (re)hydrate them from
  /// the persisted state blobs. Decode failures discard the corrupt blob
  /// and request a full `fetchChanges()` so the local cache reconverges
  /// against server truth.
  func start() {
    privateEngine = makeEngine(for: .private)
    sharedEngine = makeEngine(for: .shared)
  }

  private func makeEngine(for scope: CKDatabase.Scope) -> CKSyncEngine {
    let database: CKDatabase
    switch scope {
    case .private: database = container.privateCloudDatabase
    case .shared: database = container.sharedCloudDatabase
    case .public: database = container.publicCloudDatabase
    @unknown default: database = container.privateCloudDatabase
    }
    let stateBlob = loadStateBlob(for: scope)
    var configuration = CKSyncEngine.Configuration(
      database: database,
      stateSerialization: stateBlob,
      delegate: self
    )
    configuration.automaticallySync = true
    let engine = CKSyncEngine(configuration)
    if stateBlob == nil {
      // Either there was no prior state, or it was corrupt and discarded.
      // Either way, queue a full reconciliation so we don't miss changes
      // the engine would otherwise have learned about via stored tokens.
      engine.state.add(pendingDatabaseChanges: [])
    }
    return engine
  }

  /// Best-effort load of the persisted state blob, with corruption
  /// recovery: a non-decodable blob is logged, cleared from the store,
  /// and `nil` is returned so the engine starts fresh.
  func loadStateBlob(for scope: CKDatabase.Scope) -> CKSyncEngine.State.Serialization? {
    guard let data = stateStore.loadState(for: scope) else { return nil }
    do {
      let decoded = try Self.stateDecoder.decode(
        CKSyncEngine.State.Serialization.self,
        from: data
      )
      return decoded
    } catch {
      let scopeLabel = String(describing: scope)
      let message = error.localizedDescription
      modelLogger.error(
        "[TripSyncEngine] state decode failed for scope \(scopeLabel, privacy: .public); discarding: \(message, privacy: .public)"
      )
      try? stateStore.clearState(for: scope)
      return nil
    }
  }

  // MARK: - Pure helpers (testable without CKSyncEngine instances)

  /// Build a `RecordZoneChangeBatch` from `tripsLocal`'s
  /// `TripZoneState.pendingUploadFlags` for the records the engine asked
  /// about. Returns `nil` when there is nothing to send.
  func buildBatch(
    scope: CKDatabase.Scope,
    pendingRecordIDs: [CKRecord.ID]
  ) -> [PendingRecordChange] {
    guard !pendingRecordIDs.isEmpty else { return [] }
    var batch: [PendingRecordChange] = []
    for recordID in pendingRecordIDs {
      let record = encodeRecord(for: recordID, scope: scope)
      if let record {
        batch.append(.save(recordID: recordID, record: record))
      }
    }
    return batch
  }

  private func encodeRecord(
    for recordID: CKRecord.ID,
    scope: CKDatabase.Scope
  ) -> CKRecord? {
    // CKShare instances are cached in `pendingShares` because they are
    // not backed by SwiftData and cannot be reconstructed from the local
    // store. Return the cached instance unmodified; CloudKit accepts it
    // and the engine then surfaces the save via `sentRecordZoneChanges`.
    if let share = pendingShares[recordID] { return share }
    guard let recordUUID = UUID(uuidString: recordID.recordName) else { return nil }
    // Trip
    if let trip = try? context.fetch(
      FetchDescriptor<Trip>(predicate: #Predicate { $0.id == recordUUID })
    ).first {
      let existing = trip.ckRecordSystemFields.flatMap { decodeSystemFields(from: $0) }
      return try? TripRecordTranslator.toRecord(trip, in: recordID.zoneID, existing: existing)
    }
    // TripTask
    if let task = try? context.fetch(
      FetchDescriptor<TripTask>(predicate: #Predicate { $0.id == recordUUID })
    ).first {
      let existing = task.ckRecordSystemFields.flatMap { decodeSystemFields(from: $0) }
      return try? TripTaskRecordTranslator.toRecord(task, in: recordID.zoneID, existing: existing)
    }
    // TripPackingItem
    if let item = try? context.fetch(
      FetchDescriptor<TripPackingItem>(predicate: #Predicate { $0.id == recordUUID })
    ).first {
      let existing = item.ckRecordSystemFields.flatMap { decodeSystemFields(from: $0) }
      return try? TripPackingItemRecordTranslator.toRecord(
        item, in: recordID.zoneID, existing: existing)
    }
    // TripPersonSnapshot
    if let snapshot = try? context.fetch(
      FetchDescriptor<TripPersonSnapshot>(predicate: #Predicate { $0.id == recordUUID })
    ).first {
      let existing = snapshot.ckRecordSystemFields.flatMap { decodeSystemFields(from: $0) }
      return try? TripPersonSnapshotRecordTranslator.toRecord(
        snapshot, in: recordID.zoneID, existing: existing)
    }
    return nil
  }

  /// Apply fetched records to the local store via the matching translator.
  /// Each record dispatches by `recordType`. Unknown types are logged and
  /// skipped — the spec policy is "tolerate older clients" (Decision 13).
  /// Per-record translator failures are logged and the loop continues so
  /// one malformed record can't strand the rest of an inbound batch.
  /// CKSyncEngine considers an event "delivered" once `handleEvent`
  /// returns, so the only safe behaviour is to commit the records we
  /// successfully translated.
  func apply(fetchedRecords: [CKRecord]) throws {
    for record in fetchedRecords {
      do {
        try apply(record)
      } catch {
        let type = record.recordType
        let name = record.recordID.recordName
        let message = error.localizedDescription
        modelLogger.error(
          "[TripSyncEngine] apply(record) failed for \(type, privacy: .public) \(name, privacy: .public): \(message, privacy: .public)"
        )
      }
    }
    try context.save()
  }

  private func apply(_ record: CKRecord) throws {
    switch record.recordType {
    case TripRecordTranslator.recordType:
      try TripRecordTranslator.from(record, into: context)
    case TripTaskRecordTranslator.recordType:
      try TripTaskRecordTranslator.from(record, into: context)
    case TripPackingItemRecordTranslator.recordType:
      try TripPackingItemRecordTranslator.from(record, into: context)
    case TripPersonSnapshotRecordTranslator.recordType:
      try TripPersonSnapshotRecordTranslator.from(record, into: context)
    default:
      if let share = record as? CKShare {
        try TripZoneStateRecordTranslator.from(share, into: context)
      } else {
        modelLogger.error(
          "[TripSyncEngine] Unknown record type: \(record.recordType, privacy: .public)"
        )
      }
    }
  }

  /// Apply server-side deletions to the local store. Looks up the records
  /// by `recordName` in one fetch per entity type and deletes the matches.
  /// Skips entries whose record name doesn't parse as a UUID.
  func apply(deletedRecordIDs: [CKRecord.ID]) throws {
    let ids = Set(deletedRecordIDs.compactMap { UUID(uuidString: $0.recordName) })
    guard !ids.isEmpty else { return }

    let trips = try context.fetch(
      FetchDescriptor<Trip>(predicate: #Predicate { ids.contains($0.id) })
    )
    let foundTripIDs = Set(trips.map(\.id))
    for trip in trips { context.delete(trip) }

    let remaining = ids.subtracting(foundTripIDs)
    if !remaining.isEmpty {
      let tasks = try context.fetch(
        FetchDescriptor<TripTask>(predicate: #Predicate { remaining.contains($0.id) })
      )
      for task in tasks { context.delete(task) }

      let items = try context.fetch(
        FetchDescriptor<TripPackingItem>(predicate: #Predicate { remaining.contains($0.id) })
      )
      for item in items { context.delete(item) }

      let snapshots = try context.fetch(
        FetchDescriptor<TripPersonSnapshot>(predicate: #Predicate { remaining.contains($0.id) })
      )
      for snapshot in snapshots { context.delete(snapshot) }
    }

    try context.save()
  }

  // MARK: - Share record outbound

  /// Queue a `CKShare` for upload on the private engine. The share is
  /// cached in `pendingShares` so the record provider can return the
  /// actual instance when CloudKit asks for it; once the send is
  /// confirmed via `sentRecordZoneChanges` the cache entry is dropped.
  func enqueueShareSave(_ share: CKShare) {
    pendingShares[share.recordID] = share
    privateEngine?.state.add(
      pendingRecordZoneChanges: [.saveRecord(share.recordID)]
    )
    markSelfOriginated([share.recordID])
  }

  // MARK: - Self-origination tracking

  func markSelfOriginated(_ recordIDs: [CKRecord.ID]) {
    for id in recordIDs {
      sentRecordIDs.insert(id)
    }
  }

  /// Returns true (and clears the entry) when `recordID` was just sent
  /// by this engine. Used by `handleEvent` to flag echoed
  /// `fetchedRecordZoneChanges` so the rules engine doesn't re-trigger
  /// on its own writes.
  func wasSelfOriginated(_ recordID: CKRecord.ID) -> Bool {
    if sentRecordIDs.contains(recordID) {
      sentRecordIDs.remove(recordID)
      return true
    }
    return false
  }

  // MARK: - PendingChangeNotifier

  /// `LocalWriteHook` calls this after a successful save. We forward the
  /// record IDs to the appropriate engine's pending-changes queue and
  /// remember them as self-originated so the inbound echo is filtered.
  func notifyPendingChanges(
    savedRecordIDs: [CKRecord.ID],
    deletedRecordIDs: [CKRecord.ID],
    in zoneID: CKRecordZone.ID
  ) {
    let scope = scope(for: zoneID)
    let engine = engine(for: scope)
    let saves: [CKSyncEngine.PendingRecordZoneChange] = savedRecordIDs.map { .saveRecord($0) }
    let deletes: [CKSyncEngine.PendingRecordZoneChange] = deletedRecordIDs.map {
      .deleteRecord($0)
    }
    engine?.state.add(pendingRecordZoneChanges: saves + deletes)
    markSelfOriginated(savedRecordIDs + deletedRecordIDs)
  }

  /// Read the cached `TripZoneState.zoneScope` for the given zone to
  /// decide which engine handles it. Defaults to `.private` for unknown
  /// zones (owner-side new-trip case).
  func scope(for zoneID: CKRecordZone.ID) -> CKDatabase.Scope {
    guard let tripID = ZoneMigrationCoordinator.parseTripID(from: zoneID.zoneName)
    else { return .private }
    let descriptor = FetchDescriptor<TripZoneState>(
      predicate: #Predicate { $0.tripID == tripID }
    )
    let match = (try? context.fetch(descriptor))?.first
    return match?.zoneScope == "shared" ? .shared : .private
  }

  func engine(for scope: CKDatabase.Scope) -> CKSyncEngine? {
    switch scope {
    case .private: return privateEngine
    case .shared: return sharedEngine
    case .public: return nil
    @unknown default: return nil
    }
  }

  // MARK: - Event publishing

  func emit(_ event: TripSyncEvent) {
    eventContinuation.yield(event)
  }
}

// MARK: - Public types

/// Production sync events. The `isSelfOriginated` flag on `.zoneChanged`
/// satisfies the design's owner-side echo guard
/// (design § "engine ownership gate").
enum TripSyncEvent: Sendable {
  case zoneChanged(CKRecordZone.ID, scope: CKDatabase.Scope, isSelfOriginated: Bool)
  case recordsFetched([CKRecord], in: CKRecordZone.ID)
  case shareAccepted(CKRecordZone.ID, ownerName: String)
  case zoneRemoved(CKRecordZone.ID)
  case error(String)
}

/// Pure-Swift sketch of a pending change the engine should send. Used by
/// `buildBatch(scope:pendingRecordIDs:)` so tests can assert on what
/// would be sent without constructing a real
/// `CKSyncEngine.RecordZoneChangeBatch`.
enum PendingRecordChange: Equatable {
  case save(recordID: CKRecord.ID, record: CKRecord)
  case delete(recordID: CKRecord.ID)
}

// MARK: - CKSyncEngineDelegate

extension TripSyncEngine: CKSyncEngineDelegate {
  nonisolated func handleEvent(
    _ event: CKSyncEngine.Event,
    syncEngine: CKSyncEngine
  ) async {
    let scope = syncEngine.database.databaseScope
    switch event {
    case .stateUpdate(let stateEvent):
      await persistState(stateEvent.stateSerialization, scope: scope)
    case .fetchedRecordZoneChanges(let event):
      await handleFetchedChanges(event, scope: scope)
    case .sentRecordZoneChanges(let event):
      await handleSentChanges(event, scope: scope)
    case .accountChange, .fetchedDatabaseChanges, .sentDatabaseChanges,
      .willFetchChanges, .willFetchRecordZoneChanges,
      .didFetchRecordZoneChanges, .didFetchChanges,
      .willSendChanges, .didSendChanges:
      break
    @unknown default:
      break
    }
  }

  nonisolated func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext,
    syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    let scope = syncEngine.database.databaseScope
    let pending = syncEngine.state.pendingRecordZoneChanges.filter {
      context.options.scope.contains($0)
    }
    let saveIDs: [CKRecord.ID] = pending.compactMap {
      if case .saveRecord(let id) = $0 { return id } else { return nil }
    }
    let recordsByID = await self.buildRecordsByID(saveIDs: saveIDs, scope: scope)
    return await CKSyncEngine.RecordZoneChangeBatch(
      pendingChanges: pending,
      recordProvider: { recordID in
        recordsByID[recordID]
      }
    )
  }

  private func buildRecordsByID(
    saveIDs: [CKRecord.ID],
    scope: CKDatabase.Scope
  ) -> [CKRecord.ID: CKRecord] {
    var map: [CKRecord.ID: CKRecord] = [:]
    for id in saveIDs {
      if let record = encodeRecord(for: id, scope: scope) {
        map[id] = record
      }
    }
    return map
  }

  private func persistState(
    _ serialization: CKSyncEngine.State.Serialization,
    scope: CKDatabase.Scope
  ) {
    do {
      let data = try Self.stateEncoder.encode(serialization)
      try stateStore.saveState(data, for: scope)
    } catch {
      modelLogger.error(
        "[TripSyncEngine] Failed to persist state for scope \(String(describing: scope)): \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func handleFetchedChanges(
    _ event: CKSyncEngine.Event.FetchedRecordZoneChanges,
    scope: CKDatabase.Scope
  ) {
    let modifications = event.modifications.map(\.record)
    do {
      try apply(fetchedRecords: modifications)
    } catch {
      emit(.error("Apply fetched failed: \(error.localizedDescription)"))
    }
    let deletedIDs = event.deletions.map(\.recordID)
    do {
      try apply(deletedRecordIDs: deletedIDs)
    } catch {
      emit(.error("Apply deletions failed: \(error.localizedDescription)"))
    }

    // Emit one zoneChanged event per affected zone, with isSelfOriginated
    // set when every record in the event was just sent by this engine.
    let zoneIDs = Set(modifications.map(\.recordID.zoneID) + deletedIDs.map(\.zoneID))
    for zoneID in zoneIDs {
      let zoneRecordIDs =
        modifications.filter { $0.recordID.zoneID == zoneID }.map(\.recordID)
        + deletedIDs.filter { $0.zoneID == zoneID }
      // Consume every ID before reducing — `allSatisfy` short-circuits on
      // the first false, which would leak any self-originated IDs that
      // followed it in `sentRecordIDs`.
      let consumed = zoneRecordIDs.map { wasSelfOriginated($0) }
      let isSelf = consumed.allSatisfy { $0 }
      emit(.zoneChanged(zoneID, scope: scope, isSelfOriginated: isSelf))
      if !modifications.isEmpty {
        let zoneRecords = modifications.filter { $0.recordID.zoneID == zoneID }
        if !zoneRecords.isEmpty {
          emit(.recordsFetched(zoneRecords, in: zoneID))
        }
      }
    }
  }

  private func handleSentChanges(
    _ event: CKSyncEngine.Event.SentRecordZoneChanges,
    scope: CKDatabase.Scope
  ) {
    // Re-cache system fields on every record we just successfully sent
    // so the next outbound batch starts from the server's view. Bucket by
    // record type so each entity is fetched once per batch instead of
    // once per record.
    var buckets: [String: [(UUID, Data)]] = [:]
    for saved in event.savedRecords {
      // Drop the cached share now that CloudKit has acknowledged the
      // save — the next createShare on the same trip will surface a new
      // CKShare from the service.
      pendingShares.removeValue(forKey: saved.recordID)
      guard let id = UUID(uuidString: saved.recordID.recordName) else { continue }
      buckets[saved.recordType, default: []].append((id, encodeSystemFields(of: saved)))
    }
    for (recordType, entries) in buckets {
      try? cacheSentSystemFields(recordType: recordType, entries: entries)
    }
    try? context.save()
  }

  private func cacheSentSystemFields(
    recordType: String,
    entries: [(UUID, Data)]
  ) throws {
    let ids = Set(entries.map(\.0))
    // Last write wins if CKSyncEngine ever surfaces duplicate record IDs
    // in a single event — preferable to a trap.
    let encodedByID = Dictionary(entries, uniquingKeysWith: { _, new in new })
    switch recordType {
    case TripRecordTranslator.recordType:
      let matches = try context.fetch(
        FetchDescriptor<Trip>(predicate: #Predicate { ids.contains($0.id) })
      )
      for trip in matches { trip.ckRecordSystemFields = encodedByID[trip.id] }
    case TripTaskRecordTranslator.recordType:
      let matches = try context.fetch(
        FetchDescriptor<TripTask>(predicate: #Predicate { ids.contains($0.id) })
      )
      for task in matches { task.ckRecordSystemFields = encodedByID[task.id] }
    case TripPackingItemRecordTranslator.recordType:
      let matches = try context.fetch(
        FetchDescriptor<TripPackingItem>(predicate: #Predicate { ids.contains($0.id) })
      )
      for item in matches { item.ckRecordSystemFields = encodedByID[item.id] }
    case TripPersonSnapshotRecordTranslator.recordType:
      let matches = try context.fetch(
        FetchDescriptor<TripPersonSnapshot>(predicate: #Predicate { ids.contains($0.id) })
      )
      for snapshot in matches { snapshot.ckRecordSystemFields = encodedByID[snapshot.id] }
    default:
      break
    }
  }
}
