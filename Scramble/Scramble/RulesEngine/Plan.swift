import Foundation

nonisolated struct TripItemRef: Equatable, Hashable, Sendable {
  nonisolated enum Kind: String, Sendable, Comparable {
    case task
    case packing

    static func < (lhs: Kind, rhs: Kind) -> Bool {
      lhs.rawValue < rhs.rawValue
    }
  }

  let kind: Kind
  let id: UUID
}

/// A single category projection to write onto an existing master-derived trip
/// item (feature `packing-item-categories`, Decision 2/6). Carries the value —
/// including `nil` for a clear — so `apply` can stamp it verbatim.
nonisolated struct PackingCategoryRestamp: Equatable, Sendable {
  let id: UUID
  let category: String?
}

nonisolated struct Plan: Equatable, Sendable {
  let tripID: UUID
  let toAddTasks: [MasterTaskSnapshot]
  let toAddPacking: [MasterPackingSnapshot]
  let toFlagUnmatched: [TripItemRef]
  let toFlagMatched: [TripItemRef]
  /// Category re-stamps for existing master-derived trip items (Decision 2/6).
  /// Kept sorted by id. Compare-before-write in `compute` means only items
  /// whose category actually differs from the master appear here, so an empty
  /// array is the steady state once converged.
  let toRestampCategory: [PackingCategoryRestamp]

  init(
    tripID: UUID,
    toAddTasks: [MasterTaskSnapshot],
    toAddPacking: [MasterPackingSnapshot],
    toFlagUnmatched: [TripItemRef],
    toFlagMatched: [TripItemRef],
    toRestampCategory: [PackingCategoryRestamp] = []
  ) {
    self.tripID = tripID
    self.toAddTasks = toAddTasks.sorted { $0.id < $1.id }
    self.toAddPacking = toAddPacking.sorted { $0.id < $1.id }
    self.toFlagUnmatched = toFlagUnmatched.sorted(by: Self.refOrder)
    self.toFlagMatched = toFlagMatched.sorted(by: Self.refOrder)
    self.toRestampCategory = toRestampCategory.sorted { $0.id < $1.id }
  }

  var isEmpty: Bool {
    toAddTasks.isEmpty && toAddPacking.isEmpty && toFlagUnmatched.isEmpty
      && toFlagMatched.isEmpty && toRestampCategory.isEmpty
  }

  private static func refOrder(_ lhs: TripItemRef, _ rhs: TripItemRef) -> Bool {
    if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
    return lhs.id < rhs.id
  }
}
