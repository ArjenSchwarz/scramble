import CloudKit
import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Phase 5 — trip-global flag semantics
/// (Req [8.7](../../../specs/phase-5-cloudkit-sharing/requirements.md#8.7),
/// Decision 9).
///
/// `pinnedByUser` and `userDeletedOnThisTrip` are trip-global in v1 —
/// either member can toggle them and the change is visible to every
/// member on next sync. Last-writer-wins per attribute via the translator
/// (no conflict prompt).
@Suite("TripFlagSync", .serialized)
@MainActor
struct TripFlagSyncTests {

  // MARK: - Roundtrip

  @Test("TripTask.pinnedByUser round-trips through the translator")
  func taskPinnedRoundtrips() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack", pinnedByUser: true)
    context.insert(trip)
    context.insert(task)
    try context.save()

    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    let record = try TripTaskRecordTranslator.toRecord(task, in: zoneID, existing: nil)
    #expect(record["pinnedByUser"] as? Bool == true)

    // Simulate a remote toggle: the remote device sends pinnedByUser=false.
    record["pinnedByUser"] = false as CKRecordValue
    try TripTaskRecordTranslator.from(record, into: context)

    let stored = try #require(try context.fetch(FetchDescriptor<TripTask>()).first)
    #expect(stored.pinnedByUser == false, "Remote toggle must apply via LWW")
  }

  @Test("TripTask.userDeletedOnThisTrip round-trips through the translator")
  func taskUserDeletedRoundtrips() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let task = TripTask(trip: trip, name: "Pack", userDeletedOnThisTrip: false)
    context.insert(trip)
    context.insert(task)
    try context.save()

    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    var record = try TripTaskRecordTranslator.toRecord(task, in: zoneID, existing: nil)
    // Remote member flips userDeletedOnThisTrip to true.
    record["userDeletedOnThisTrip"] = true as CKRecordValue
    try TripTaskRecordTranslator.from(record, into: context)

    let stored = try #require(try context.fetch(FetchDescriptor<TripTask>()).first)
    #expect(stored.userDeletedOnThisTrip == true)
  }

  @Test("TripPackingItem.pinnedByUser round-trips through the translator")
  func packingPinnedRoundtrips() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let item = TripPackingItem(trip: trip, name: "Socks", pinnedByUser: false)
    context.insert(trip)
    context.insert(item)
    try context.save()

    let zoneID = CKRecordZone.ID(
      zoneName: "trip-\(trip.id.uuidString)",
      ownerName: CKCurrentUserDefaultName
    )
    let record = try TripPackingItemRecordTranslator.toRecord(item, in: zoneID, existing: nil)
    record["pinnedByUser"] = true as CKRecordValue
    try TripPackingItemRecordTranslator.from(record, into: context)

    let stored = try #require(try context.fetch(FetchDescriptor<TripPackingItem>()).first)
    #expect(stored.pinnedByUser == true)
  }

  // MARK: - Engine respects flags as trip-global

  @Test("Engine does not mutate a TripTask pinned by another member")
  func enginePreservesPinnedFromRemoteMember() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let master = MasterTaskItem(
      name: "Bring umbrella",
      phase: .dayBefore,
      conditions: .match(attribute: .weather, anyOf: ["rain"])
    )
    context.insert(master)

    var attrs = TripAttributes()
    attrs.toggle(.weather, value: "sun")
    let trip = Trip(name: "T", startDate: .now, endDate: .now, attributes: attrs)
    context.insert(trip)
    // Pre-existing pinned task created by a remote member; rule no longer
    // matches (sun != rain).
    let task = TripTask(
      trip: trip,
      masterItemID: master.id,
      name: "Bring umbrella",
      phase: .dayBefore,
      pinnedByUser: true,
      userDeletedOnThisTrip: false
    )
    context.insert(task)
    try context.save()

    let runner = RulesEngineRunner(context: context)
    _ = try runner.runForTrip(trip)

    let stored = try #require(try context.fetch(FetchDescriptor<TripTask>()).first)
    #expect(stored.pinnedByUser == true, "Pin must survive a non-owner-applied engine pass")
    #expect(stored.currentlyMatchesRules == true,
      "Pinned items are never dimmed by the engine even when their rules don't match")
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
