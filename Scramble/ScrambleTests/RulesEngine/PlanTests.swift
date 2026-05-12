import Foundation
import Testing

@testable import Scramble

@Suite("RulesEngine Plan + Snapshot value types")
struct PlanTests {

  // MARK: - Fixture helpers

  private static let idA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
  private static let idB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
  private static let idC = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!
  private static let idD = UUID(uuidString: "00000000-0000-0000-0000-00000000000D")!

  private static func taskSnap(id: UUID, name: String = "T") -> MasterTaskSnapshot {
    MasterTaskSnapshot(id: id, name: name, phase: .weeksBefore, conditions: .always)
  }

  private static func packingSnap(id: UUID, name: String = "P") -> MasterPackingSnapshot {
    MasterPackingSnapshot(id: id, name: name, personID: UUID(), conditions: .always)
  }

  // MARK: - TripItemRef.Kind raw values

  @Test("TripItemRef.Kind raw values are 'task' and 'packing'")
  func tripItemRefKindRawValues() {
    #expect(TripItemRef.Kind.task.rawValue == "task")
    #expect(TripItemRef.Kind.packing.rawValue == "packing")
  }

  // MARK: - Equatable conformance

  @Test("MasterTaskSnapshot Equatable")
  func masterTaskSnapshotEquatable() {
    let a = MasterTaskSnapshot(id: Self.idA, name: "x", phase: .weeksBefore, conditions: .always)
    let b = MasterTaskSnapshot(id: Self.idA, name: "x", phase: .weeksBefore, conditions: .always)
    let c = MasterTaskSnapshot(id: Self.idB, name: "x", phase: .weeksBefore, conditions: .always)
    #expect(a == b)
    #expect(a != c)
  }

  @Test("MasterPackingSnapshot Equatable")
  func masterPackingSnapshotEquatable() {
    let personID = UUID()
    let a = MasterPackingSnapshot(id: Self.idA, name: "x", personID: personID, conditions: .always)
    let b = MasterPackingSnapshot(id: Self.idA, name: "x", personID: personID, conditions: .always)
    let c = MasterPackingSnapshot(id: Self.idA, name: "y", personID: personID, conditions: .always)
    #expect(a == b)
    #expect(a != c)
  }

  @Test("TripTaskRef Equatable")
  func tripTaskRefEquatable() {
    let a = TripTaskRef(
      id: Self.idA,
      masterItemID: Self.idB,
      currentlyMatchesRules: true,
      pinnedByUser: false,
      source: .rule,
      isCompleted: false
    )
    let b = TripTaskRef(
      id: Self.idA,
      masterItemID: Self.idB,
      currentlyMatchesRules: true,
      pinnedByUser: false,
      source: .rule,
      isCompleted: false
    )
    let c = TripTaskRef(
      id: Self.idA,
      masterItemID: Self.idB,
      currentlyMatchesRules: false,
      pinnedByUser: false,
      source: .rule,
      isCompleted: false
    )
    #expect(a == b)
    #expect(a != c)
  }

  @Test("TripPackingItemRef Equatable")
  func tripPackingItemRefEquatable() {
    let a = TripPackingItemRef(
      id: Self.idA,
      masterItemID: Self.idB,
      currentlyMatchesRules: true,
      pinnedByUser: false,
      source: .rule,
      state: .unpacked
    )
    let b = TripPackingItemRef(
      id: Self.idA,
      masterItemID: Self.idB,
      currentlyMatchesRules: true,
      pinnedByUser: false,
      source: .rule,
      state: .unpacked
    )
    let c = TripPackingItemRef(
      id: Self.idA,
      masterItemID: Self.idB,
      currentlyMatchesRules: true,
      pinnedByUser: false,
      source: .rule,
      state: .packed
    )
    #expect(a == b)
    #expect(a != c)
  }

  @Test("TripSnapshot Equatable")
  func tripSnapshotEquatable() {
    var attrs = TripAttributes()
    attrs.setSingle(.duration, value: "week")
    let task = TripTaskRef(
      id: Self.idA,
      masterItemID: nil,
      currentlyMatchesRules: true,
      pinnedByUser: false,
      source: .manual,
      isCompleted: false
    )
    let a = TripSnapshot(
      id: Self.idC, attributes: attrs, existingTasks: [task], existingPacking: [])
    let b = TripSnapshot(
      id: Self.idC, attributes: attrs, existingTasks: [task], existingPacking: [])
    let c = TripSnapshot(
      id: Self.idD, attributes: attrs, existingTasks: [task], existingPacking: [])
    #expect(a == b)
    #expect(a != c)
  }

