import CloudKit
import Foundation
import SwiftData
import Testing

@testable import Scramble

/// Phase 5.1 — property-based test for the `LocalWriteHook.commitDeletion`
/// mixed-zone partition contract
/// ([Req 2.4](../requirements.md#2.4), design § "LocalWriteHook (changed)").
///
/// Given any combination of:
///   - `vanishingZoneCount`: how many trip zones are deleted in the commit
///   - `survivingZoneCount`: how many trip zones survive the commit
///   - records being deleted within the vanishing zones
///   - records being deleted within the surviving zones
///   - records being changed in the surviving zones
///
/// the post-commit invariants are:
///   1. Surviving-zone `TripZoneState.pendingUploadFlags` carries only the
///      surviving-zone dirty + deleted record names (no flag write for the
///      vanishing zones).
///   2. The notifier receives the UNION of all deleted record IDs across
///      both vanishing and surviving zones (so the engine queues
///      `deleteRecord` operations for both kinds).
@Suite("LocalWriteHook PBT — commitDeletion", .serialized)
@MainActor
struct LocalWriteHookPBT {

  struct Scenario: Sendable, CustomStringConvertible {
    let vanishingZoneCount: Int
    let survivingZoneCount: Int
    let deletedPerVanishing: Int
    let deletedPerSurviving: Int
    let changedPerSurviving: Int

    var description: String {
      "v=\(vanishingZoneCount)/d\(deletedPerVanishing)"
        + " s=\(survivingZoneCount)/d\(deletedPerSurviving)+c\(changedPerSurviving)"
    }
  }

  /// A small but expressive cross-product. The number of cases stays
  /// bounded so Swift Testing's `-parallel-testing-worker-count 1` simulator
  /// runs don't blow up the suite runtime.
  static let scenarios: [Scenario] = {
    var result: [Scenario] = []
    for vanish in [1, 2] {
      for surviving in [0, 1, 2] {
        for delV in [0, 1, 2] {
          for delS in [0, 1] where surviving > 0 || delS == 0 {
            for chgS in [0, 1] where surviving > 0 || chgS == 0 {
              result.append(
                Scenario(
                  vanishingZoneCount: vanish,
                  survivingZoneCount: surviving,
                  deletedPerVanishing: delV,
                  deletedPerSurviving: delS,
                  changedPerSurviving: chgS
                ))
            }
          }
        }
      }
    }
    return result
  }()

