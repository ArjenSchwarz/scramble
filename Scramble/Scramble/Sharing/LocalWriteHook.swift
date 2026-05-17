import CloudKit
import Foundation
import SwiftData

/// Phase 5 chokepoint for every `tripsLocal` mutation (Decision 13).
///
/// Call sites (Trip CRUD, Tasks UI, Packing Sheet, rules engine, snapshot
/// maintenance) invoke `commit(_:)` rather than `context.save()` directly.
/// The hook inspects pending model changes, ORs the corresponding dirty
/// bits into the affected `TripZoneState.pendingUploadFlags`, persists the
/// context, and notifies the sync engine.
///
/// Direct `context.save()` on `tripsLocal` outside this hook is forbidden
/// (lint rule / code-review checklist item).
@MainActor
final class LocalWriteHook {
  /// Notifier the hook calls to wake the sync engine. Production wires
  /// this to `TripSyncEngine`; tests inject a recording fake.
  let notifier: PendingChangeNotifier

  init(notifier: PendingChangeNotifier) {
    self.notifier = notifier
  }

  /// Apply pending changes from `context` to the corresponding
  /// `TripZoneState` rows, save once, then notify the sync engine. Errors
  /// from `save()` propagate to the caller.
  func commit(_ context: ModelContext) throws {
    try commitChanges(in: context, zoneIDsBeingDeleted: [])
  }

  /// Phase 5.1 — same contract as `commit(_:)` but partitions changes by
  /// whether their mapped zone is in `zoneIDsBeingDeleted`. For records
  /// whose zone is vanishing in this same transaction, the per-
  /// `TripZoneState` flag update is skipped (the row is also being
  /// deleted); the notifier is still called with the deleted record IDs
  /// so the engine queues `deleteRecord` operations alongside the
  /// `deleteZone`. Records whose zone is not vanishing follow the
  /// regular `commit(_:)` path (flag update + notifier signal).
  ///
  /// Used by `TripDeletion.delete` so the entire reverse-cascade ends in
  /// a single chokepoint call.
  func commitDeletion(
    _ context: ModelContext,
    zoneIDsBeingDeleted: Set<CKRecordZone.ID>
  ) throws {
    try commitChanges(in: context, zoneIDsBeingDeleted: zoneIDsBeingDeleted)
  }

  // MARK: - Unified commit path

  private func commitChanges(
    in context: ModelContext,
    zoneIDsBeingDeleted: Set<CKRecordZone.ID>
  ) throws {
    let summary = collectChanges(in: context)
    // Partition by zoneName only (trip-{uuid}). The hook synthesises
    // zone IDs with `CKCurrentUserDefaultName`, but a participant
    // trip's `TripZoneState` carries the remote owner's name; matching
    // on full `CKRecordZone.ID` would misclassify those zones as
    // surviving and trigger a re-insert of the just-deleted
    // `TripZoneState` row inside `applyZoneChange`. Zone names are
    // owner-agnostic and unique per trip, so a name-only comparison
    // partitions correctly for both private-DB and shared-DB scopes.
    let vanishingZoneNames: Set<String> = Set(zoneIDsBeingDeleted.map(\.zoneName))

    // Step 1: update TripZoneState rows for surviving zones only. A
    // vanishing zone's TripZoneState row is in the same transaction's
    // deletedModelsArray; writing into it is wasted work and would
    // re-insert a fresh row.
    for change in summary.zoneChanges where !vanishingZoneNames.contains(change.zoneID.zoneName) {
      try applyZoneChange(change, in: context)
    }

    // Step 2: single save commits both the user mutations and the
    // freshly-stamped `TripZoneState.pendingUploadFlags`.
    try context.save()

    // Step 3: tell the engine which records to send / delete on the next
    // batch. Vanishing-zone records still notify so the engine queues
    // their `deleteRecord` operations alongside the `deleteZone`.
    for change in summary.zoneChanges {
      let recordIDs = change.dirtyRecordNames.map { recordName in
        CKRecord.ID(recordName: recordName, zoneID: change.zoneID)
      }
      let deletedIDs = change.deletedRecordNames.map { recordName in
        CKRecord.ID(recordName: recordName, zoneID: change.zoneID)
      }
      notifier.notifyPendingChanges(
        savedRecordIDs: recordIDs,
        deletedRecordIDs: deletedIDs,
        in: change.zoneID
      )
    }
  }

