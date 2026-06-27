import Foundation

nonisolated struct TripSnapshot: Equatable, Sendable {
  let id: UUID
  let attributes: TripAttributes
  let existingTasks: [TripTaskRef]
  let existingPacking: [TripPackingItemRef]
}

nonisolated struct TripTaskRef: Equatable, Hashable, Sendable {
  let id: UUID
  let masterItemID: UUID?
  let currentlyMatchesRules: Bool
  let pinnedByUser: Bool
  let source: ItemSource
  let isCompleted: Bool
  /// Phase 3, Decision 7: a user-deleted rule task is inert in the engine
  /// (skipped in `classifyTaskRefs`, never written to in `flagTasks`).
  let userDeletedOnThisTrip: Bool
}

nonisolated struct TripPackingItemRef: Equatable, Hashable, Sendable {
  let id: UUID
  let masterItemID: UUID?
  let currentlyMatchesRules: Bool
  let pinnedByUser: Bool
  let source: ItemSource
  let state: PackingState
  /// Current stored category, captured purely for the re-stamp diff
  /// (feature `packing-item-categories`, Decision 2). `nil` ⇒ uncategorised.
  /// Not a matching input — `compute` only exact-string compares it against
  /// the master's category to decide whether to emit a re-stamp.
  let category: String?

  /// Explicit memberwise init so `category` can carry a `nil` default — the
  /// many existing call sites (tests, `PlanTests`) predate the field and pass
  /// only the original six members. The runner capture site passes `category`.
  init(
    id: UUID,
    masterItemID: UUID?,
    currentlyMatchesRules: Bool,
    pinnedByUser: Bool,
    source: ItemSource,
    state: PackingState,
    category: String? = nil
  ) {
    self.id = id
    self.masterItemID = masterItemID
    self.currentlyMatchesRules = currentlyMatchesRules
    self.pinnedByUser = pinnedByUser
    self.source = source
    self.state = state
    self.category = category
  }
}

nonisolated struct MasterTaskSnapshot: Equatable, Hashable, Sendable {
  let id: UUID
  let name: String
  let phase: Phase
  let conditions: ItemConditions
}

nonisolated struct MasterPackingSnapshot: Equatable, Hashable, Sendable {
  let id: UUID
  let name: String
  let personID: UUID
  let conditions: ItemConditions
  /// Source category projected onto derived trip items (feature
  /// `packing-item-categories`, Decision 2). `nil` ⇒ uncategorised. Exact-string
  /// compared against the trip item's category in `compute` to emit re-stamps,
  /// and stamped at creation in `insertAddedPacking` (Req 3.1).
  let category: String?

  /// Explicit memberwise init so `category` can carry a `nil` default —
  /// existing call sites (tests, `PlanTests`) predate the field. The runner
  /// snapshot-capture site passes `category`.
  init(
    id: UUID,
    name: String,
    personID: UUID,
    conditions: ItemConditions,
    category: String? = nil
  ) {
    self.id = id
    self.name = name
    self.personID = personID
    self.conditions = conditions
    self.category = category
  }
}