  // swiftlint:disable function_body_length cyclomatic_complexity
  @Test(
    "PBT — commitDeletion partitions correctly across mixed-zone inputs",
    arguments: Self.scenarios
  )
  func mixedZonePartition(scenario: Scenario) throws {
    let container = try Self.makeContainer()
    let context = container.mainContext
    let notifier = RecordingNotifier()
    let hook = LocalWriteHook(notifier: notifier)

    // Seed surviving zones: trip + TripZoneState per zone.
    var survivingZoneIDs: [CKRecordZone.ID] = []
    var survivingTrips: [Trip] = []
    for index in 0..<scenario.survivingZoneCount {
      let trip = Trip(name: "Surviving\(index)", startDate: .now, endDate: .now)
      context.insert(trip)
      let zoneID = CKRecordZone.ID(
        zoneName: "trip-\(trip.id.uuidString)",
        ownerName: CKCurrentUserDefaultName
      )
      let state = TripZoneState(
        tripID: trip.id,
        zoneOwnerName: CKCurrentUserDefaultName,
        zoneScope: "private"
      )
      context.insert(state)
      survivingZoneIDs.append(zoneID)
      survivingTrips.append(trip)
    }
    try hook.commit(context)
    notifier.calls.removeAll()

    // Seed vanishing trips + their zone states.
    var vanishingZoneIDs: [CKRecordZone.ID] = []
    var vanishingTrips: [Trip] = []
    var vanishingDeletedItemIDs: [Trip: [TripPackingItem]] = [:]
    for index in 0..<scenario.vanishingZoneCount {
      let trip = Trip(name: "Vanishing\(index)", startDate: .now, endDate: .now)
      context.insert(trip)
      let zoneID = CKRecordZone.ID(
        zoneName: "trip-\(trip.id.uuidString)",
        ownerName: CKCurrentUserDefaultName
      )
      let state = TripZoneState(
        tripID: trip.id,
        zoneOwnerName: CKCurrentUserDefaultName,
        zoneScope: "private"
      )
      context.insert(state)
      var items: [TripPackingItem] = []
      for itemIndex in 0..<scenario.deletedPerVanishing {
        let item = TripPackingItem(
          trip: trip, name: "v-\(index)-\(itemIndex)"
        )
        context.insert(item)
        items.append(item)
      }
      vanishingDeletedItemIDs[trip] = items
      vanishingZoneIDs.append(zoneID)
      vanishingTrips.append(trip)
    }
    try hook.commit(context)
    notifier.calls.removeAll()

    // Build the mixed-zone commit: stage deletions in vanishing zones,
    // deletions + changes in surviving zones.
    var expectedSurvivingDirty: [CKRecordZone.ID: Set<String>] = [:]
    var expectedSurvivingDeleted: [CKRecordZone.ID: Set<String>] = [:]
    var expectedVanishingDeleted: [CKRecordZone.ID: Set<String>] = [:]

    // Vanishing-zone deletions (record-level deletes + the trip + its TripZoneState).
    for (trip, items) in vanishingDeletedItemIDs {
      for item in items {
        context.delete(item)
        let zoneID = CKRecordZone.ID(
          zoneName: "trip-\(trip.id.uuidString)",
          ownerName: CKCurrentUserDefaultName
        )
        expectedVanishingDeleted[zoneID, default: []].insert(item.id.uuidString)
      }
    }
    for trip in vanishingTrips {
      let zoneID = CKRecordZone.ID(
        zoneName: "trip-\(trip.id.uuidString)",
        ownerName: CKCurrentUserDefaultName
      )
      expectedVanishingDeleted[zoneID, default: []].insert(trip.id.uuidString)
      context.delete(trip)
    }
    for state in try context.fetch(FetchDescriptor<TripZoneState>())
    where vanishingTrips.contains(where: { $0.id == state.tripID }) {
      context.delete(state)
    }

    // Surviving-zone deletions: insert + commit some items then delete them.
    for (index, trip) in survivingTrips.enumerated() {
      let zoneID = survivingZoneIDs[index]
      for delIndex in 0..<scenario.deletedPerSurviving {
        let item = TripPackingItem(trip: trip, name: "s-del-\(delIndex)")
        context.insert(item)
        try hook.commit(context)
        notifier.calls.removeAll()
        context.delete(item)
        expectedSurvivingDeleted[zoneID, default: []].insert(item.id.uuidString)
      }
      for chgIndex in 0..<scenario.changedPerSurviving {
        let item = TripPackingItem(trip: trip, name: "s-chg-\(chgIndex)")
        context.insert(item)
        expectedSurvivingDirty[zoneID, default: []].insert(item.id.uuidString)
      }
    }

    try hook.commitDeletion(
      context, zoneIDsBeingDeleted: Set(vanishingZoneIDs)
    )

    // Invariant 1 — surviving zone flags carry only surviving-zone deltas.
    for (index, trip) in survivingTrips.enumerated() {
      let zoneID = survivingZoneIDs[index]
      let descriptor = FetchDescriptor<TripZoneState>(
        predicate: #Predicate { $0.tripID == trip.id }
      )
      guard let survivingState = try context.fetch(descriptor).first else {
        Issue.record("Surviving TripZoneState vanished unexpectedly")
        continue
      }
      let flags = PendingUploadFlags.decode(survivingState.pendingUploadFlags)
      let expectedDirty = expectedSurvivingDirty[zoneID] ?? []
      let expectedDeleted = expectedSurvivingDeleted[zoneID] ?? []
      #expect(
        expectedDirty.isSubset(of: flags.dirtyRecordNames),
        "Surviving zone carries the expected dirty record names"
      )
      #expect(
        expectedDeleted.isSubset(of: flags.deletedRecordNames),
        "Surviving zone carries the expected deleted record names"
      )
    }

    // Invariant 2 — notifier received the union of deletions across both partitions.
    var notifiedDeletedByZone: [CKRecordZone.ID: Set<String>] = [:]
    for call in notifier.calls {
      let zone = call.zoneID
      let names = Set(call.deletedRecordIDs.map(\.recordName))
      notifiedDeletedByZone[zone, default: []].formUnion(names)
    }
    for (zone, expected) in expectedVanishingDeleted {
      #expect(
        expected.isSubset(of: notifiedDeletedByZone[zone] ?? []),
        "Notifier received deletions for vanishing zone \(zone.zoneName)"
      )
    }
    for (zone, expected) in expectedSurvivingDeleted {
      #expect(
        expected.isSubset(of: notifiedDeletedByZone[zone] ?? []),
        "Notifier received deletions for surviving zone \(zone.zoneName)"
      )
    }
  }
  // swiftlint:enable function_body_length cyclomatic_complexity

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
