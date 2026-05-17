import CloudKit
import Foundation
import SwiftData
import Testing

@testable import Scramble

@Suite("TripZoneStateRecordTranslator", .serialized)
@MainActor
struct TripZoneStateRecordTranslatorTests {

  @Test("from(_:into:) inserts a TripZoneState row keyed off the zone's trip-UUID name")
  func decodeInsertsZoneStateForFreshShare() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let tripID = UUID()
    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(tripID.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    let share = CKShare(recordZoneID: zoneID)

    try TripZoneStateRecordTranslator.from(share, into: context)
    try context.save()

    let stored = try #require(try context.fetch(FetchDescriptor<TripZoneState>()).first)
    #expect(stored.tripID == tripID)
    #expect(stored.shareID == share.recordID.recordName)
    #expect(stored.ckRecordSystemFields != nil)
  }

  @Test("from(_:into:) merges into an existing TripZoneState rather than duplicating")
  func decodeMergesIntoExistingState() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let tripID = UUID()
    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(tripID.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    let existing = TripZoneState(
      tripID: tripID,
      zoneOwnerName: CKCurrentUserDefaultName,
      zoneScope: "private"
    )
    context.insert(existing)
    try context.save()

    let share = CKShare(recordZoneID: zoneID)
    try TripZoneStateRecordTranslator.from(share, into: context)
    try context.save()

    let stored = try context.fetch(FetchDescriptor<TripZoneState>())
    #expect(stored.count == 1)
    #expect(stored.first?.shareID == share.recordID.recordName)
  }

  @Test("from(_:into:) silently ignores zones whose name doesn't match the trip-UUID format")
  func decodeIgnoresUnknownZoneFormat() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let zoneID = CKRecordZone.ID(zoneName: "globals", ownerName: CKCurrentUserDefaultName)
    let share = CKShare(recordZoneID: zoneID)

    try TripZoneStateRecordTranslator.from(share, into: context)
    try context.save()

    let stored = try context.fetch(FetchDescriptor<TripZoneState>())
    #expect(stored.isEmpty)
  }

  @Test("zoneID(for:) derives a stable trip-{uuid} zone name")
  func zoneIDComposition() {
    let tripID = UUID()
    let state = TripZoneState(
      tripID: tripID,
      zoneOwnerName: CKCurrentUserDefaultName,
      zoneScope: "private"
    )
    let zoneID = TripZoneStateRecordTranslator.zoneID(for: state)
    #expect(zoneID.zoneName == "trip-\(tripID.uuidString)")
    #expect(zoneID.ownerName == CKCurrentUserDefaultName)
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
