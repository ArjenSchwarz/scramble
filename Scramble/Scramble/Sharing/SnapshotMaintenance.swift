import CloudKit
import Foundation
import SwiftData

/// Phase 5 — owner-side maintenance for `TripPersonSnapshot` rows.
///
/// Snapshots are denormalised per-trip identity carried inside each trip
/// zone so participants can render the trip without consulting the owner's
/// globals zone (Decision 7). The four routines below keep snapshots in
/// sync with `Person` edits and clean up orphaned rows:
///
/// 1. `propagatePersonEdit` — fan-out a Person rename / colour change to
///    every snapshot referencing it (Req
///    [2.3](../../../specs/phase-5-cloudkit-sharing/requirements.md#2.3)).
///    Owner-only — gated by the supplied `ownerIdentity` closure.
/// 2. `handleRosterRemoval` — flip a snapshot to `isRosterMember = false`
///    when a person is removed from the trip's roster; delete it in the
///    same transaction when no packing item still references it.
/// 3. `handlePackingItemDeletion` — when a packing item is being deleted,
///    delete its snapshot if it is non-roster and no other items refer to
///    it.
/// 4. `sweep` — post-engine-run sweep that deletes any non-roster
///    snapshots with no remaining references (defence-in-depth against
///    missed triggers).
///
/// SwiftData's cascade traversal on iOS 26.4 cannot be relied on for the
/// snapshot ↔ packing-item nullify chain (see persistence note "Trip.participantSnapshots is one-way"),
/// so the cleanup is explicit instead of declarative.
@MainActor
enum SnapshotMaintenance {

  /// Update every snapshot referencing `person` with the person's latest
  /// `name` / `colorKey` and mark each affected `TripZoneState`'s
  /// snapshot record dirty for upload. Owner-only: snapshots living in
  /// trips owned by other users are skipped.
  static func propagatePersonEdit(
    _ person: Person,
    in context: ModelContext,
    ownerIdentity: (UUID) -> OwnerIdentity?
  ) throws {
    let personID = person.id
    let descriptor = FetchDescriptor<TripPersonSnapshot>(
      predicate: #Predicate { $0.personID == personID }
    )
    let snapshots = try context.fetch(descriptor)
    var dirtyTrips: [UUID: Set<String>] = [:]
    for snapshot in snapshots {
      guard let tripID = snapshot.trip?.id else { continue }
      if case .otherUser = ownerIdentity(tripID) { continue }
      snapshot.name = person.name
      snapshot.colourID = person.colorKey
      snapshot.initialSource = "name"
      dirtyTrips[tripID, default: []].insert(snapshot.id.uuidString)
    }
    try context.save()
    for (tripID, dirtyNames) in dirtyTrips {
      try flagDirty(tripID: tripID, recordNames: dirtyNames, in: context)
    }
    try context.save()
  }

  /// Mark the matching snapshot as non-roster and delete it if no packing
  /// item still references it. Idempotent — if no snapshot exists for the
  /// (trip, person) pair, the call is a no-op.
  static func handleRosterRemoval(
    tripID: UUID,
    personID: UUID,
    in context: ModelContext
  ) throws {
    let descriptor = FetchDescriptor<TripPersonSnapshot>(
      predicate: #Predicate { $0.personID == personID && $0.trip?.id == tripID }
    )
    let matches = try context.fetch(descriptor)
    for snapshot in matches {
      snapshot.isRosterMember = false
      let referrerCount = try referrerCount(for: snapshot, in: context)
      if referrerCount == 0 {
        context.delete(snapshot)
      }
    }
    try context.save()
  }

  /// Inspect the snapshot of a packing item that is being deleted. If the
  /// snapshot is non-roster and no other packing item still references
  /// it, delete the snapshot too. Caller is responsible for actually
  /// deleting `item`.
  static func handlePackingItemDeletion(
    _ item: TripPackingItem,
    in context: ModelContext
  ) throws {
    guard let snapshot = item.personSnapshot else { return }
    guard !snapshot.isRosterMember else { return }
    let referrerCount = try referrerCount(for: snapshot, in: context, excluding: item.id)
    if referrerCount == 0 {
      context.delete(snapshot)
    }
    try context.save()
  }

  /// Periodic sweep — deletes every non-roster snapshot with no referring
  /// packing items. Safe to call on every engine post-run.
  static func sweep(in context: ModelContext) throws {
    let snapshots = try context.fetch(FetchDescriptor<TripPersonSnapshot>())
    for snapshot in snapshots where !snapshot.isRosterMember {
      let referrerCount = try referrerCount(for: snapshot, in: context)
      if referrerCount == 0 {
        context.delete(snapshot)
      }
    }
    try context.save()
  }

  // MARK: - Private

  private static func referrerCount(
    for snapshot: TripPersonSnapshot,
    in context: ModelContext,
    excluding excludedItemID: UUID? = nil
  ) throws -> Int {
    let snapshotID = snapshot.id
    let items = try context.fetch(
      FetchDescriptor<TripPackingItem>(
        predicate: #Predicate { $0.personSnapshot?.id == snapshotID }
      )
    )
    if let excludedItemID {
      return items.filter { $0.id != excludedItemID }.count
    }
    return items.count
  }

  private static func flagDirty(
    tripID: UUID,
    recordNames: Set<String>,
    in context: ModelContext
  ) throws {
    let descriptor = FetchDescriptor<TripZoneState>(predicate: #Predicate { $0.tripID == tripID })
    guard let state = try context.fetch(descriptor).first else { return }
    var flags = PendingUploadFlags.decode(state.pendingUploadFlags)
    for name in recordNames {
      flags.markDirty(recordName: name)
    }
    state.pendingUploadFlags = flags.encode()
  }
}
