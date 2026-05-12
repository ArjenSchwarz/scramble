import Foundation
import Testing

@testable import Scramble

@Suite("RulesEngine compute(_:masterTasks:masterPacking:)")
struct ComputeTests {

  // MARK: - Fixture helpers

  private static let tripID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F0")!
  private static let personID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!
  private static let masterIDA = UUID(uuidString: "00000000-0000-0000-0000-0000000000A0")!
  private static let masterIDB = UUID(uuidString: "00000000-0000-0000-0000-0000000000B0")!
  private static let masterIDC = UUID(uuidString: "00000000-0000-0000-0000-0000000000C0")!
  private static let tripItemIDA = UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!
  private static let tripItemIDB = UUID(uuidString: "00000000-0000-0000-0000-00000000A002")!
  private static let tripItemIDC = UUID(uuidString: "00000000-0000-0000-0000-00000000A003")!

  private static func rainyTripAttributes() -> TripAttributes {
    var attrs = TripAttributes()
    attrs.toggle(.weather, value: "rain")
    return attrs
  }

  private static func sunnyTripAttributes() -> TripAttributes {
    var attrs = TripAttributes()
    attrs.toggle(.weather, value: "sun")
    return attrs
  }

  private static func taskMaster(
    id: UUID = masterIDA,
    name: String = "Pack umbrella",
    conditions: ItemConditions = .match(attribute: .weather, anyOf: ["rain"])
  ) -> MasterTaskSnapshot {
    MasterTaskSnapshot(id: id, name: name, phase: .dayBefore, conditions: conditions)
  }

  private static func packingMaster(
    id: UUID = masterIDA,
    name: String = "Rain jacket",
    conditions: ItemConditions = .match(attribute: .weather, anyOf: ["rain"])
  ) -> MasterPackingSnapshot {
    MasterPackingSnapshot(id: id, name: name, personID: personID, conditions: conditions)
  }

  private static func taskRef(
    id: UUID = tripItemIDA,
    masterItemID: UUID? = masterIDA,
    currentlyMatchesRules: Bool = true,
    pinnedByUser: Bool = false,
    source: ItemSource = .rule,
    isCompleted: Bool = false,
    userDeletedOnThisTrip: Bool = false
  ) -> TripTaskRef {
    TripTaskRef(
      id: id,
      masterItemID: masterItemID,
      currentlyMatchesRules: currentlyMatchesRules,
      pinnedByUser: pinnedByUser,
      source: source,
      isCompleted: isCompleted,
      userDeletedOnThisTrip: userDeletedOnThisTrip
    )
  }

  private static func packingRef(
    id: UUID = tripItemIDA,
    masterItemID: UUID? = masterIDA,
    currentlyMatchesRules: Bool = true,
    pinnedByUser: Bool = false,
    source: ItemSource = .rule,
    state: PackingState = .unpacked
  ) -> TripPackingItemRef {
    TripPackingItemRef(
      id: id,
      masterItemID: masterItemID,
      currentlyMatchesRules: currentlyMatchesRules,
      pinnedByUser: pinnedByUser,
      source: source,
      state: state
    )
  }

  private static func snapshot(
    attributes: TripAttributes = rainyTripAttributes(),
    tasks: [TripTaskRef] = [],
    packing: [TripPackingItemRef] = []
  ) -> TripSnapshot {
    TripSnapshot(
      id: tripID,
      attributes: attributes,
      existingTasks: tasks,
      existingPacking: packing
    )
  }

  // MARK: - Add path

  @Test("Add: matching master not referenced on trip emits to toAddTasks")
  func addMatchingTask() {
    let plan = compute(
      trip: Self.snapshot(),
      masterTasks: [Self.taskMaster()],
      masterPacking: []
    )
    #expect(plan.toAddTasks.map(\.id) == [Self.masterIDA])
    #expect(plan.toAddPacking.isEmpty)
    #expect(plan.toFlagUnmatched.isEmpty)
    #expect(plan.toFlagMatched.isEmpty)
  }

