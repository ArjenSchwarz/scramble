import Foundation
import SwiftData

/// Phase 5 Stage A — `SchemaV2 → SchemaV3` custom migration step.
///
/// SwiftData applies the lightweight schema diff (new entities + new columns)
/// before this runs. The custom step then backfills the V3 person snapshots
/// from the V2 `Trip.participants` / `TripPackingItem.person` references so
/// shared trips render the same on every device without consulting the
/// owner's globals zone (Decision 7,
/// Req [2.1](../../../../specs/phase-5-cloudkit-sharing/requirements.md#2.1) /
/// [2.2](../../../../specs/phase-5-cloudkit-sharing/requirements.md#2.2)).
nonisolated enum SchemaV3MigrationStage {

  /// Idempotent backfill — safe to invoke any number of times against a V3
  /// store. For every `Trip` with `participants` populated, inserts one
  /// `TripPersonSnapshot` per `Person` (skipping persons that already have
  /// a snapshot on the trip), then walks `TripPackingItem`s and assigns
  /// `personSnapshot` to the matching trip-scoped snapshot when the item's
  /// `person` is part of the trip's roster.
  ///
  /// Offline-safe — touches only the local SwiftData store, never CloudKit.
  /// Runs unconditionally including when the user is signed out
  /// (Req [11.3](../../../../specs/phase-5-cloudkit-sharing/requirements.md#11.3)).
  ///
  /// `nonisolated` so SwiftData's `MigrationStage.custom` `didMigrate`
  /// closure (called on a synchronous, non-isolated context) can invoke
  /// it. Caller is responsible for actor isolation of the supplied
  /// `ModelContext`.
  nonisolated static func backfillSnapshots(in context: ModelContext) throws {
    let trips = try context.fetch(FetchDescriptor<Trip>())
    for trip in trips {
      try backfillSnapshots(for: trip, in: context)
    }
  }

  private nonisolated static func backfillSnapshots(
    for trip: Trip,
    in context: ModelContext
  ) throws {
    let participants = trip.participants ?? []
    let existingSnapshots = trip.participantSnapshots ?? []
    let existingByPersonID = Dictionary(
      uniqueKeysWithValues: existingSnapshots.map { ($0.personID, $0) }
    )

    var snapshotByPersonID = existingByPersonID
    var newSnapshots: [TripPersonSnapshot] = []
    for person in participants where existingByPersonID[person.id] == nil {
      let snapshot = TripPersonSnapshot(
        personID: person.id,
        name: person.name,
        colourID: person.colorKey,
        initialSource: "name",
        isRosterMember: true,
        trip: trip
      )
      context.insert(snapshot)
      snapshotByPersonID[person.id] = snapshot
      newSnapshots.append(snapshot)
    }
    // `Trip.participantSnapshots ↔ TripPersonSnapshot.trip` is an unpaired
    // relationship (see the model decl — the inverse was dropped for the
    // iOS 26.4 cascade-traversal workaround). SwiftData therefore can't
    // auto-populate the trip-side array from the snapshot-side `trip`
    // reference; the writer has to maintain both sides explicitly.
    if !newSnapshots.isEmpty {
      var combined = existingSnapshots
      combined.append(contentsOf: newSnapshots)
      trip.participantSnapshots = combined
    }

    for item in trip.packingItems ?? [] {
      // Already linked — nothing to do (idempotence on a re-run).
      if item.personSnapshot != nil { continue }
      guard let person = item.person else { continue }
      // The item's person may have been removed from the roster after the
      // packing item was created (Req 2.4 dangling-snapshot rule); only
      // wire up a snapshot when there is one for this person on this trip.
      if let snapshot = snapshotByPersonID[person.id] {
        item.personSnapshot = snapshot
      }
    }
  }
}