  // MARK: - Hashable conformance

  @Test("MasterTaskSnapshot Hashable")
  func masterTaskSnapshotHashable() {
    let a = Self.taskSnap(id: Self.idA)
    let b = Self.taskSnap(id: Self.idA)
    let c = Self.taskSnap(id: Self.idB)
    let set: Set<MasterTaskSnapshot> = [a, b, c]
    #expect(set.count == 2)
  }

  @Test("MasterPackingSnapshot Hashable")
  func masterPackingSnapshotHashable() {
    let personID = UUID()
    let a = MasterPackingSnapshot(id: Self.idA, name: "x", personID: personID, conditions: .always)
    let b = MasterPackingSnapshot(id: Self.idA, name: "x", personID: personID, conditions: .always)
    let c = MasterPackingSnapshot(id: Self.idB, name: "x", personID: personID, conditions: .always)
    let set: Set<MasterPackingSnapshot> = [a, b, c]
    #expect(set.count == 2)
  }

  @Test("TripTaskRef Hashable")
  func tripTaskRefHashable() {
    let a = TripTaskRef(
      id: Self.idA,
      masterItemID: nil,
      currentlyMatchesRules: true,
      pinnedByUser: false,
      source: .rule,
      isCompleted: false
    )
    let set: Set<TripTaskRef> = [a, a]
    #expect(set.count == 1)
  }

  @Test("TripPackingItemRef Hashable")
  func tripPackingItemRefHashable() {
    let a = TripPackingItemRef(
      id: Self.idA,
      masterItemID: nil,
      currentlyMatchesRules: true,
      pinnedByUser: false,
      source: .rule,
      state: .unpacked
    )
    let set: Set<TripPackingItemRef> = [a, a]
    #expect(set.count == 1)
  }

  @Test("TripItemRef Hashable")
  func tripItemRefHashable() {
    let a = TripItemRef(kind: .task, id: Self.idA)
    let b = TripItemRef(kind: .packing, id: Self.idA)
    let c = TripItemRef(kind: .task, id: Self.idA)
    let set: Set<TripItemRef> = [a, b, c]
    #expect(set.count == 2)
  }

  // MARK: - Sendable conformance (compile-time check)

  @Test("Snapshot + Plan value types are Sendable")
  func sendableConformance() async {
    let trip = TripSnapshot(
      id: Self.idA, attributes: TripAttributes(), existingTasks: [], existingPacking: [])
    let taskSnap = Self.taskSnap(id: Self.idA)
    let packingSnap = Self.packingSnap(id: Self.idA)
    let taskRef = TripTaskRef(
      id: Self.idA,
      masterItemID: nil,
      currentlyMatchesRules: true,
      pinnedByUser: false,
      source: .rule,
      isCompleted: false
    )
    let packingRef = TripPackingItemRef(
      id: Self.idA,
      masterItemID: nil,
      currentlyMatchesRules: true,
      pinnedByUser: false,
      source: .rule,
      state: .unpacked
    )
    let ref = TripItemRef(kind: .task, id: Self.idA)
    let plan = Plan(
      tripID: Self.idA,
      toAddTasks: [taskSnap],
      toAddPacking: [packingSnap],
      toFlagUnmatched: [ref],
      toFlagMatched: []
    )
    // Crossing actor boundary requires Sendable.
    await Task.detached {
      _ = trip
      _ = taskSnap
      _ = packingSnap
      _ = taskRef
      _ = packingRef
      _ = ref
      _ = plan
    }.value
  }

  // MARK: - Plan sort invariant

  @Test("Plan sorts toAddTasks by id ascending")
  func planSortsToAddTasksByID() {
    let plan = Plan(
      tripID: Self.idA,
      toAddTasks: [
        Self.taskSnap(id: Self.idC), Self.taskSnap(id: Self.idA), Self.taskSnap(id: Self.idB),
      ],
      toAddPacking: [],
      toFlagUnmatched: [],
      toFlagMatched: []
    )
    #expect(plan.toAddTasks.map(\.id) == [Self.idA, Self.idB, Self.idC])
  }

