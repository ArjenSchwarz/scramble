import Foundation
import SwiftData
import os

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
    let fetched: [Person]
    do {
      fetched = try context.fetch(descriptor)
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
    // Preserve the user-chosen order from the draft when assigning.
    let ordered = ids.compactMap { byID[$0] }
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
