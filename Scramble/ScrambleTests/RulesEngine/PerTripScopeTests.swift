import Foundation
import Testing

@testable import Scramble

/// `userDeletedOnThisTrip` is scoped to a single `TripTask` record. Deleting a
/// rule-driven task on trip A must not affect the same rule on trip B
/// (Req 7.5 / Decision 7).
@Suite("Engine scope: userDeleted is per-trip")
struct PerTripScopeTests {

  // MARK: - Fixtures

  private static let masterID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
  private static let tripAID = UUID(uuidString: "00000000-0000-0000-0000-000000000A01")!
  private static let tripBID = UUID(uuidString: "00000000-0000-0000-0000-000000000B01")!
  private static let taskAID = UUID(uuidString: "00000000-0000-0000-0000-000000000A02")!

  private static func rainyAttributes() -> TripAttributes {
    var a = TripAttributes()
    a.toggle(.weather, value: "rain")
    return a
  }

  private static let master = MasterTaskSnapshot(
    id: masterID,
    name: "Pack umbrella",
    phase: .dayBefore,
    conditions: .match(attribute: .weather, anyOf: ["rain"])
  )

  // MARK: - Trip A: deleted, must be skipped

  @Test("Trip A with userDeleted=true on the rule task: engine skips it, no flag, no re-add")
  func tripADeletedRefIsInert() {
    let tripA = TripSnapshot(
      id: Self.tripAID,
      attributes: Self.rainyAttributes(),
      existingTasks: [
        TripTaskRef(
          id: Self.taskAID,
          masterItemID: Self.masterID,
          currentlyMatchesRules: true,
          pinnedByUser: false,
          source: .rule,
          isCompleted: false,
          userDeletedOnThisTrip: true
        )
      ],
      existingPacking: []
    )
    let plan = compute(trip: tripA, masterTasks: [Self.master], masterPacking: [])
    #expect(plan.toFlagUnmatched.isEmpty)
    #expect(plan.toFlagMatched.isEmpty)
    // Master is still referenced by the deleted record, so no toAdd either.
    #expect(plan.toAddTasks.isEmpty)
  }

  // MARK: - Trip B: untouched, must keep working

  @Test("Trip B without the rule task: engine still adds the rule task")
  func tripBStillAddsTheTask() {
    let tripB = TripSnapshot(
      id: Self.tripBID,
      attributes: Self.rainyAttributes(),
      existingTasks: [],
      existingPacking: []
    )
    let plan = compute(trip: tripB, masterTasks: [Self.master], masterPacking: [])
    #expect(plan.toAddTasks.map(\.id) == [Self.masterID])
  }

  @Test("Trip B that already has the rule task (not deleted): engine no-op")
  func tripBExistingRuleTaskIsNoOp() {
    let tripB = TripSnapshot(
      id: Self.tripBID,
      attributes: Self.rainyAttributes(),
      existingTasks: [
        TripTaskRef(
          id: UUID(),
          masterItemID: Self.masterID,
          currentlyMatchesRules: true,
          pinnedByUser: false,
          source: .rule,
          isCompleted: false,
          userDeletedOnThisTrip: false
        )
      ],
      existingPacking: []
    )
    let plan = compute(trip: tripB, masterTasks: [Self.master], masterPacking: [])
    #expect(plan.toAddTasks.isEmpty)
    #expect(plan.toFlagUnmatched.isEmpty)
    #expect(plan.toFlagMatched.isEmpty)
  }

  // MARK: - Cross-trip: both trips together

  @Test("Same master, two trips: deletion on A leaves B's behaviour untouched")
  func deletionOnAIsScopedToA() {
    let tripA = TripSnapshot(
      id: Self.tripAID,
      attributes: Self.rainyAttributes(),
      existingTasks: [
        TripTaskRef(
          id: Self.taskAID,
          masterItemID: Self.masterID,
          currentlyMatchesRules: true,
          pinnedByUser: false,
          source: .rule,
          isCompleted: false,
          userDeletedOnThisTrip: true
        )
      ],
      existingPacking: []
    )
    let tripB = TripSnapshot(
      id: Self.tripBID,
      attributes: Self.rainyAttributes(),
      existingTasks: [],
      existingPacking: []
    )

    let planA = compute(trip: tripA, masterTasks: [Self.master], masterPacking: [])
    let planB = compute(trip: tripB, masterTasks: [Self.master], masterPacking: [])

    // A: inert.
    #expect(planA.toAddTasks.isEmpty)
    #expect(planA.toFlagMatched.isEmpty)
    #expect(planA.toFlagUnmatched.isEmpty)
    // B: still produces the add.
    #expect(planB.toAddTasks.map(\.id) == [Self.masterID])
  }
}
