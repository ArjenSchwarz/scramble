import Foundation
import SwiftData

/// Helpers for applying a `TripDraft` to the model context.
///
/// `resolveParticipants` is shared between trip-create and trip-edit so the
/// orphaned-participant tolerance from `decision_log.md` Decision 15 (and AC 8.5
/// / 1.9 dangling-reference policy) is enforced in one place: IDs that don't
/// resolve are dropped silently and returned to the caller so the UI can surface
/// a transient toast.
@MainActor enum TripPersistence {

  struct ResolvedParticipants {
    let resolved: [Person]
    let missingIDs: [UUID]
  }

  static func resolveParticipants(
    ids: [UUID],
    in context: ModelContext
  ) -> ResolvedParticipants {
    let idSet = Set(ids)
    guard !idSet.isEmpty else {
      return ResolvedParticipants(resolved: [], missingIDs: [])
    }
    let descriptor = FetchDescriptor<Person>(
      predicate: #Predicate<Person> { idSet.contains($0.id) }
    )
    let fetched = (try? context.fetch(descriptor)) ?? []
    let fetchedIDs = Set(fetched.map(\.id))
    let missing = ids.filter { !fetchedIDs.contains($0) }
    // Preserve the user-chosen order from the draft when assigning.
    let ordered = ids.compactMap { id in fetched.first(where: { $0.id == id }) }
    return ResolvedParticipants(resolved: ordered, missingIDs: missing)
  }

  /// Create a new `Trip` from the draft. Returns the new trip and any orphaned IDs.
  @discardableResult
  static func create(from draft: TripDraft, in context: ModelContext) -> (Trip, [UUID]) {
    let resolved = resolveParticipants(ids: draft.participantIDs, in: context)
    let trip = Trip(
      name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
      startDate: draft.startDate,
      endDate: draft.endDate,
      attributes: draft.attributes
    )
    context.insert(trip)
    trip.participants = resolved.resolved
    return (trip, resolved.missingIDs)
  }

  /// Apply the draft to an existing `Trip`. Returns any orphaned IDs.
  @discardableResult
  static func apply(_ draft: TripDraft, to trip: Trip, in context: ModelContext) -> [UUID] {
    let resolved = resolveParticipants(ids: draft.participantIDs, in: context)
    trip.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    trip.startDate = draft.startDate
    trip.endDate = draft.endDate
    trip.attributes = draft.attributes
    trip.participants = resolved.resolved
    return resolved.missingIDs
  }
}