  @Test("Add: matching master not referenced on trip emits to toAddPacking")
  func addMatchingPacking() {
    let plan = compute(
      trip: Self.snapshot(),
      masterTasks: [],
      masterPacking: [Self.packingMaster()]
    )
    #expect(plan.toAddPacking.map(\.id) == [Self.masterIDA])
    #expect(plan.toAddTasks.isEmpty)
  }

  @Test("Add: non-matching master not emitted to toAdd")
  func addSkipsNonMatching() {
    let plan = compute(
      trip: Self.snapshot(attributes: Self.sunnyTripAttributes()),
      masterTasks: [Self.taskMaster()],
      masterPacking: [Self.packingMaster()]
    )
    #expect(plan.toAddTasks.isEmpty)
    #expect(plan.toAddPacking.isEmpty)
  }

  @Test("Add: .always always matches and is emitted")
  func addAlwaysAlwaysMatches() {
    let master = Self.taskMaster(conditions: .always)
    let plan = compute(
      trip: Self.snapshot(attributes: TripAttributes()),
      masterTasks: [master],
      masterPacking: []
    )
    #expect(plan.toAddTasks == [master])
  }

  // MARK: - Dedup (AC 6.4)

  @Test("Dedup: master already referenced on trip is not re-added (task ref)")
  func dedupTaskRef() {
    let plan = compute(
      trip: Self.snapshot(tasks: [Self.taskRef()]),
      masterTasks: [Self.taskMaster()],
      masterPacking: []
    )
    #expect(plan.toAddTasks.isEmpty)
  }

  @Test("Dedup: master already referenced on trip is not re-added (packing ref)")
  func dedupPackingRef() {
    let plan = compute(
      trip: Self.snapshot(packing: [Self.packingRef()]),
      masterTasks: [],
      masterPacking: [Self.packingMaster()]
    )
    #expect(plan.toAddPacking.isEmpty)
  }

  @Test("Dedup: duplicate refs to the same masterItemID are tolerated as single 'present'")
  func dedupToleratesDuplicates() {
    let refA = Self.taskRef(id: Self.tripItemIDA)
    let refB = Self.taskRef(id: Self.tripItemIDB)
    let plan = compute(
      trip: Self.snapshot(tasks: [refA, refB]),
      masterTasks: [Self.taskMaster()],
      masterPacking: []
    )
    #expect(plan.toAddTasks.isEmpty)
  }

  // MARK: - 4-way decision matrix

  @Test("Matrix: currentlyMatchesRules=true + conditions=true → no-op")
  func matrixTrueTrue() {
    let plan = compute(
      trip: Self.snapshot(tasks: [Self.taskRef(currentlyMatchesRules: true)]),
      masterTasks: [Self.taskMaster()],
      masterPacking: []
    )
    #expect(plan.toFlagMatched.isEmpty)
    #expect(plan.toFlagUnmatched.isEmpty)
    #expect(plan.toAddTasks.isEmpty)
  }

  @Test("Matrix: currentlyMatchesRules=true + conditions=false → toFlagUnmatched")
  func matrixTrueFalse() {
    let plan = compute(
      trip: Self.snapshot(
        attributes: Self.sunnyTripAttributes(),
        tasks: [Self.taskRef(currentlyMatchesRules: true)]
      ),
      masterTasks: [Self.taskMaster()],
      masterPacking: []
    )
    #expect(plan.toFlagUnmatched == [TripItemRef(kind: .task, id: Self.tripItemIDA)])
    #expect(plan.toFlagMatched.isEmpty)
  }

  @Test("Matrix: currentlyMatchesRules=false + conditions=true → toFlagMatched")
  func matrixFalseTrue() {
    let plan = compute(
      trip: Self.snapshot(tasks: [Self.taskRef(currentlyMatchesRules: false)]),
      masterTasks: [Self.taskMaster()],
      masterPacking: []
    )
    #expect(plan.toFlagMatched == [TripItemRef(kind: .task, id: Self.tripItemIDA)])
    #expect(plan.toFlagUnmatched.isEmpty)
  }

