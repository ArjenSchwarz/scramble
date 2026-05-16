import CloudKit
import Foundation
import Testing

@testable import Scramble

/// Throwaway validation harness for Decision 13 — confirm `CKSyncEngine` can drive
/// owner-side zone creation, record uploads, and a zone-wide `CKShare` end-to-end on
/// iOS 26 before the rest of Phase 5 is built on top of it. The acceptance gate is:
///
/// - **Owner-side, automated here:** a private `CKSyncEngine` creates a custom zone,
///   uploads a test record, and saves a `CKShare(recordZoneID:)`. The harness asserts
///   each step succeeds and prints the share URL.
/// - **Participant-side, manual:** copy the printed share URL to a second iCloud
///   account (a second device or another simulator), accept the share, then stand up
///   a shared-DB `CKSyncEngine` and confirm the test record arrives via
///   `fetchedRecordZoneChanges`. The pre-existing Apple sample app at
///   <https://github.com/apple/sample-cloudkit-sync-engine> is a fine reference for
///   the shared-DB delegate shape; this repository's own shared-DB engine doesn't
///   exist yet (that's the next tasks in this phase).
///
/// Pass/fail decides whether Decision 13 stands or we fall back to raw `CKDatabase`
/// (see `specs/phase-5-cloudkit-sharing/decision_log.md#decision-13`).
///
/// ### How to run
///
/// The suite is disabled by default so unit-test CI passes without iCloud. To run it
/// against the development CloudKit container:
///
/// 1. Sign the iOS Simulator (or your device) into an iCloud account that has access
///    to the development container `iCloud.me.nore.ig.scramble`.
/// 2. ```bash
///    SCRAMBLE_CK_HARNESS=1 make test-quick
///    ```
///    Or run from Xcode after setting the `SCRAMBLE_CK_HARNESS` environment variable
///    on the `ScrambleTests` scheme.
/// 3. The harness prints the share URL in the test log. Open it on the second
///    iCloud account and verify the trip zone records appear.
///
/// Once Decision 13 has been validated end-to-end, this file can be deleted — it is
/// not load-bearing for the production code path.
@Suite("CKSyncEngine validation harness", .enabled(if: CKSyncEngineHarness.isEnabled))
@MainActor
struct CKSyncEngineValidationHarnessSuite {

  @Test(
    "Owner can create zone, upload record, and save zone-wide CKShare via CKSyncEngine"
  )
  func ownerSideLifecycle() async throws {
    let container = CKContainer(identifier: "iCloud.me.nore.ig.scramble")

    let accountStatus = try await container.accountStatus()
    try #require(
      accountStatus == .available,
      "iCloud account is \(accountStatus); sign in before running the harness."
    )

    let harness = CKSyncEngineHarness(container: container)
    defer { harness.tearDownInBackground() }

    let zoneID = harness.makeUniqueZoneID()
    let recordID = CKRecord.ID(recordName: "harness-record", zoneID: zoneID)

    // Stage 1: create zone + upload one record.
    let testRecord = CKRecord(recordType: "HarnessProbe", recordID: recordID)
    testRecord["payload"] = "ok" as CKRecordValue
    harness.stage(record: testRecord)
    harness.scheduleZoneSave(zoneID: zoneID)
    harness.scheduleRecordSave(recordID: recordID)
    try await harness.engine.sendChanges()

    #expect(harness.didSaveZone(zoneID), "CKSyncEngine did not confirm zone save")
    #expect(harness.didSaveRecord(recordID), "CKSyncEngine did not confirm record save")

    // Stage 2: zone-wide share rooted in the same zone.
    let share = CKShare(recordZoneID: zoneID)
    share.publicPermission = .none
    harness.stage(record: share)
    harness.scheduleRecordSave(recordID: share.recordID)
    try await harness.engine.sendChanges()

    #expect(harness.didSaveRecord(share.recordID), "CKSyncEngine did not confirm CKShare save")

    if let savedShare = harness.savedShare(), let shareURL = savedShare.url {
      print("[CK harness] Zone: \(zoneID.zoneName)")
      print("[CK harness] Share URL (open on second account): \(shareURL)")
      print(
        "[CK harness] Then run a shared-DB CKSyncEngine on the second account and confirm "
          + "fetchedRecordZoneChanges delivers the HarnessProbe record."
      )
    } else {
      Issue.record("Share was saved but no URL was attached to the local copy")
    }
  }
}

