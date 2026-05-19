import CloudKit
import Foundation

/// Phase 6 — multicast wrapper over `PendingChangeNotifier` (Decision 12).
///
/// `LocalWriteHook(notifier:)` accepts a single notifier; Phase 6 needs the
/// hook to drive both `TripSyncEngine` and `NotificationsService`. The
/// broadcaster sits at the notifier seam and forwards every
/// `notifyPendingChanges(...)` call to each registered child in
/// registration order.
///
/// Ownership: both `TripSyncEngine` and `NotificationsService` are owned
/// by `ScrambleApp` for the lifetime of the app; the broadcaster also
/// lives for the lifetime of the app. There is therefore no retain-cycle
/// concern that warrants weak storage — the broadcaster strongly holds
/// its children.
@MainActor
final class PendingChangeBroadcaster: PendingChangeNotifier {

  private var children: [any PendingChangeNotifier]

  init(children: [any PendingChangeNotifier]) {
    self.children = children
  }

  func add(_ child: any PendingChangeNotifier) {
    children.append(child)
  }

  func notifyPendingChanges(
    savedRecordIDs: [CKRecord.ID],
    deletedRecordIDs: [CKRecord.ID],
    in zoneID: CKRecordZone.ID
  ) {
    for child in children {
      child.notifyPendingChanges(
        savedRecordIDs: savedRecordIDs,
        deletedRecordIDs: deletedRecordIDs,
        in: zoneID
      )
    }
  }
}
