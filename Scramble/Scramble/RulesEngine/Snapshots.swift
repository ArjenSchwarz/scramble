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
}

nonisolated struct TripPackingItemRef: Equatable, Hashable, Sendable {
  let id: UUID
  let masterItemID: UUID?
  let currentlyMatchesRules: Bool
  let pinnedByUser: Bool
  let source: ItemSource
  let state: PackingState
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
}