  @Test("Matrix: currentlyMatchesRules=false + conditions=false → no-op")
  func matrixFalseFalse() {
    let plan = compute(
      trip: Self.snapshot(
        attributes: Self.sunnyTripAttributes(),
        tasks: [Self.taskRef(currentlyMatchesRules: false)]
      ),
      masterTasks: [Self.taskMaster()],
      masterPacking: []
    )
    #expect(plan.toFlagMatched.isEmpty)
    #expect(plan.toFlagUnmatched.isEmpty)
  }

  // MARK: - Exclusion table — protects from toFlagUnmatched but NOT toFlagMatched

  @Test("Exclusion: pinned task protected from toFlagUnmatched")
  func pinExcludesFromUnmatched() {
    let plan = compute(
      trip: Self.snapshot(
        attributes: Self.sunnyTripAttributes(),
        tasks: [Self.taskRef(currentlyMatchesRules: true, pinnedByUser: true)]
      ),
      masterTasks: [Self.taskMaster()],
      masterPacking: []
    )
    #expect(plan.toFlagUnmatched.isEmpty)
  }

  @Test("Exclusion: pinned task does NOT block toFlagMatched (AC 6.1 final sentence)")
  func pinDoesNotExcludeFromMatched() {
    let plan = compute(
      trip: Self.snapshot(
        tasks: [Self.taskRef(currentlyMatchesRules: false, pinnedByUser: true)]
      ),
      masterTasks: [Self.taskMaster()],
      masterPacking: []
    )
    #expect(plan.toFlagMatched == [TripItemRef(kind: .task, id: Self.tripItemIDA)])
  }

  @Test("Exclusion: completed task protected from toFlagUnmatched (AC 6.2)")
  func completedExcludesFromUnmatched() {
    let plan = compute(
      trip: Self.snapshot(
        attributes: Self.sunnyTripAttributes(),
        tasks: [Self.taskRef(currentlyMatchesRules: true, isCompleted: true)]
      ),
      masterTasks: [Self.taskMaster()],
      masterPacking: []
    )
    #expect(plan.toFlagUnmatched.isEmpty)
  }

  @Test("Exclusion: completed task remains eligible for toFlagMatched")
  func completedDoesNotExcludeFromMatched() {
    let plan = compute(
      trip: Self.snapshot(
        tasks: [Self.taskRef(currentlyMatchesRules: false, isCompleted: true)]
      ),
      masterTasks: [Self.taskMaster()],
      masterPacking: []
    )
    #expect(plan.toFlagMatched == [TripItemRef(kind: .task, id: Self.tripItemIDA)])
  }

  @Test("Exclusion: packed item protected from toFlagUnmatched (AC 6.3)")
  func packedExcludesFromUnmatched() {
    let plan = compute(
      trip: Self.snapshot(
        attributes: Self.sunnyTripAttributes(),
        packing: [Self.packingRef(currentlyMatchesRules: true, state: .packed)]
      ),
      masterTasks: [],
      masterPacking: [Self.packingMaster()]
    )
    #expect(plan.toFlagUnmatched.isEmpty)
  }

  @Test("Exclusion: repacked item protected from toFlagUnmatched (AC 6.3)")
  func repackedExcludesFromUnmatched() {
    let plan = compute(
      trip: Self.snapshot(
        attributes: Self.sunnyTripAttributes(),
        packing: [Self.packingRef(currentlyMatchesRules: true, state: .repacked)]
      ),
      masterTasks: [],
      masterPacking: [Self.packingMaster()]
    )
    #expect(plan.toFlagUnmatched.isEmpty)
  }

  @Test("Exclusion: excluded item protected from toFlagUnmatched (AC 6.3)")
  func excludedExcludesFromUnmatched() {
    let plan = compute(
      trip: Self.snapshot(
        attributes: Self.sunnyTripAttributes(),
        packing: [Self.packingRef(currentlyMatchesRules: true, state: .excluded)]
      ),
      masterTasks: [],
      masterPacking: [Self.packingMaster()]
    )
    #expect(plan.toFlagUnmatched.isEmpty)
  }