  // MARK: - Internal collection

  private struct ZoneChange {
    let zoneID: CKRecordZone.ID
    let tripID: UUID
    var dirtyRecordNames: Set<String> = []
    var deletedRecordNames: Set<String> = []
  }

  private struct ChangeSummary {
    var zoneChanges: [ZoneChange] = []
  }

  private func collectChanges(in context: ModelContext) -> ChangeSummary {
    var byTripID: [UUID: ZoneChange] = [:]

    func touch(tripID: UUID, recordName: String, deleted: Bool) {
      let zoneID = CKRecordZone.ID(
        zoneName: "trip-\(tripID.uuidString)",
        ownerName: CKCurrentUserDefaultName
      )
      var change = byTripID[tripID] ?? ZoneChange(zoneID: zoneID, tripID: tripID)
      if deleted {
        change.deletedRecordNames.insert(recordName)
      } else {
        change.dirtyRecordNames.insert(recordName)
      }
      byTripID[tripID] = change
    }

    let inserted = context.insertedModelsArray
    let changed = context.changedModelsArray
    let deleted = context.deletedModelsArray

    for model in inserted {
      if let entry = mapping(for: model) {
        touch(tripID: entry.tripID, recordName: entry.recordName, deleted: false)
      }
    }
    for model in changed {
      if let entry = mapping(for: model) {
        touch(tripID: entry.tripID, recordName: entry.recordName, deleted: false)
      }
    }
    for model in deleted {
      if let entry = mapping(for: model) {
        touch(tripID: entry.tripID, recordName: entry.recordName, deleted: true)
      }
    }

    return ChangeSummary(zoneChanges: Array(byTripID.values))
  }

  private struct ChangeMapping {
    let tripID: UUID
    let recordName: String
  }

  private func mapping(for model: any PersistentModel) -> ChangeMapping? {
    if let trip = model as? Trip {
      return ChangeMapping(tripID: trip.id, recordName: trip.id.uuidString)
    }
    if let task = model as? TripTask {
      guard let tripID = task.trip?.id else { return nil }
      return ChangeMapping(tripID: tripID, recordName: task.id.uuidString)
    }
    if let item = model as? TripPackingItem {
      guard let tripID = item.trip?.id else { return nil }
      return ChangeMapping(tripID: tripID, recordName: item.id.uuidString)
    }
    if let snapshot = model as? TripPersonSnapshot {
      guard let tripID = snapshot.trip?.id else { return nil }
      return ChangeMapping(tripID: tripID, recordName: snapshot.id.uuidString)
    }
    // TripZoneState mutations are local-only — they should not feed back
    // into the sync engine. Person / Master* live in globals.
    return nil
  }

  private func applyZoneChange(_ change: ZoneChange, in context: ModelContext) throws {
    let tripID = change.tripID
    let descriptor = FetchDescriptor<TripZoneState>(predicate: #Predicate { $0.tripID == tripID })
    let state =
      try context.fetch(descriptor).first
      ?? insertZoneState(for: change, in: context)
    var flags = PendingUploadFlags.decode(state.pendingUploadFlags)
    for name in change.dirtyRecordNames { flags.markDirty(recordName: name) }
    for name in change.deletedRecordNames { flags.markDeleted(recordName: name) }
    state.pendingUploadFlags = flags.encode()
  }

  private func insertZoneState(
    for change: ZoneChange,
    in context: ModelContext
  ) -> TripZoneState {
    let state = TripZoneState(
      tripID: change.tripID,
      zoneOwnerName: change.zoneID.ownerName,
      zoneScope: change.zoneID.ownerName == CKCurrentUserDefaultName ? "private" : "shared"
    )
    context.insert(state)
    return state
  }
}

// MARK: - Sync engine seam

/// Notification hook that `LocalWriteHook` calls after a successful save.
/// Production wiring is `TripSyncEngine`; the test target injects a fake
/// that records its calls (Decision 13).
@MainActor
protocol PendingChangeNotifier: AnyObject {
  func notifyPendingChanges(
    savedRecordIDs: [CKRecord.ID],
    deletedRecordIDs: [CKRecord.ID],
    in zoneID: CKRecordZone.ID
  )
}