  @Test("Plan sorts toAddPacking by id ascending")
  func planSortsToAddPackingByID() {
    let plan = Plan(
      tripID: Self.idA,
      toAddTasks: [],
      toAddPacking: [
        Self.packingSnap(id: Self.idC), Self.packingSnap(id: Self.idA),
        Self.packingSnap(id: Self.idB),
      ],
      toFlagUnmatched: [],
      toFlagMatched: []
    )
    #expect(plan.toAddPacking.map(\.id) == [Self.idA, Self.idB, Self.idC])
  }

  @Test("Plan sorts toFlagUnmatched by (kind, id) ascending")
  func planSortsToFlagUnmatchedByKindThenID() {
    let plan = Plan(
      tripID: Self.idA,
      toAddTasks: [],
      toAddPacking: [],
      toFlagUnmatched: [
        TripItemRef(kind: .packing, id: Self.idB),
        TripItemRef(kind: .task, id: Self.idC),
        TripItemRef(kind: .packing, id: Self.idA),
        TripItemRef(kind: .task, id: Self.idA),
      ],
      toFlagMatched: []
    )
    // 'packing' < 'task' alphabetically, so packing items come first, sorted by id.
    #expect(
      plan.toFlagUnmatched == [
        TripItemRef(kind: .packing, id: Self.idA),
        TripItemRef(kind: .packing, id: Self.idB),
        TripItemRef(kind: .task, id: Self.idA),
        TripItemRef(kind: .task, id: Self.idC),
      ])
  }

  @Test("Plan sorts toFlagMatched by (kind, id) ascending")
  func planSortsToFlagMatchedByKindThenID() {
    let plan = Plan(
      tripID: Self.idA,
      toAddTasks: [],
      toAddPacking: [],
      toFlagUnmatched: [],
      toFlagMatched: [
        TripItemRef(kind: .task, id: Self.idB),
        TripItemRef(kind: .packing, id: Self.idC),
        TripItemRef(kind: .task, id: Self.idA),
      ]
    )
    #expect(
      plan.toFlagMatched == [
        TripItemRef(kind: .packing, id: Self.idC),
        TripItemRef(kind: .task, id: Self.idA),
        TripItemRef(kind: .task, id: Self.idB),
      ])
  }

  // MARK: - Plan.isEmpty

  @Test("Plan.isEmpty true when all four collections empty")
  func planIsEmptyWhenAllEmpty() {
    let plan = Plan(
      tripID: Self.idA,
      toAddTasks: [],
      toAddPacking: [],
      toFlagUnmatched: [],
      toFlagMatched: []
    )
    #expect(plan.isEmpty)
  }

  @Test("Plan.isEmpty false when any collection non-empty")
  func planIsEmptyFalseWhenAnyNonEmpty() {
    let base = Plan(
      tripID: Self.idA,
      toAddTasks: [],
      toAddPacking: [],
      toFlagUnmatched: [],
      toFlagMatched: []
    )
    #expect(base.isEmpty)

    let withTask = Plan(
      tripID: Self.idA,
      toAddTasks: [Self.taskSnap(id: Self.idA)],
      toAddPacking: [],
      toFlagUnmatched: [],
      toFlagMatched: []
    )
    #expect(!withTask.isEmpty)

    let withPacking = Plan(
      tripID: Self.idA,
      toAddTasks: [],
      toAddPacking: [Self.packingSnap(id: Self.idA)],
      toFlagUnmatched: [],
      toFlagMatched: []
    )
    #expect(!withPacking.isEmpty)

    let withUnmatched = Plan(
      tripID: Self.idA,
      toAddTasks: [],
      toAddPacking: [],
      toFlagUnmatched: [TripItemRef(kind: .task, id: Self.idA)],
      toFlagMatched: []
    )
    #expect(!withUnmatched.isEmpty)

    let withMatched = Plan(
      tripID: Self.idA,
      toAddTasks: [],
      toAddPacking: [],
      toFlagUnmatched: [],
      toFlagMatched: [TripItemRef(kind: .task, id: Self.idA)]
    )
    #expect(!withMatched.isEmpty)
  }
}
