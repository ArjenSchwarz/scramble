import Foundation
import SwiftData
import os

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

  /// Resolves the `WhyDisclosure.Reason` for a `TripTask`. When
  /// `hideOnUnresolvedMaster == true` (participant-side shared trip,
  /// Req 3.3), a rule-driven item whose master cannot be found in the
  /// current globals zone returns `nil` so the affordance is hidden from
  /// the layout. Owner-viewed trips pass `false` and continue to return
  /// `.ruleMasterDeleted` in the same situation.
  static func reason(
    for task: TripTask,
    context: ModelContext,
    hideOnUnresolvedMaster: Bool = false
  ) -> WhyDisclosure.Reason? {
    if task.source == .manual {
      return .manual
    }

    guard let masterID = task.masterItemID else {
      return hideOnUnresolvedMaster ? nil : .ruleMasterDeleted
    }

    let master: MasterTaskItem? = fetchMaster(id: masterID, context: context)
    guard let master else {
      return hideOnUnresolvedMaster ? nil : .ruleMasterDeleted
    }

    let attributes = task.trip?.attributes ?? TripAttributes()
    let conditions = master.conditions

    if conditions.evaluate(against: attributes) {
      let text = ConditionsFormatter.format(conditions, against: attributes)
      return .ruleMatched(conditionsText: text)
    }
    return .ruleNoLongerMatches
  }

  static func reason(
    for item: TripPackingItem,
    context: ModelContext,
    hideOnUnresolvedMaster: Bool = false
  ) -> WhyDisclosure.Reason? {
    if item.source == .manual {
      return .manual
    }

    guard let masterID = item.masterItemID else {
      return hideOnUnresolvedMaster ? nil : .ruleMasterDeleted
    }

    let master: MasterPackingItem? = fetchMaster(id: masterID, context: context)
    guard let master else {
      return hideOnUnresolvedMaster ? nil : .ruleMasterDeleted
    }

    let attributes = item.trip?.attributes ?? TripAttributes()
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
    do {
      return try context.fetch(descriptor).first
    } catch {
      // A fetch failure here (corrupt store, mid-migration schema mismatch)
      // is indistinguishable from a missing master in the return value. The
      // caller will surface this as `.ruleMasterDeleted`, which is the best
      // user-facing fallback, but the actual error is worth logging so the
      // misleading explanation can be investigated.
      modelLogger.error(
        "WhyResolver.fetchMaster failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      return nil
    }
  }

  private static func fetchMaster(id: UUID, context: ModelContext) -> MasterPackingItem? {
    let descriptor = FetchDescriptor<MasterPackingItem>(
      predicate: #Predicate { $0.id == id }
    )
    do {
      return try context.fetch(descriptor).first
    } catch {
      modelLogger.error(
        "WhyResolver.fetchMaster<MasterPackingItem> failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      return nil
    }
  }
}