  @Test("Exclusion: unpacked item NOT protected from toFlagUnmatched")
  func unpackedNotExcludedFromUnmatched() {
    let plan = compute(
      trip: Self.snapshot(
        attributes: Self.sunnyTripAttributes(),
        packing: [Self.packingRef(currentlyMatchesRules: true, state: .unpacked)]
      ),
      masterTasks: [],
      masterPacking: [Self.packingMaster()]
    )
    #expect(plan.toFlagUnmatched == [TripItemRef(kind: .packing, id: Self.tripItemIDA)])
  }

  @Test("Exclusion: packed item remains eligible for toFlagMatched")
  func packedDoesNotExcludeFromMatched() {
    let plan = compute(
      trip: Self.snapshot(
        packing: [Self.packingRef(currentlyMatchesRules: false, state: .packed)]
      ),
      masterTasks: [],
      masterPacking: [Self.packingMaster()]
    )
    #expect(plan.toFlagMatched == [TripItemRef(kind: .packing, id: Self.tripItemIDA)])
  }

  // MARK: - source == .manual (AC 4.6)

  @Test("Manual task: never emitted to toFlagUnmatched even when master would flag it")
  func manualTaskNeverFlaggedUnmatched() {
    let plan = compute(
      trip: Self.snapshot(
        attributes: Self.sunnyTripAttributes(),
        tasks: [Self.taskRef(currentlyMatchesRules: true, source: .manual)]
      ),
      masterTasks: [Self.taskMaster()],
      masterPacking: []
    )
    #expect(plan.toFlagUnmatched.isEmpty)
  }

  @Test("Manual task: never emitted to toFlagMatched")
  func manualTaskNeverFlaggedMatched() {
    let plan = compute(
      trip: Self.snapshot(
        tasks: [Self.taskRef(currentlyMatchesRules: false, source: .manual)]
      ),
      masterTasks: [Self.taskMaster()],
      masterPacking: []
    )
    #expect(plan.toFlagMatched.isEmpty)
  }

  @Test("Manual packing item: never emitted to flag collections")
  func manualPackingNeverFlagged() {
    let plan = compute(
      trip: Self.snapshot(
        attributes: Self.sunnyTripAttributes(),
        packing: [Self.packingRef(currentlyMatchesRules: true, source: .manual)]
      ),
      masterTasks: [],
      masterPacking: [Self.packingMaster()]
    )
    #expect(plan.toFlagUnmatched.isEmpty)
    #expect(plan.toFlagMatched.isEmpty)
  }

  // MARK: - Missing master (AC 4.7)

  @Test("Missing master: dangling masterItemID classified as conditions=false")
  func danglingMasterClassifiedFalse() {
    // currentlyMatchesRules=true + master missing → conditions evaluate false → toFlagUnmatched.
    let plan = compute(
      trip: Self.snapshot(tasks: [Self.taskRef(currentlyMatchesRules: true)]),
      masterTasks: [],
      masterPacking: []
    )
    #expect(plan.toFlagUnmatched == [TripItemRef(kind: .task, id: Self.tripItemIDA)])
  }

  @Test("Missing master: already-unmatched ref → no-op")
  func danglingMasterAlreadyUnmatchedNoOp() {
    let plan = compute(
      trip: Self.snapshot(tasks: [Self.taskRef(currentlyMatchesRules: false)]),
      masterTasks: [],
      masterPacking: []
    )
    #expect(plan.toFlagUnmatched.isEmpty)
    #expect(plan.toFlagMatched.isEmpty)
  }

  @Test("Missing master: dangling ref subject to pin exclusion")
  func danglingMasterRespectsPin() {
    let plan = compute(
      trip: Self.snapshot(
        tasks: [Self.taskRef(currentlyMatchesRules: true, pinnedByUser: true)]
      ),
      masterTasks: [],
      masterPacking: []
    )
    #expect(plan.toFlagUnmatched.isEmpty)
  }

  // MARK: - nil masterItemID (manual without source flag)

