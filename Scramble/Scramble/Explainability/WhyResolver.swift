import Foundation
import SwiftData

/// Namespace for the `WhyDisclosure` view (defined in stream 3, task 16). The
/// nested `Reason` enum lives here so `WhyResolver` and the future view can
/// share the same type without forcing a load-order between streams. The
/// view will extend this empty enum with its own SwiftUI implementation.
enum WhyDisclosure {}

extension WhyDisclosure {
  /// Why a given `TripTask` is on this trip. Computed on demand by
  /// `WhyResolver` and rendered by `WhyDisclosure` (the view).
  enum Reason: Equatable, Sendable {
    /// User added this task manually for this trip.
    case manual
    /// The rule that created this task no longer exists (master deleted or
    /// `masterItemID` is nil).
    case ruleMasterDeleted
    /// The rule's master exists and at least one of its conditions currently
    /// matches the trip's attributes. `conditionsText` is the formatted
    /// explanation produced by `ConditionsFormatter`.
    case ruleMatched(conditionsText: String)
    /// The rule's master exists but no condition currently matches the
    /// trip's attributes.
    case ruleNoLongerMatches
  }
}

/// Resolves the `WhyDisclosure.Reason` for a single `TripTask` against the
/// current store state.
///
/// Conventions:
/// - Manual tasks always return `.manual` regardless of `masterItemID`.
/// - Rule-driven tasks with `masterItemID == nil` or whose master can't be
///   fetched return `.ruleMasterDeleted`.
/// - Rule-driven tasks whose master's conditions evaluate true against the
///   trip's current `attributes` return `.ruleMatched(conditionsText:)`.
/// - Rule-driven tasks whose master's conditions evaluate false return
///   `.ruleNoLongerMatches`.
///
/// `MainActor` because it touches `ModelContext`.
@MainActor
enum WhyResolver {

  static func reason(for task: TripTask, context: ModelContext) -> WhyDisclosure.Reason {
    if task.source == .manual {
      return .manual
    }

    guard let masterID = task.masterItemID else {
      return .ruleMasterDeleted
    }

    guard let master = fetchMaster(id: masterID, context: context) else {
      return .ruleMasterDeleted
    }

    let attributes = task.trip?.attributes ?? TripAttributes()
    let conditions = master.conditions

    if conditions.evaluate(against: attributes) {
      let text = ConditionsFormatter.format(conditions, against: attributes)
      return .ruleMatched(conditionsText: text)
    }
    return .ruleNoLongerMatches
  }

  // MARK: - Private

  private static func fetchMaster(id: UUID, context: ModelContext) -> MasterTaskItem? {
    let descriptor = FetchDescriptor<MasterTaskItem>(
      predicate: #Predicate { $0.id == id }
    )
    return (try? context.fetch(descriptor))?.first
  }
}
