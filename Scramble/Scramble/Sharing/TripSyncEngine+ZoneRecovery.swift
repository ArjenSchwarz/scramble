import CloudKit
import Foundation

/// Pure zone-not-found recovery decisions for `TripSyncEngine`. Kept in a
/// separate file, free of engine/instance state, so the logic that decides
/// *what* to recover is unit-tested without a live `CKSyncEngine` (T-1670).
/// The side-effecting application (enqueue + emit) lives on `TripSyncEngine`
/// itself (`recoverFailedSaves`).
extension TripSyncEngine {
  /// Partition failed record saves. `.zoneNotFound` failures are
  /// recoverable — CKSyncEngine does **not** auto-create record zones, so
  /// a freshly-created trip's records are rejected until the zone exists;
  /// the fix is to create the zone and re-queue the records (Apple's
  /// sample handles this in the sent-changes callback). Every other error
  /// is a genuine failure that should surface via `.recordsFailed`.
  static func classifyFailedSaves(
    _ failures: [(recordID: CKRecord.ID, code: CKError.Code)]
  ) -> FailedSaveClassification {
    var result = FailedSaveClassification()
    for failure in failures {
      if failure.code == .zoneNotFound {
        result.zonesToCreate.insert(failure.recordID.zoneID)
        result.recordsToRetry.append(failure.recordID)
      } else {
        result.unrecoverable.append(failure.recordID)
      }
    }
    return result
  }

  /// Result of `classifyFailedSaves`: the zones to (re)create, the records
  /// to re-queue once they exist, and the genuinely-failed records.
  struct FailedSaveClassification: Equatable {
    var zonesToCreate: Set<CKRecordZone.ID> = []
    var recordsToRetry: [CKRecord.ID] = []
    var unrecoverable: [CKRecord.ID] = []
  }

  /// Decide zone-not-found recovery for a batch of failed record saves,
  /// applying the two safety gates the raw classification can't express
  /// (both live here, not in `handleSentChanges`, so they're unit-tested):
  ///
  /// - **Scope.** Only the private database recovers by creating a zone —
  ///   a participant cannot create a shared-DB zone it doesn't own, so a
  ///   `.zoneNotFound` there (e.g. the owner removed the zone) is terminal.
  /// - **Bounded attempts.** Recovery is optimistic: it re-queues records
  ///   without observing whether the `.saveZone` it depends on succeeded.
  ///   A zone that has already failed `maxAttempts` times stops retrying
  ///   and its records surface as failures, so a persistent zone-save
  ///   error can't loop forever (T-1670 Findings 1–3).
  ///
  /// Pure: `attemptedZones` are the zones whose per-zone counter the caller
  /// should increment. `zonesToCreate` are sorted for deterministic output.
  static func planZoneRecovery(
    failures: [(recordID: CKRecord.ID, code: CKError.Code)],
    scope: CKDatabase.Scope,
    attempts: [CKRecordZone.ID: Int],
    maxAttempts: Int
  ) -> ZoneRecoveryPlan {
    let classified = classifyFailedSaves(failures)
    var plan = ZoneRecoveryPlan()
    // Non-zoneNotFound errors are always genuine failures.
    plan.failedRecordIDs = classified.unrecoverable

    guard scope == .private else {
      plan.failedRecordIDs.append(contentsOf: classified.recordsToRetry)
      return plan
    }

    for zone in classified.zonesToCreate.sorted(by: { $0.zoneName < $1.zoneName }) {
      let zoneRecords = classified.recordsToRetry.filter { $0.zoneID == zone }
      if attempts[zone, default: 0] < maxAttempts {
        plan.attemptedZones.append(zone)
        plan.zonesToCreate.append(zone)
        plan.recordsToRetry.append(contentsOf: zoneRecords)
      } else {
        plan.failedRecordIDs.append(contentsOf: zoneRecords)
      }
    }
    return plan
  }

  /// Result of `planZoneRecovery`. `attemptedZones` ⊆ `zonesToCreate` and
  /// names the zones whose recovery-attempt counter should be bumped.
  struct ZoneRecoveryPlan: Equatable {
    var zonesToCreate: [CKRecordZone.ID] = []
    var recordsToRetry: [CKRecord.ID] = []
    var failedRecordIDs: [CKRecord.ID] = []
    var attemptedZones: [CKRecordZone.ID] = []
  }
}