  @Test("Ref with nil masterItemID: never touched")
  func nilMasterItemIDIgnored() {
    // A nil masterItemID is a manual item; the .manual source check would also exclude it,
    // but we test the nil path explicitly because the implementation builds the referenced-id
    // set by ignoring nils.
    let ref = Self.taskRef(masterItemID: nil, source: .manual)
    let plan = compute(
      trip: Self.snapshot(tasks: [ref]),
      masterTasks: [Self.taskMaster()],
      masterPacking: []
    )
    #expect(plan.toFlagUnmatched.isEmpty)
    #expect(plan.toFlagMatched.isEmpty)
    // And the existing manual item does NOT block re-adding the master.
    #expect(plan.toAddTasks.map(\.id) == [Self.masterIDA])
  }

  // MARK: - Defensive: .match(_, anyOf: []) evaluates false

  @Test(".match(_, anyOf: []) is treated as conditions=false")
  func emptyAnyOfEvaluatesFalse() {
    let master = Self.taskMaster(conditions: .match(attribute: .weather, anyOf: []))
    // Add path: empty anyOf never matches, so no toAdd.
    let plan = compute(
      trip: Self.snapshot(),
      masterTasks: [master],
      masterPacking: []
    )
    #expect(plan.toAddTasks.isEmpty)
  }

  @Test(".match(_, anyOf: []) flags an existing matched ref as unmatched")
  func emptyAnyOfFlagsExistingUnmatched() {
    let master = Self.taskMaster(conditions: .match(attribute: .weather, anyOf: []))
    let plan = compute(
      trip: Self.snapshot(tasks: [Self.taskRef(currentlyMatchesRules: true)]),
      masterTasks: [master],
      masterPacking: []
    )
    #expect(plan.toFlagUnmatched == [TripItemRef(kind: .task, id: Self.tripItemIDA)])
  }

  // MARK: - Sort invariants

  @Test("toAddTasks sorted by master id ascending")
  func toAddTasksSorted() {
    let plan = compute(
      trip: Self.snapshot(),
      masterTasks: [
        Self.taskMaster(id: Self.masterIDC),
        Self.taskMaster(id: Self.masterIDA),
        Self.taskMaster(id: Self.masterIDB)
      ],
      masterPacking: []
    )
    #expect(plan.toAddTasks.map(\.id) == [Self.masterIDA, Self.masterIDB, Self.masterIDC])
  }

  @Test("toAddPacking sorted by master id ascending")
  func toAddPackingSorted() {
    let plan = compute(
      trip: Self.snapshot(),
      masterTasks: [],
      masterPacking: [
        Self.packingMaster(id: Self.masterIDC),
        Self.packingMaster(id: Self.masterIDA),
        Self.packingMaster(id: Self.masterIDB)
      ]
    )
    #expect(plan.toAddPacking.map(\.id) == [Self.masterIDA, Self.masterIDB, Self.masterIDC])
  }

