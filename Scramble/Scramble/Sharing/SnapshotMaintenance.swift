import Foundation
import SwiftData

/// Phase 5 / Phase 5.1 — owner-side maintenance for `TripPersonSnapshot`
/// rows.
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
/// **Phase 5.1 contract:** every routine here is mutate-only. None of
/// them call `context.save()` or stamp `TripZoneState.pendingUploadFlags`
/// directly. The caller is responsible for committing through
/// `LocalWriteHook.commit(_:)` after invoking one or more of these
/// routines so the user action collapses to a single commit with
/// correct dirty-marking (Phase 5.1 design § "Save-path chokepoint
/// topology").
///
/// SwiftData's cascade traversal on iOS 26.4 cannot be relied on for the
/// snapshot ↔ packing-item nullify chain (see persistence note
/// "Trip.participantSnapshots is one-way"), so the cleanup is explicit
/// instead of declarative.
@MainActor
enum SnapshotMaintenance {

  /// Update every snapshot referencing `person` with the person's latest
  /// `name` / `colorKey`. Owner-only: snapshots living in trips owned by
  /// other users are skipped. Mutate-only — the caller commits via
  /// `LocalWriteHook.commit(_:)`, which marks each touched snapshot
  /// dirty in its trip's `TripZoneState`.
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
    for snapshot in snapshots {
      guard let tripID = snapshot.trip?.id else { continue }
      if case .otherUser = ownerIdentity(tripID) { continue }
      snapshot.name = person.name
      snapshot.colourID = person.colorKey
      snapshot.initialSource = "name"
    }
  }

  /// Mark the matching snapshot as non-roster and delete it if no packing
  /// item still references it. Idempotent — if no snapshot exists for the
  /// (trip, person) pair, the call is a no-op. Mutate-only.
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
  }

  /// Inspect the snapshot of a packing item that is being deleted. If the
  /// snapshot is non-roster and no other packing item still references
  /// it, delete the snapshot too. Caller is responsible for actually
  /// deleting `item`. Mutate-only.
  ///
  /// **Ordering contract — call BEFORE `context.delete(item)`.** This
  /// routine counts referrers via a SwiftData fetch (predicate over
  /// `personSnapshot?.id`) which sees the in-context state, including
  /// any deletions staged in this transaction. If `item` is already
  /// deleted at the moment of this call, the referrer count drops to
  /// zero prematurely and a snapshot that other packing items still
  /// reference would be deleted incorrectly. Production callers
  /// (`PackingSheet.deletePackingItem`, `PackingItemForm.delete`)
  /// must run `try SnapshotMaintenance.handlePackingItemDeletion(item,
  /// in: context)` first, then `context.delete(item)`, then the single
  /// `LocalWriteHook.commit(_:)`.
  static func handlePackingItemDeletion(
    _ item: TripPackingItem,
    in context: ModelContext
  ) throws {
    #if DEBUG
      // Enforce the ordering contract: the item must still be live in
      // the context at the moment of this call. A staged deletion
      // (`context.deletedModelsArray` contains `item`) means the caller
      // ran `context.delete(item)` first, which would let the in-
      // context referrer count drop to zero prematurely and incorrectly
      // delete a snapshot that other packing items reference.
      assert(
        !context.deletedModelsArray.contains(where: { ($0 as? TripPackingItem)?.id == item.id }),
        """
        SnapshotMaintenance.handlePackingItemDeletion: call BEFORE \
        context.delete(item). The in-context referrer count would \
        otherwise miscount and could orphan-delete a snapshot.
        """
      )
    #endif
    guard let snapshot = item.personSnapshot else { return }
    guard !snapshot.isRosterMember else { return }
    let referrerCount = try referrerCount(for: snapshot, in: context, excluding: item.id)
    if referrerCount == 0 {
      context.delete(snapshot)
    }
  }

  /// Periodic sweep — deletes every non-roster snapshot with no referring
  /// packing items. Safe to call on every engine post-run. Mutate-only.
  static func sweep(in context: ModelContext) throws {
    let snapshots = try context.fetch(FetchDescriptor<TripPersonSnapshot>())
    for snapshot in snapshots where !snapshot.isRosterMember {
      let referrerCount = try referrerCount(for: snapshot, in: context)
      if referrerCount == 0 {
        context.delete(snapshot)
      }
    }
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
}
