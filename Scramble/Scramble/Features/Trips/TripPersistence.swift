import CloudKit
import Foundation
import SwiftData
import os

/// Phase 5.1 — helpers for applying a `TripDraft` to the trip-domain
/// store.
///
/// `create` / `apply` operate against two contexts:
/// - `tripsLocal` — owns the `Trip`, `TripPersonSnapshot`,
///   `TripPackingItem`, and `TripZoneState` rows.
/// - `globals` — owns the `Person` rows the draft refers to by UUID.
///
/// Both functions resolve `draft.participantIDs` against `globals` to
/// pull name + colourKey per person, then maintain
/// `trip.participantSnapshots` (the Phase 5 V3 relationship that lives
/// in `tripsLocal`). The V2-era `Trip.participants → Person`
/// relationship is intentionally not written from the production read
/// paths (constraint C3); it remains on the schema and is unreachable
/// from trip-domain views.
///
/// The caller is responsible for committing both contexts via
/// `LocalWriteHook.commit(_:)` (for `tripsLocal`) and an ordinary
/// `globals.save()` (for any globals-only writes the caller staged).
/// These helpers are mutate-only.
@MainActor enum TripPersistence {

  struct ResolvedParticipants {
    let resolved: [Person]
    let missingIDs: [UUID]
  }

  /// Look up the persons named in `ids` against the `globals` context.
  /// Unresolved IDs are dropped and returned to the caller for the
  /// orphan-toast surface (Decision 15, AC 8.5 / 1.9 dangling-reference
  /// policy).
  static func resolveParticipants(
    ids: [UUID],
    in globals: ModelContext
  ) -> ResolvedParticipants {
    let idSet = Set(ids)
    guard !idSet.isEmpty else {
      return ResolvedParticipants(resolved: [], missingIDs: [])
    }
    // `#Predicate` translates `Array.contains` to a SwiftData query reliably;
    // `Set.contains` is less consistently supported across OS versions.
    let idArray = Array(idSet)
    let descriptor = FetchDescriptor<Person>(
      predicate: #Predicate<Person> { idArray.contains($0.id) }
    )
    let fetched: [Person]
    do {
      fetched = try globals.fetch(descriptor)
    } catch {
      // A fetch failure here (corrupt store, mid-migration schema mismatch)
      // would silently drop every participant from the trip on save. Surface
      // it via the persistence logger and treat the trip as having no
      // resolvable participants so the orphan path lights up downstream.
      modelLogger.error(
        "TripPersistence.resolveParticipants fetch failed: \(error.localizedDescription, privacy: .public)"
      )
      fetched = []
    }
    let byID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
    let missing = ids.filter { byID[$0] == nil }
    let ordered = ids.compactMap { byID[$0] }
    return ResolvedParticipants(resolved: ordered, missingIDs: missing)
  }

  /// Create a new `Trip` from the draft. Inserts the trip, its
  /// `TripZoneState` (so the first edit's hook commit has somewhere to
  /// record dirty flags — Req 1.5), and a `TripPersonSnapshot` per
  /// resolved participant. Returns the new trip and any orphaned IDs.
  @discardableResult
  static func create(
    from draft: TripDraft,
    in tripsLocal: ModelContext,
    globals: ModelContext
  ) -> (Trip, [UUID]) {
    let resolved = resolveParticipants(ids: draft.participantIDs, in: globals)
    let trip = Trip(
      name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
      startDate: draft.startDate,
      endDate: draft.endDate,
      attributes: draft.attributes
    )
    tripsLocal.insert(trip)

    // TripZoneState up-front so the first hook commit can stamp dirty
    // flags before the engine sees the new trip.
    let zoneState = TripZoneState(
      tripID: trip.id,
      zoneOwnerName: CKCurrentUserDefaultName,
      zoneScope: "private"
    )
    tripsLocal.insert(zoneState)

    for person in resolved.resolved {
      let snapshot = TripPersonSnapshot(
        personID: person.id,
        name: person.name,
        colourID: person.colorKey,
        initialSource: "name",
        isRosterMember: true,
        trip: trip
      )
      tripsLocal.insert(snapshot)
    }
    return (trip, resolved.missingIDs)
  }

  /// Apply the draft to an existing `Trip`. Diffs the resolved
  /// participants against the trip's `participantSnapshots` and:
  /// - inserts a `TripPersonSnapshot` for new IDs;
  /// - calls `SnapshotMaintenance.handleRosterRemoval` for removed IDs
  ///   (which deletes the snapshot when no packing item still references
  ///   it, else flips `isRosterMember = false`);
  /// - updates `name` + `colourID` in place for kept IDs whose Person
  ///   changed.
  /// Returns any orphaned IDs.
  @discardableResult
  static func apply(
    _ draft: TripDraft,
    to trip: Trip,
    in tripsLocal: ModelContext,
    globals: ModelContext
  ) throws -> [UUID] {
    let resolved = resolveParticipants(ids: draft.participantIDs, in: globals)
    trip.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    trip.startDate = draft.startDate
    trip.endDate = draft.endDate
    trip.attributes = draft.attributes

    let existing = trip.participantSnapshots ?? []
    let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.personID, $0) })
    let desiredByID = Dictionary(uniqueKeysWithValues: resolved.resolved.map { ($0.id, $0) })

    // Remove snapshots whose person is no longer in the draft. Use the
    // dedicated routine so packing-item-referenced snapshots survive
    // as `isRosterMember = false` (Req 6.2). Errors propagate so the
    // caller can roll back the context — `handleRosterRemoval` interleaves
    // a fetch with a mutation, so a partial pass would leave one snapshot
    // flipped to `isRosterMember=false` without the corresponding delete
    // sweep. Logging-and-continuing here would hide that partial state.
    for snapshot in existing where desiredByID[snapshot.personID] == nil {
      try SnapshotMaintenance.handleRosterRemoval(
        tripID: trip.id,
        personID: snapshot.personID,
        in: tripsLocal
      )
    }

    // Insert new + update kept.
    for person in resolved.resolved {
      if let snapshot = existingByID[person.id] {
        if snapshot.name != person.name || snapshot.colourID != person.colorKey {
          snapshot.name = person.name
          snapshot.colourID = person.colorKey
          snapshot.initialSource = "name"
        }
        snapshot.isRosterMember = true
      } else {
        let snapshot = TripPersonSnapshot(
          personID: person.id,
          name: person.name,
          colourID: person.colorKey,
          initialSource: "name",
          isRosterMember: true,
          trip: trip
        )
        tripsLocal.insert(snapshot)
      }
    }

    return resolved.missingIDs
  }

  static func orphanedParticipantMessage(count: Int) -> String {
    count == 1
      ? "1 participant was removed during save (already deleted on another device)"
      : "\(count) participants were removed during save (already deleted on another device)"
  }
}

/// Trip-date range formatter shared by `TripListView` and `TripDetailView`.
/// Kept as a free function (vs an extension on `Date`) because it operates on
/// a pair of dates and only ever renders in one canonical style.
nonisolated func formatTripDateRange(start: Date, end: Date) -> String {
  let style = Date.FormatStyle.dateTime.day().month(.abbreviated).year(.defaultDigits)
  return "\(start.formatted(style)) – \(end.formatted(style))"
}
