import Foundation
import Testing

@testable import Scramble

/// Category re-stamp emission (feature `packing-item-categories`, Decision 2/6).
/// Lives in its own suite to keep `ComputeTests` under the file/type-length
/// limits. `compute` branches on the master's presence in the packing map, not
/// on its value, and exact-string compares category before emitting.
@Suite("RulesEngine compute — category re-stamp")
struct ComputeCategoryRestampTests {

  // MARK: - Fixture helpers

  private static let tripID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F0")!
  private static let personID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!
  private static let masterIDA = UUID(uuidString: "00000000-0000-0000-0000-0000000000A0")!
  private static let masterIDB = UUID(uuidString: "00000000-0000-0000-0000-0000000000B0")!
  private static let masterIDC = UUID(uuidString: "00000000-0000-0000-0000-0000000000C0")!
  private static let tripItemIDA = UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!
  private static let tripItemIDB = UUID(uuidString: "00000000-0000-0000-0000-00000000A002")!
  private static let tripItemIDC = UUID(uuidString: "00000000-0000-0000-0000-00000000A003")!

  private static func packingMaster(
    id: UUID = masterIDA,
    category: String?
  ) -> MasterPackingSnapshot {
    MasterPackingSnapshot(
      id: id, name: "Rain jacket", personID: personID, conditions: .always, category: category)
  }

  private static func packingRef(
    id: UUID = tripItemIDA,
    masterItemID: UUID? = masterIDA,
    source: ItemSource = .rule,
    category: String?
  ) -> TripPackingItemRef {
    TripPackingItemRef(
      id: id,
      masterItemID: masterItemID,
      currentlyMatchesRules: true,
      pinnedByUser: false,
      source: source,
      state: .unpacked,
      category: category
    )
  }

  private static func snapshot(packing: [TripPackingItemRef]) -> TripSnapshot {
    TripSnapshot(
      id: tripID,
      attributes: TripAttributes(),
      existingTasks: [],
      existingPacking: packing
    )
  }

  // MARK: - Tests

  @Test("Master present and category differs → emit one restamp with the master value")
  func emitsWhenDiffers() {
    let plan = compute(
      trip: Self.snapshot(packing: [Self.packingRef(category: "Toiletries")]),
      masterTasks: [],
      masterPacking: [Self.packingMaster(category: "Clothes")]
    )
    #expect(
      plan.toRestampCategory == [PackingCategoryRestamp(id: Self.tripItemIDA, category: "Clothes")])
  }

  @Test("Exact-string compare — a case-variant differs and re-stamps to the master spelling")
  func usesExactStringCompare() {
    // Normalization is a display concern; the engine compares stored spellings
    // verbatim, so "clothes" ≠ "Clothes" and re-stamps to the master's spelling.
    let plan = compute(
      trip: Self.snapshot(packing: [Self.packingRef(category: "clothes")]),
      masterTasks: [],
      masterPacking: [Self.packingMaster(category: "Clothes")]
    )
    #expect(
      plan.toRestampCategory == [PackingCategoryRestamp(id: Self.tripItemIDA, category: "Clothes")])
  }

  @Test("Equal categories → no restamp (compare-before-write)")
  func skipsWhenEqual() {
    let plan = compute(
      trip: Self.snapshot(packing: [Self.packingRef(category: "Clothes")]),
      masterTasks: [],
      masterPacking: [Self.packingMaster(category: "Clothes")]
    )
    #expect(plan.toRestampCategory.isEmpty)
  }

  @Test("Master present with nil category over a non-nil item → emit clear (category: nil)")
  func clearsWhenMasterNil() {
    let plan = compute(
      trip: Self.snapshot(packing: [Self.packingRef(category: "Clothes")]),
      masterTasks: [],
      masterPacking: [Self.packingMaster(category: nil)]
    )
    #expect(plan.toRestampCategory == [PackingCategoryRestamp(id: Self.tripItemIDA, category: nil)])
  }

  @Test("Master absent/deleted from the packing map → no restamp (freeze, Req 3.6)")
  func frozenWhenMasterAbsent() {
    // The ref references masterIDA but no master is supplied, so the master is
    // absent from the packing map → the last-applied category is frozen.
    let plan = compute(
      trip: Self.snapshot(packing: [Self.packingRef(category: "Clothes")]),
      masterTasks: [],
      masterPacking: []
    )
    #expect(plan.toRestampCategory.isEmpty)
  }

  @Test("Manual one-off (masterItemID == nil) → never re-stamped (Req 4.3)")
  func skipsManualOneOff() {
    let plan = compute(
      trip: Self.snapshot(
        packing: [Self.packingRef(masterItemID: nil, source: .manual, category: "Clothes")]
      ),
      masterTasks: [],
      masterPacking: [Self.packingMaster(category: "Toiletries")]
    )
    #expect(plan.toRestampCategory.isEmpty)
  }

  @Test("Manual item with a stray non-nil masterItemID present in the map → never re-stamped")
  func skipsManualWithStrayMasterID() {
    // A manual item owns its category. Even though masterIDA IS present in the
    // packing map and its category differs, the `source == .manual` guard wins
    // — proving a manual item is never re-stamped via a stray masterItemID (Req 4.3).
    let plan = compute(
      trip: Self.snapshot(
        packing: [
          Self.packingRef(masterItemID: Self.masterIDA, source: .manual, category: "Clothes")
        ]
      ),
      masterTasks: [],
      masterPacking: [Self.packingMaster(id: Self.masterIDA, category: "Toiletries")]
    )
    #expect(plan.toRestampCategory.isEmpty)
  }

  @Test("Second pass after applying the restamp → empty toRestampCategory (idempotence)")
  func isIdempotent() {
    let first = compute(
      trip: Self.snapshot(packing: [Self.packingRef(category: "Old")]),
      masterTasks: [],
      masterPacking: [Self.packingMaster(category: "New")]
    )
    #expect(
      first.toRestampCategory == [PackingCategoryRestamp(id: Self.tripItemIDA, category: "New")])

    // Simulate apply: the item now holds the master's category. Recompute.
    let second = compute(
      trip: Self.snapshot(packing: [Self.packingRef(category: "New")]),
      masterTasks: [],
      masterPacking: [Self.packingMaster(category: "New")]
    )
    #expect(second.toRestampCategory.isEmpty)
  }

  @Test("Only the differing items are emitted, sorted by trip-item id")
  func emitsOnlyDifferingItemsSorted() {
    // Item A already equals master A (no emit); B and C differ. Inputs are
    // out of order to prove the emitted list is sorted by trip-item id.
    let plan = compute(
      trip: Self.snapshot(
        packing: [
          Self.packingRef(id: Self.tripItemIDC, masterItemID: Self.masterIDC, category: "x"),
          Self.packingRef(id: Self.tripItemIDA, masterItemID: Self.masterIDA, category: "Same"),
          Self.packingRef(id: Self.tripItemIDB, masterItemID: Self.masterIDB, category: "y"),
        ]
      ),
      masterTasks: [],
      masterPacking: [
        Self.packingMaster(id: Self.masterIDA, category: "Same"),
        Self.packingMaster(id: Self.masterIDB, category: "B-cat"),
        Self.packingMaster(id: Self.masterIDC, category: "C-cat"),
      ]
    )
    #expect(
      plan.toRestampCategory == [
        PackingCategoryRestamp(id: Self.tripItemIDB, category: "B-cat"),
        PackingCategoryRestamp(id: Self.tripItemIDC, category: "C-cat"),
      ])
  }
}
