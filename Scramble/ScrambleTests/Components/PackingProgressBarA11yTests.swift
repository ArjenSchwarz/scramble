import Testing

@testable import Scramble

/// Phase 6 Req 9.4 — per-person packing progress bar accessibility value
/// of the form `"{name}'s packing, {packed} of {total} packed"`.
@Suite("PackingSummaryRow accessibilityValue")
struct PackingProgressBarA11yTests {

  @Test("Pack mode reports packed of (toPack + packed)")
  func packMode() {
    let counts = PackingCounts(
      toPack: 3, packed: 2, repacked: 0, excluded: 0
    )
    let value = PackingSummaryRow.composedAccessibilityValue(
      personName: "Alice", counts: counts, mode: .pack
    )
    #expect(value == "Alice's packing, 2 of 5 packed")
  }

  @Test("Repack mode reports repacked of (packed + repacked)")
  func repackMode() {
    let counts = PackingCounts(
      toPack: 0, packed: 1, repacked: 3, excluded: 0
    )
    let value = PackingSummaryRow.composedAccessibilityValue(
      personName: "Bob", counts: counts, mode: .repack
    )
    #expect(value == "Bob's packing, 3 of 4 repacked")
  }

  @Test("Empty totals still render as 0 of 0")
  func emptyTotals() {
    let counts = PackingCounts(
      toPack: 0, packed: 0, repacked: 0, excluded: 0
    )
    let value = PackingSummaryRow.composedAccessibilityValue(
      personName: "Cara", counts: counts, mode: .pack
    )
    #expect(value == "Cara's packing, 0 of 0 packed")
  }
}
