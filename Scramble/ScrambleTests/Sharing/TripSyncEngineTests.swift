import CloudKit
import Foundation
import SwiftData
import Testing

@testable import Scramble

@Suite("TripSyncEngine", .serialized)
@MainActor
struct TripSyncEngineTests {

  // MARK: - buildBatch via translators

  @Test("buildBatch encodes a Trip via the matching translator and includes it in the result")
  func buildBatchEncodesTrip() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let engine = TripSyncEngine(
      context: context,
      container: CKContainer(identifier: "iCloud.test"),
      stateStore: InMemoryTripSyncStateStore()
    )

    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    context.insert(trip)
    try context.save()

    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    let recordID = CKRecord.ID(recordName: trip.id.uuidString, zoneID: zoneID)

    let pending = engine.buildBatch(scope: .private, pendingRecordIDs: [recordID])
    #expect(pending.count == 1)
    if case .save(let resultRecordID, let record) = pending.first! {
      #expect(resultRecordID == recordID)
      #expect(record.recordType == TripRecordTranslator.recordType)
      #expect(record["name"] as? String == "T")
    } else {
      Issue.record("Expected .save in pending batch")
    }
  }

  @Test("buildBatch silently skips record IDs with no matching local row")
  func buildBatchSkipsUnknownRecord() throws {
    let container = try Self.makeContainer()
    let engine = TripSyncEngine(
      context: container.mainContext,
      container: CKContainer(identifier: "iCloud.test"),
      stateStore: InMemoryTripSyncStateStore()
    )
    let zoneID = CKRecordZone.ID(zoneName: "trip-x", ownerName: CKCurrentUserDefaultName)
    let unknownID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)

    let pending = engine.buildBatch(scope: .private, pendingRecordIDs: [unknownID])
    #expect(pending.isEmpty)
  }

  // MARK: - apply(fetchedRecords:)

  @Test("apply(fetchedRecords:) routes Trip records through TripRecordTranslator")
  func applyFetchedRoutesTripRecord() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let engine = TripSyncEngine(
      context: context,
      container: CKContainer(identifier: "iCloud.test"),
      stateStore: InMemoryTripSyncStateStore()
    )

    let zoneID = CKRecordZone.ID(zoneName: "trip-x", ownerName: CKCurrentUserDefaultName)
    let id = UUID()
    let record = CKRecord(
      recordType: TripRecordTranslator.recordType,
      recordID: CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    )
    record["name"] = "Iceland" as CKRecordValue

    try engine.apply(fetchedRecords: [record])

    let stored = try context.fetch(FetchDescriptor<Trip>())
    #expect(stored.first?.name == "Iceland")
  }

  // MARK: - Self-origination

  @Test("markSelfOriginated then wasSelfOriginated returns true once and clears the entry")
  func selfOriginatedConsumesEntry() throws {
    let container = try Self.makeContainer()
    let engine = TripSyncEngine(
      context: container.mainContext,
      container: CKContainer(identifier: "iCloud.test"),
      stateStore: InMemoryTripSyncStateStore()
    )
    let zoneID = CKRecordZone.ID(zoneName: "trip-x", ownerName: CKCurrentUserDefaultName)
    let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)

    engine.markSelfOriginated([recordID])
    #expect(engine.wasSelfOriginated(recordID) == true)
    #expect(engine.wasSelfOriginated(recordID) == false, "Entry must clear on first read")
  }

  // MARK: - State corruption recovery

  @Test("loadStateBlob discards corrupt state and clears it from the store")
  func corruptStateDiscarded() throws {
    let container = try Self.makeContainer()
    let store = InMemoryTripSyncStateStore()
    store.returnCorruptDataForScopes = [.private]
    let engine = TripSyncEngine(
      context: container.mainContext,
      container: CKContainer(identifier: "iCloud.test"),
      stateStore: store
    )

    let result = engine.loadStateBlob(for: .private)
    #expect(result == nil)
    #expect(store.clearedScopes.contains(.private))
  }

  @Test("loadStateBlob returns nil when no state file exists")
  func missingStateReturnsNil() throws {
    let container = try Self.makeContainer()
    let engine = TripSyncEngine(
      context: container.mainContext,
      container: CKContainer(identifier: "iCloud.test"),
      stateStore: InMemoryTripSyncStateStore()
    )
    #expect(engine.loadStateBlob(for: .private) == nil)
  }

  // MARK: - PendingChangeNotifier wiring (LocalWriteHook handoff)

  @Test("notifyPendingChanges marks each saved record ID as self-originated")
  func notifyPendingChangesMarksSelfOriginated() throws {
    let container = try Self.makeContainer()
    let engine = TripSyncEngine(
      context: container.mainContext,
      container: CKContainer(identifier: "iCloud.test"),
      stateStore: InMemoryTripSyncStateStore()
    )
    let zoneID = CKRecordZone.ID(zoneName: "trip-x", ownerName: CKCurrentUserDefaultName)
    let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)
    engine.notifyPendingChanges(
      savedRecordIDs: [recordID],
      deletedRecordIDs: [],
      in: zoneID
    )
    #expect(engine.wasSelfOriginated(recordID))
  }

  // MARK: - Zone-not-found recovery (T-1670)

  @Test("classifyFailedSaves routes zoneNotFound to zone-create + retry, other errors to unrecoverable")
  func classifyFailedSavesPartitions() {
    let zoneA = CKRecordZone.ID(zoneName: "trip-a", ownerName: CKCurrentUserDefaultName)
    let zoneB = CKRecordZone.ID(zoneName: "trip-b", ownerName: CKCurrentUserDefaultName)
    let missing1 = CKRecord.ID(recordName: "r1", zoneID: zoneA)
    let missing2 = CKRecord.ID(recordName: "r2", zoneID: zoneA)
    let missing3 = CKRecord.ID(recordName: "r3", zoneID: zoneB)
    let conflict = CKRecord.ID(recordName: "r4", zoneID: zoneB)

    let result = TripSyncEngine.classifyFailedSaves([
      (missing1, .zoneNotFound),
      (missing2, .zoneNotFound),
      (missing3, .zoneNotFound),
      (conflict, .serverRecordChanged),
    ])

    #expect(result.zonesToCreate == [zoneA, zoneB])
    #expect(Set(result.recordsToRetry) == [missing1, missing2, missing3])
    #expect(result.unrecoverable == [conflict])
  }

  @Test("classifyFailedSaves with no zoneNotFound leaves everything unrecoverable")
  func classifyFailedSavesNoRecovery() {
    let zone = CKRecordZone.ID(zoneName: "trip-a", ownerName: CKCurrentUserDefaultName)
    let record = CKRecord.ID(recordName: "r1", zoneID: zone)
    let result = TripSyncEngine.classifyFailedSaves([(record, .networkUnavailable)])
    #expect(result.zonesToCreate.isEmpty)
    #expect(result.recordsToRetry.isEmpty)
    #expect(result.unrecoverable == [record])
  }

  @Test("planZoneRecovery on the private DB creates the zone and re-queues its records")
  func planZoneRecoveryPrivateFresh() {
    let zone = CKRecordZone.ID(zoneName: "trip-a", ownerName: CKCurrentUserDefaultName)
    let r1 = CKRecord.ID(recordName: "r1", zoneID: zone)
    let r2 = CKRecord.ID(recordName: "r2", zoneID: zone)
    let plan = TripSyncEngine.planZoneRecovery(
      failures: [(r1, .zoneNotFound), (r2, .zoneNotFound)],
      scope: .private, attempts: [:], maxAttempts: 3
    )
    #expect(plan.zonesToCreate == [zone])
    #expect(Set(plan.recordsToRetry) == [r1, r2])
    #expect(plan.attemptedZones == [zone])
    #expect(plan.failedRecordIDs.isEmpty)
  }

  @Test("planZoneRecovery stops recovering a zone that has hit the attempt limit")
  func planZoneRecoveryExhausted() {
    let zone = CKRecordZone.ID(zoneName: "trip-a", ownerName: CKCurrentUserDefaultName)
    let r1 = CKRecord.ID(recordName: "r1", zoneID: zone)
    let plan = TripSyncEngine.planZoneRecovery(
      failures: [(r1, .zoneNotFound)],
      scope: .private, attempts: [zone: 3], maxAttempts: 3
    )
    #expect(plan.zonesToCreate.isEmpty)
    #expect(plan.recordsToRetry.isEmpty)
    #expect(plan.attemptedZones.isEmpty)
    #expect(plan.failedRecordIDs == [r1])
  }

  @Test("planZoneRecovery never creates a zone on the shared DB — zoneNotFound is terminal there")
  func planZoneRecoverySharedTerminal() {
    let zone = CKRecordZone.ID(zoneName: "trip-a", ownerName: "remoteOwner")
    let r1 = CKRecord.ID(recordName: "r1", zoneID: zone)
    let plan = TripSyncEngine.planZoneRecovery(
      failures: [(r1, .zoneNotFound)],
      scope: .shared, attempts: [:], maxAttempts: 3
    )
    #expect(plan.zonesToCreate.isEmpty)
    #expect(plan.attemptedZones.isEmpty)
    #expect(plan.failedRecordIDs == [r1])
  }

  @Test("planZoneRecovery recovers zoneNotFound and fails other errors in the same batch")
  func planZoneRecoveryMixed() {
    let zone = CKRecordZone.ID(zoneName: "trip-a", ownerName: CKCurrentUserDefaultName)
    let missing = CKRecord.ID(recordName: "r1", zoneID: zone)
    let conflict = CKRecord.ID(recordName: "r2", zoneID: zone)
    let plan = TripSyncEngine.planZoneRecovery(
      failures: [(missing, .zoneNotFound), (conflict, .serverRecordChanged)],
      scope: .private, attempts: [:], maxAttempts: 3
    )
    #expect(plan.zonesToCreate == [zone])
    #expect(plan.recordsToRetry == [missing])
    #expect(plan.failedRecordIDs == [conflict])
  }

  // MARK: - Initial fetch decision (T-1670)

  @Test("needsInitialFetch is true when the private scope has no persisted state")
  func needsInitialFetchFreshStore() throws {
    let container = try Self.makeContainer()
    let engine = TripSyncEngine(
      context: container.mainContext,
      container: CKContainer(identifier: "iCloud.test"),
      stateStore: InMemoryTripSyncStateStore()
    )
    #expect(engine.needsInitialFetch())
  }

  @Test("needsInitialFetch is true when the private scope's state is corrupt")
  func needsInitialFetchCorruptStore() throws {
    let container = try Self.makeContainer()
    let store = InMemoryTripSyncStateStore()
    store.returnCorruptDataForScopes = [.private]
    let engine = TripSyncEngine(
      context: container.mainContext,
      container: CKContainer(identifier: "iCloud.test"),
      stateStore: store
    )
    #expect(engine.needsInitialFetch())
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
}