/// Configuration + state for one harness run. Acts as the `CKSyncEngineDelegate`,
/// tracks pending records keyed by `CKRecord.ID`, and records the IDs the engine
/// confirms it sent.
@MainActor
final class CKSyncEngineHarness: NSObject {

  nonisolated static var isEnabled: Bool {
    ProcessInfo.processInfo.environment["SCRAMBLE_CK_HARNESS"] == "1"
  }

  let container: CKContainer
  let database: CKDatabase
  private(set) var engine: CKSyncEngine!
  private var pendingRecords: [CKRecord.ID: CKRecord] = [:]
  private var savedRecordIDs: Set<CKRecord.ID> = []
  private var savedZoneIDs: Set<CKRecordZone.ID> = []
  private var lastSavedShare: CKShare?

  init(container: CKContainer) {
    self.container = container
    self.database = container.privateCloudDatabase
    super.init()
    var configuration = CKSyncEngine.Configuration(
      database: database,
      stateSerialization: nil,
      delegate: self
    )
    configuration.automaticallySync = false
    self.engine = CKSyncEngine(configuration)
  }

  func makeUniqueZoneID() -> CKRecordZone.ID {
    // Unique per run so a previously-aborted harness run doesn't leave a name collision.
    let suffix = UUID().uuidString.prefix(8)
    return CKRecordZone.ID(
      zoneName: "scramble-harness-\(suffix)", ownerName: CKCurrentUserDefaultName)
  }

  func stage(record: CKRecord) {
    pendingRecords[record.recordID] = record
  }

  func scheduleZoneSave(zoneID: CKRecordZone.ID) {
    engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
  }

  func scheduleRecordSave(recordID: CKRecord.ID) {
    engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
  }

  func didSaveZone(_ zoneID: CKRecordZone.ID) -> Bool {
    savedZoneIDs.contains(zoneID)
  }

  func didSaveRecord(_ recordID: CKRecord.ID) -> Bool {
    savedRecordIDs.contains(recordID)
  }

  func savedShare() -> CKShare? {
    lastSavedShare
  }

  /// Schedules a zone-delete via the engine and forgets cached state. Errors during
  /// teardown are logged but don't fail the test — a stale dev zone is harmless.
  func tearDownInBackground() {
    let zoneIDs = savedZoneIDs
    Task { [database] in
      for zoneID in zoneIDs {
        do {
          _ = try await database.deleteRecordZone(withID: zoneID)
        } catch {
          // Best-effort; CloudKit Dashboard can be used to clean up if needed.
          print("[CK harness] Failed to delete zone \(zoneID): \(error)")
        }
      }
    }
  }
}

extension CKSyncEngineHarness: CKSyncEngineDelegate {

  nonisolated func handleEvent(
    _ event: CKSyncEngine.Event,
    syncEngine: CKSyncEngine
  ) async {
    switch event {
    case .sentRecordZoneChanges(let event):
      await self.recordSentRecordZoneChanges(event)
    case .sentDatabaseChanges(let event):
      await self.recordSentDatabaseChanges(event)
    case .stateUpdate, .accountChange,
      .fetchedDatabaseChanges, .fetchedRecordZoneChanges,
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
    let scope = context.options.scope
    let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
    let records = await self.snapshotPendingRecords()
    return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
      records[recordID]
    }
  }

  private func snapshotPendingRecords() -> [CKRecord.ID: CKRecord] {
    pendingRecords
  }

  private func recordSentRecordZoneChanges(_ event: CKSyncEngine.Event.SentRecordZoneChanges) {
    for saved in event.savedRecords {
      savedRecordIDs.insert(saved.recordID)
      if let share = saved as? CKShare {
        lastSavedShare = share
      }
    }
    for failed in event.failedRecordSaves {
      print(
        "[CK harness] record save failed: \(failed.record.recordID) — \(failed.error)"
      )
    }
  }

  private func recordSentDatabaseChanges(_ event: CKSyncEngine.Event.SentDatabaseChanges) {
    for zone in event.savedZones {
      savedZoneIDs.insert(zone.zoneID)
    }
    for failed in event.failedZoneSaves {
      print("[CK harness] zone save failed: \(failed.zone.zoneID) — \(failed.error)")
    }
  }
}
