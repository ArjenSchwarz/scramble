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

nonisolated struct Plan: Equatable, Sendable {
  let tripID: UUID
  let toAddTasks: [MasterTaskSnapshot]
  let toAddPacking: [MasterPackingSnapshot]
  let toFlagUnmatched: [TripItemRef]
  let toFlagMatched: [TripItemRef]

  init(
    tripID: UUID,
    toAddTasks: [MasterTaskSnapshot],
    toAddPacking: [MasterPackingSnapshot],
    toFlagUnmatched: [TripItemRef],
    toFlagMatched: [TripItemRef]
  ) {
    self.tripID = tripID
    self.toAddTasks = toAddTasks.sorted { $0.id < $1.id }
    self.toAddPacking = toAddPacking.sorted { $0.id < $1.id }
    self.toFlagUnmatched = toFlagUnmatched.sorted(by: Self.refOrder)
    self.toFlagMatched = toFlagMatched.sorted(by: Self.refOrder)
  }

  var isEmpty: Bool {
    toAddTasks.isEmpty && toAddPacking.isEmpty && toFlagUnmatched.isEmpty && toFlagMatched.isEmpty
  }

  private static func refOrder(_ lhs: TripItemRef, _ rhs: TripItemRef) -> Bool {
    if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
    return lhs.id < rhs.id
  }
}