  @Test("toFlagUnmatched sorted by (kind, id) — packing before task")
  func toFlagUnmatchedSortedByKindThenID() {
    let taskRef = Self.taskRef(id: Self.tripItemIDC, masterItemID: Self.masterIDA)
    let pack1 = Self.packingRef(id: Self.tripItemIDB, masterItemID: Self.masterIDB)
    let pack2 = Self.packingRef(id: Self.tripItemIDA, masterItemID: Self.masterIDC)
    let plan = compute(
      trip: Self.snapshot(
        attributes: Self.sunnyTripAttributes(),
        tasks: [taskRef],
        packing: [pack1, pack2]
      ),
      masterTasks: [Self.taskMaster(id: Self.masterIDA)],
      masterPacking: [
        Self.packingMaster(id: Self.masterIDB), Self.packingMaster(id: Self.masterIDC)
      ]
    )
    #expect(
      plan.toFlagUnmatched == [
        TripItemRef(kind: .packing, id: Self.tripItemIDA),
        TripItemRef(kind: .packing, id: Self.tripItemIDB),
        TripItemRef(kind: .task, id: Self.tripItemIDC)
      ])
  }

  // MARK: - tripID propagation

  @Test("Plan carries trip id from input snapshot")
  func planCarriesTripID() {
    let plan = compute(
      trip: Self.snapshot(),
      masterTasks: [],
      masterPacking: []
    )
    #expect(plan.tripID == Self.tripID)
  }

  // MARK: - userDeletedOnThisTrip — engine carve-out (Req 7.4 / 7.5)

  @Test(
    "userDeleted: (matched=true, conditions=true) — ref is skipped (would have been no-op anyway)")
  func userDeletedTrueTrue() {
    let plan = compute(
      trip: Self.snapshot(
        tasks: [Self.taskRef(currentlyMatchesRules: true, userDeletedOnThisTrip: true)]
      ),
      masterTasks: [Self.taskMaster()],
      masterPacking: []
    )
    #expect(plan.toFlagMatched.isEmpty)
    #expect(plan.toFlagUnmatched.isEmpty)
    #expect(
      plan.toAddTasks.isEmpty, "Master is still referenced by the deleted ref, so toAdd stays empty"
    )
  }

  @Test(
    "userDeleted: (matched=true, conditions=false) — ref is skipped, NOT moved to toFlagUnmatched")
  func userDeletedTrueFalse() {
    let plan = compute(
      trip: Self.snapshot(
        attributes: Self.sunnyTripAttributes(),
        tasks: [Self.taskRef(currentlyMatchesRules: true, userDeletedOnThisTrip: true)]
      ),
      masterTasks: [Self.taskMaster()],
      masterPacking: []
    )
    #expect(plan.toFlagUnmatched.isEmpty)
    #expect(plan.toFlagMatched.isEmpty)
  }

  @Test(
    "userDeleted: (matched=false, conditions=true) — ref is skipped, NOT moved to toFlagMatched")
  func userDeletedFalseTrue() {
    let plan = compute(
      trip: Self.snapshot(
        tasks: [Self.taskRef(currentlyMatchesRules: false, userDeletedOnThisTrip: true)]
      ),
      masterTasks: [Self.taskMaster()],
      masterPacking: []
    )
    #expect(plan.toFlagMatched.isEmpty)
    #expect(plan.toFlagUnmatched.isEmpty)
  }

  @Test("userDeleted: (matched=false, conditions=false) — ref is skipped")
  func userDeletedFalseFalse() {
    let plan = compute(
      trip: Self.snapshot(
        attributes: Self.sunnyTripAttributes(),
        tasks: [Self.taskRef(currentlyMatchesRules: false, userDeletedOnThisTrip: true)]
      ),
      masterTasks: [Self.taskMaster()],
      masterPacking: []
    )
    #expect(plan.toFlagMatched.isEmpty)
    #expect(plan.toFlagUnmatched.isEmpty)
  }

  @Test("userDeleted: master is still considered referenced — no re-add via toAddTasks")
  func userDeletedDoesNotReAdd() {
    let plan = compute(
      trip: Self.snapshot(
        tasks: [Self.taskRef(currentlyMatchesRules: true, userDeletedOnThisTrip: true)]
      ),
      masterTasks: [Self.taskMaster()],
      masterPacking: []
    )
    #expect(plan.toAddTasks.isEmpty)
  }

  // MARK: - Snapshot capture worst case (200 masters, all matching)

  @Test("200 masters all matching against empty-trip snapshot produces 200 sorted toAddTasks")
  func twoHundredMastersAllMatching() {
    let masters: [MasterTaskSnapshot] = (0..<200).map { i in
      let id = UUID(
        uuidString: String(format: "00000000-0000-0000-0000-%012X", i))!
      return MasterTaskSnapshot(id: id, name: "M\(i)", phase: .weeksBefore, conditions: .always)
    }
    let plan = compute(
      trip: Self.snapshot(attributes: TripAttributes()),
      masterTasks: masters,
      masterPacking: []
    )
    #expect(plan.toAddTasks.count == 200)
    let ids = plan.toAddTasks.map(\.id)
    #expect(ids == ids.sorted())
  }
}
