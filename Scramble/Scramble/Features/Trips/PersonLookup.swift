import Foundation
import SwiftData

/// Cross-container helper that resolves a `Person` UUID against a globals
/// `ModelContext`. Phase 5.1 trip-domain views (rooted in `tripsLocal`)
/// cannot traverse the V2-era `Trip.participants → Person` relationship
/// (constraint C3); when a view needs the live `Person` row — currently
/// only the Trip Editor's people picker and unit tests — it resolves the
/// row through this helper.
///
/// Views that need only name/colour for display should read
/// `TripPersonSnapshot` instead, which lives in `tripsLocal` and is
/// reachable via the trip-domain SwiftData relationship.
@MainActor
enum PersonLookup {
  static func person(for id: UUID, in globals: ModelContext) -> Person? {
    let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.id == id })
    return try? globals.fetch(descriptor).first
  }
}
