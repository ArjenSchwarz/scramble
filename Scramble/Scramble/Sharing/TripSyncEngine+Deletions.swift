import CloudKit
import Foundation
import SwiftData

extension TripSyncEngine {
  /// Apply tombstones only to the matching CloudKit identity (record name,
  /// zone name, and owner). A UUID alone is not an identity across zones.
  func apply(deletedRecordIDs: [CKRecord.ID]) throws {
    let deletions = Set(deletedRecordIDs)
    let ids = Set(deletedRecordIDs.compactMap { UUID(uuidString: $0.recordName) })
    guard !ids.isEmpty else { return }

    let trips = try context.fetch(
      FetchDescriptor<Trip>(predicate: #Predicate { ids.contains($0.id) }))
    let tasks = try context.fetch(
      FetchDescriptor<TripTask>(predicate: #Predicate { ids.contains($0.id) }))
    let items = try context.fetch(
      FetchDescriptor<TripPackingItem>(predicate: #Predicate { ids.contains($0.id) }))
    let snapshots = try context.fetch(
      FetchDescriptor<TripPersonSnapshot>(predicate: #Predicate { ids.contains($0.id) }))
    let tripIDs = Set(
      trips.map(\.id) + tasks.compactMap { $0.trip?.id }
        + items.compactMap { $0.trip?.id } + snapshots.compactMap { $0.trip?.id })
    let states = try context.fetch(
      FetchDescriptor<TripZoneState>(predicate: #Predicate { tripIDs.contains($0.tripID) }))
    let owners = Dictionary(
      states.map { ($0.tripID, TripZoneStateRecordTranslator.zoneID(for: $0).ownerName) },
      uniquingKeysWith: { first, _ in first })

    let matcher = RecordDeletionMatcher(deletions: deletions, owners: owners)

    // Resolve ownership BEFORE staging any delete: nullification can remove
    // the parent links needed by subsequent checks. Use reverse-cascade order
    // just like TripDeletion to avoid SwiftData snapshot traversal failures.
    let removedTrips = trips.filter {
      matcher.matches($0.id, trip: $0, systemFields: $0.ckRecordSystemFields)
    }
    let removedTripIDs = Set(removedTrips.map(\.id))
    let removedItems = Set(
      items.filter { matcher.matches($0.id, trip: $0.trip, systemFields: $0.ckRecordSystemFields) }
    )
    .union(removedTrips.flatMap { $0.packingItems ?? [] })
    let removedTasks = Set(
      tasks.filter { matcher.matches($0.id, trip: $0.trip, systemFields: $0.ckRecordSystemFields) }
    )
    .union(removedTrips.flatMap { $0.tasks ?? [] })
    let removedSnapshots = Set(
      snapshots.filter {
        matcher.matches($0.id, trip: $0.trip, systemFields: $0.ckRecordSystemFields)
      }
    )
    .union(removedTrips.flatMap { $0.participantSnapshots ?? [] })
    .union(try snapshotsOfTrips(removedTripIDs))
    for item in removedItems { context.delete(item) }
    for task in removedTasks { context.delete(task) }
    for snapshot in removedSnapshots { context.delete(snapshot) }
    for trip in removedTrips { context.delete(trip) }
    for state in states where removedTripIDs.contains(state.tripID) { context.delete(state) }
    try context.save()
  }

  private func snapshotsOfTrips(_ tripIDs: Set<UUID>) throws -> [TripPersonSnapshot] {
    guard !tripIDs.isEmpty else { return [] }
    return try context.fetch(
      FetchDescriptor<TripPersonSnapshot>(
        predicate: #Predicate { snapshot in
          if let trip = snapshot.trip {
            tripIDs.contains(trip.id)
          } else {
            false
          }
        }))
  }

}

@MainActor
private struct RecordDeletionMatcher {
  let deletions: Set<CKRecord.ID>
  let owners: [UUID: String]

  func matches(_ id: UUID, trip: Trip?, systemFields: Data?) -> Bool {
    let zoneID: CKRecordZone.ID
    if let trip {
      let cachedZone = trip.ckRecordSystemFields.flatMap { decodeSystemFields(from: $0) }?
        .recordID.zoneID
      let owner = owners[trip.id] ?? cachedZone?.ownerName ?? CKCurrentUserDefaultName
      zoneID = CKRecordZone.ID(
        zoneName: ZoneMigrationCoordinator.ownerZoneID(for: trip.id).zoneName, ownerName: owner)
    } else {
      // A child can arrive before its trip. Its cached full record identity
      // permits a genuine tombstone without guessing ownership for an orphan.
      guard let cached = systemFields.flatMap({ decodeSystemFields(from: $0) }),
        cached.recordID.recordName == id.uuidString
      else { return false }
      zoneID = cached.recordID.zoneID
    }
    return deletions.contains(CKRecord.ID(recordName: id.uuidString, zoneID: zoneID))
  }

}
