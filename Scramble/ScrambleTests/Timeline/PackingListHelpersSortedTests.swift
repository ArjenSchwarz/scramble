import Foundation
import Testing

@testable import Scramble

@Suite("PackingListHelpers.sorted")
@MainActor
struct PackingListHelpersSortedTests {

  // MARK: - Fixture builder

  private static func item(
    name: String,
    matches: Bool = true,
    pinned: Bool = false,
    id: UUID = UUID()
  ) -> TripPackingItem {
    TripPackingItem(
      id: id,
      name: name,
      source: .rule,
      currentlyMatchesRules: matches,
      pinnedByUser: pinned
    )
  }

  // MARK: - Active before dimmed

  @Test("Active items sort before dimmed items")
  func activeBeforeDimmed() {
    let dimmed = Self.item(name: "alpha", matches: false, pinned: false)
    let active = Self.item(name: "zebra", matches: true, pinned: false)
    let result = PackingListHelpers.sorted([dimmed, active])
    #expect(result.map(\.name) == ["zebra", "alpha"])
  }

  @Test("Pinned-but-unmatched items count as active")
  func pinnedUnmatchedIsActive() {
    let pinnedUnmatched = Self.item(name: "alpha", matches: false, pinned: true)
    let plainUnmatched = Self.item(name: "zebra", matches: false, pinned: false)
    let result = PackingListHelpers.sorted([plainUnmatched, pinnedUnmatched])
    #expect(result.map(\.name) == ["alpha", "zebra"])
  }

  // MARK: - Case-insensitive sort within bucket

  @Test("Within a bucket, case-insensitive ascending name sort")
  func caseInsensitiveSort() {
    let inputs = [
      Self.item(name: "Beta"),
      Self.item(name: "alpha"),
      Self.item(name: "Charlie"),
    ]
    let result = PackingListHelpers.sorted(inputs)
    #expect(result.map(\.name) == ["alpha", "Beta", "Charlie"])
  }

  @Test("Non-ASCII names sort by locale-aware case-insensitive compare")
  func nonASCIISort() {
    let inputs = [
      Self.item(name: "Étretat"),
      Self.item(name: "Beta"),
      Self.item(name: "alpha"),
    ]
    let result = PackingListHelpers.sorted(inputs)
    #expect(result.map(\.name) == ["alpha", "Beta", "Étretat"])
  }

  // MARK: - Id tiebreak

  @Test("Equal-name items tiebreak by id")
  func idTiebreak() {
    let lo = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let hi = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFE")!
    let high = Self.item(name: "Same", id: hi)
    let low = Self.item(name: "Same", id: lo)
    let result = PackingListHelpers.sorted([high, low])
    #expect(result.map(\.id) == [lo, hi])
  }

  @Test("Equal-name same-bucket case-difference tiebreak by id (case-insensitive equal names)")
  func caseInsensitiveEqualTiebreak() {
    let lo = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let hi = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFE")!
    let upper = Self.item(name: "ALPHA", id: hi)
    let lower = Self.item(name: "alpha", id: lo)
    let result = PackingListHelpers.sorted([upper, lower])
    #expect(result.map(\.id) == [lo, hi])
  }

  // MARK: - Mixed

  @Test("Mixed buckets: active group fully sorted, then dimmed group fully sorted")
  func mixedBuckets() {
    let inputs = [
      Self.item(name: "zebra", matches: true),  // active
      Self.item(name: "Étretat", matches: false),  // dimmed
      Self.item(name: "Charlie", matches: true),  // active
      Self.item(name: "alpha", matches: false, pinned: true),  // active (pinned)
      Self.item(name: "beta", matches: false),  // dimmed
    ]
    let result = PackingListHelpers.sorted(inputs)
    #expect(result.map(\.name) == ["alpha", "Charlie", "zebra", "beta", "Étretat"])
  }
}
