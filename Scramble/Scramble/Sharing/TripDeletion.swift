import CloudKit
import Foundation
import SwiftData

/// Phase 5 / Phase 5.1 — owner-side trip deletion (Req 1.4, design §
/// "Trip-deletion ordering").
///
/// Performs the reverse-cascade order in a single transaction:
/// `packing items → tasks → snapshots → trip → TripZoneState`. The
/// explicit order avoids relying on SwiftData's cascade traversal, which
/// panics on iOS 26.4 once the snapshot ↔ packing-item nullify pair
/// enters the chain (persistence note "Trip.participantSnapshots is
/// one-way"). The owner variant also asks the supplied
/// `TripZoneDeleter` to enqueue a `deleteZone` on the private engine;
/// participants pass `nil` (they leave the share via
/// `CloudKitSharingService.leaveShare`, which already enqueues the
/// shared-DB zone deletion).
///
/// Phase 5.1 routes the single context save through
/// `LocalWriteHook.commitDeletion(_:zoneIDsBeingDeleted:)` so the
/// deleted record IDs reach the engine for `deleteRecord` operations
/// while the per-`TripZoneState` flag write is skipped for the
/// vanishing zone.
@MainActor
enum TripDeletion {

  /// Delete the trip and every record dependent on it in the documented
  /// reverse-cascade order, routing the commit through
  /// `LocalWriteHook.commitDeletion(_:zoneIDsBeingDeleted:)`. When
  /// `zoneDeleter` is supplied, the trip's `CKRecordZone` is also queued
  /// for deletion after the local commit succeeds.
  ///
  /// Idempotent — calling against a trip that no longer exists tears
  /// down any leftover `TripZoneState` row but otherwise no-ops.
  static func delete(
    tripID: UUID,
    in context: ModelContext,
    hook: LocalWriteHook,
    zoneDeleter: TripZoneDeleter? = nil
  ) throws {
    let zoneStates = try context.fetch(
      FetchDescriptor<TripZoneState>(predicate: #Predicate { $0.tripID == tripID })
    )
    let zoneIDs = zoneStates.map { TripZoneStateRecordTranslator.zoneID(for: $0) }
    let isOwnerScope =
      zoneStates.first?.zoneScope == "private"
      || zoneStates.first?.zoneOwnerName == CKCurrentUserDefaultName

    let trips = try context.fetch(
      FetchDescriptor<Trip>(predicate: #Predicate { $0.id == tripID })
    )

    if let trip = trips.first {
      for item in trip.packingItems ?? [] {
        context.delete(item)
      }
      for task in trip.tasks ?? [] {
        context.delete(task)
      }
      for snapshot in trip.participantSnapshots ?? [] {
        context.delete(snapshot)
      }
      context.delete(trip)
    }
    for state in zoneStates {
      context.delete(state)
    }

    try hook.commitDeletion(context, zoneIDsBeingDeleted: Set(zoneIDs))

    // Owner-side: ask the engine to remove the zone from CloudKit.
    if let zoneDeleter, isOwnerScope {
      for zoneID in zoneIDs {
        zoneDeleter.deleteZone(zoneID)
      }
    }
  }
}

/// Phase 5 — test seam for the zone-delete operation. Production wires
/// this to `TripSyncEngine.privateEngine.state.add(pendingDatabaseChanges:
/// [.deleteZone(zoneID)])`; tests use a recording fake.
@MainActor
protocol TripZoneDeleter: AnyObject {
  func deleteZone(_ zoneID: CKRecordZone.ID)
}

/// Production driver around `TripSyncEngine.privateEngine`.
@MainActor
final class TripSyncEngineZoneDeleter: TripZoneDeleter {
  let syncEngine: TripSyncEngine

  init(syncEngine: TripSyncEngine) {
    self.syncEngine = syncEngine
  }

  func deleteZone(_ zoneID: CKRecordZone.ID) {
    syncEngine.privateEngine?.state.add(
      pendingDatabaseChanges: [.deleteZone(zoneID)]
    )
  }
}
