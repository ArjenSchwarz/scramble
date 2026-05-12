import Foundation
import Testing

@testable import Scramble

@Suite("RulesEngine compute(_:masterTasks:masterPacking:) — property-based")
struct ComputeIdempotenceTests {

  // MARK: - Random fixture generator

  /// Deterministic, seedable PRNG so failures reproduce.
  private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xDEADBEEFCAFEBABE : seed }
    mutating func next() -> UInt64 {
      // SplitMix64
      state &+= 0x9E3779B97F4A7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
      z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
      return z ^ (z >> 31)
    }
  }

  /// All v1 attribute values used during generation.
  private static let weatherValues = ["rain", "cold", "hot", "sun"]
  private static let scopeValues = ["domestic", "international"]
  private static let purposeValues = ["leisure", "work"]
  private static let transportValues = ["car", "plane", "train"]
  private static let durationValues = ["short", "weekend", "week"]

  private static func attributeDomain(_ attr: TripAttribute) -> [String] {
    switch attr {
    case .duration: return durationValues
    case .transport: return transportValues
    case .scope: return scopeValues
    case .weather: return weatherValues
    case .purpose: return purposeValues
    }
  }

  private static func randomAttributes(rng: inout SeededGenerator) -> TripAttributes {
    var attrs = TripAttributes()
    for attribute in TripAttribute.allCases {
      let domain = attributeDomain(attribute)
      for value in domain where Bool.random(using: &rng) {
        attrs.toggle(attribute, value: value)
      }
    }
    return attrs
  }

  private static func randomConditions(rng: inout SeededGenerator) -> ItemConditions {
    // 20% chance .always; else .all of 1-3 .match clauses (v1 shape).
    if UInt64.random(in: 0..<5, using: &rng) == 0 { return .always }
    let attributeCount = Int.random(in: 1...3, using: &rng)
    let attributes = TripAttribute.allCases.shuffled(using: &rng).prefix(attributeCount)
    let matches: [ItemConditions] = attributes.map { attr in
      let domain = attributeDomain(attr)
      let valueCount = Int.random(in: 1...min(3, domain.count), using: &rng)
      let values = Array(domain.shuffled(using: &rng).prefix(valueCount))
      return .match(attribute: attr, anyOf: values.sorted())
    }
    return .all(matches)
  }

  private static func randomMasterTasks(count: Int, rng: inout SeededGenerator) -> [MasterTaskSnapshot] {
    (0..<count).map { i in
      MasterTaskSnapshot(
        id: UUID(),
        name: "Task\(i)",
        phase: Phase.allCases.randomElement(using: &rng) ?? .weeksBefore,
        conditions: randomConditions(rng: &rng)
      )
    }
  }

  private static func randomMasterPacking(
    count: Int, personID: UUID, rng: inout SeededGenerator
  ) -> [MasterPackingSnapshot] {
    (0..<count).map { i in
      MasterPackingSnapshot(
        id: UUID(),
        name: "Pack\(i)",
        personID: personID,
        conditions: randomConditions(rng: &rng)
      )
    }
  }

  /// Build a snapshot with 0..maxExisting existing items per kind, sourced from a random
  /// subset of the masters (so dedup behavior is exercised). Refs default to
  /// `currentlyMatchesRules` chosen at random and `source = .rule` so the engine sees them.
  private static func randomSnapshot(
    tripID: UUID = UUID(),
    maxExisting: Int = 5,
    masterTasks: [MasterTaskSnapshot],
    masterPacking: [MasterPackingSnapshot],
    rng: inout SeededGenerator
  ) -> TripSnapshot {
    let taskCount = Int.random(in: 0...min(maxExisting, masterTasks.count), using: &rng)
    let pickedTasks = Array(masterTasks.shuffled(using: &rng).prefix(taskCount))
    let taskRefs: [TripTaskRef] = pickedTasks.map { master in
      TripTaskRef(
        id: UUID(),
        masterItemID: master.id,
        currentlyMatchesRules: Bool.random(using: &rng),
        pinnedByUser: false,
        source: .rule,
        isCompleted: false
      )
    }
    let packCount = Int.random(in: 0...min(maxExisting, masterPacking.count), using: &rng)
    let pickedPacking = Array(masterPacking.shuffled(using: &rng).prefix(packCount))
    let packRefs: [TripPackingItemRef] = pickedPacking.map { master in
      TripPackingItemRef(
        id: UUID(),
        masterItemID: master.id,
        currentlyMatchesRules: Bool.random(using: &rng),
        pinnedByUser: false,
        source: .rule,
        state: .unpacked
      )
    }
    return TripSnapshot(
      id: tripID,
      attributes: randomAttributes(rng: &rng),
      existingTasks: taskRefs,
      existingPacking: packRefs
    )
  }

  /// Pure-function simulation of `apply`: rewrite the trip snapshot as if the plan had
  /// been written to the store. Used to drive the idempotence property without a
  /// `ModelContainer`.
  private static func applyToSnapshot(plan: Plan, snapshot: TripSnapshot) -> TripSnapshot {
    let tasks = updateTaskFlags(snapshot.existingTasks, plan: plan) + appendedTasks(from: plan)
    let packing = updatePackingFlags(snapshot.existingPacking, plan: plan)
      + appendedPacking(from: plan)
    return TripSnapshot(
      id: snapshot.id,
      attributes: snapshot.attributes,
      existingTasks: tasks,
      existingPacking: packing
    )
  }

  private static func updateTaskFlags(_ refs: [TripTaskRef], plan: Plan) -> [TripTaskRef] {
    let unmatch = Set(plan.toFlagUnmatched.compactMap { $0.kind == .task ? $0.id : nil })
    let match = Set(plan.toFlagMatched.compactMap { $0.kind == .task ? $0.id : nil })
    return refs.map { ref in
      var flag = ref.currentlyMatchesRules
      if unmatch.contains(ref.id) { flag = false }
      if match.contains(ref.id) { flag = true }
      return TripTaskRef(
        id: ref.id,
        masterItemID: ref.masterItemID,
        currentlyMatchesRules: flag,
        pinnedByUser: ref.pinnedByUser,
        source: ref.source,
        isCompleted: ref.isCompleted
      )
    }
  }

  private static func updatePackingFlags(
    _ refs: [TripPackingItemRef], plan: Plan
  ) -> [TripPackingItemRef] {
    let unmatch = Set(plan.toFlagUnmatched.compactMap { $0.kind == .packing ? $0.id : nil })
    let match = Set(plan.toFlagMatched.compactMap { $0.kind == .packing ? $0.id : nil })
    return refs.map { ref in
      var flag = ref.currentlyMatchesRules
      if unmatch.contains(ref.id) { flag = false }
      if match.contains(ref.id) { flag = true }
      return TripPackingItemRef(
        id: ref.id,
        masterItemID: ref.masterItemID,
        currentlyMatchesRules: flag,
        pinnedByUser: ref.pinnedByUser,
        source: ref.source,
        state: ref.state
      )
    }
  }

  private static func appendedTasks(from plan: Plan) -> [TripTaskRef] {
    plan.toAddTasks.map { master in
      TripTaskRef(
        id: UUID(),
        masterItemID: master.id,
        currentlyMatchesRules: true,
        pinnedByUser: false,
        source: .rule,
        isCompleted: false
      )
    }
  }

  private static func appendedPacking(from plan: Plan) -> [TripPackingItemRef] {
    plan.toAddPacking.map { master in
      TripPackingItemRef(
        id: UUID(),
        masterItemID: master.id,
        currentlyMatchesRules: true,
        pinnedByUser: false,
        source: .rule,
        state: .unpacked
      )
    }
  }

  // MARK: - Determinism

  @Test("Determinism: compute(x, m1, m2) == compute(x, m1, m2) across random inputs")
  func determinism() {
    for seed in UInt64(1)...UInt64(40) {
      var rng = SeededGenerator(seed: seed)
      let personID = UUID()
      let masterTasks = Self.randomMasterTasks(count: 8, rng: &rng)
      let masterPacking = Self.randomMasterPacking(count: 8, personID: personID, rng: &rng)
      let snapshot = Self.randomSnapshot(
        masterTasks: masterTasks, masterPacking: masterPacking, rng: &rng)
      let first = compute(trip: snapshot, masterTasks: masterTasks, masterPacking: masterPacking)
      let second = compute(trip: snapshot, masterTasks: masterTasks, masterPacking: masterPacking)
      #expect(first == second, "Determinism violated at seed \(seed)")
    }
  }

  // MARK: - Idempotence

  @Test("Idempotence: applying the plan then recomputing produces an empty plan")
  func idempotence() {
    for seed in UInt64(1)...UInt64(40) {
      var rng = SeededGenerator(seed: seed)
      let personID = UUID()
      let masterTasks = Self.randomMasterTasks(count: 8, rng: &rng)
      let masterPacking = Self.randomMasterPacking(count: 8, personID: personID, rng: &rng)
      let snapshot = Self.randomSnapshot(
        masterTasks: masterTasks, masterPacking: masterPacking, rng: &rng)

      let first = compute(trip: snapshot, masterTasks: masterTasks, masterPacking: masterPacking)
      let after = Self.applyToSnapshot(plan: first, snapshot: snapshot)
      let second = compute(trip: after, masterTasks: masterTasks, masterPacking: masterPacking)

      #expect(second.isEmpty, "Idempotence violated at seed \(seed). Second plan = \(second)")
    }
  }

  // MARK: - No spurious adds

  @Test("No spurious adds: empty attributes + impossible masters → no toAdd entries")
  func noSpuriousAdds() {
    for seed in UInt64(1)...UInt64(40) {
      var rng = SeededGenerator(seed: seed)
      let personID = UUID()
      // All masters use an attribute value the trip will never have.
      let masterTasks: [MasterTaskSnapshot] = (0..<8).map { i in
        MasterTaskSnapshot(
          id: UUID(),
          name: "T\(i)",
          phase: .weeksBefore,
          conditions: .match(attribute: .weather, anyOf: ["__nonexistent\(i)"])
        )
      }
      let masterPacking: [MasterPackingSnapshot] = (0..<8).map { i in
        MasterPackingSnapshot(
          id: UUID(),
          name: "P\(i)",
          personID: personID,
          conditions: .match(attribute: .weather, anyOf: ["__nonexistent\(i)"])
        )
      }
      let snapshot = TripSnapshot(
        id: UUID(),
        attributes: Self.randomAttributes(rng: &rng),
        existingTasks: [],
        existingPacking: []
      )
      let plan = compute(trip: snapshot, masterTasks: masterTasks, masterPacking: masterPacking)
      #expect(plan.toAddTasks.isEmpty, "Spurious toAdd at seed \(seed): \(plan.toAddTasks)")
      #expect(plan.toAddPacking.isEmpty, "Spurious toAdd at seed \(seed): \(plan.toAddPacking)")
    }
  }
}
