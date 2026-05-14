import Foundation
import Testing

@testable import Scramble

@Suite("PackingListHelpers.progressRatio")
@MainActor
struct PackingProgressRatioTests {

  // MARK: - Pack mode

  @Test("Pack: zero denominator (toPack + packed == 0) → 0.0")
  func packZeroDenominator() {
    let counts = PackingCounts(toPack: 0, packed: 0, repacked: 0, excluded: 0)
    #expect(PackingListHelpers.progressRatio(counts, mode: .pack) == 0.0)
  }

  @Test("Pack: zero denominator with only excluded items → 0.0")
  func packOnlyExcluded() {
    let counts = PackingCounts(toPack: 0, packed: 0, repacked: 0, excluded: 5)
    #expect(PackingListHelpers.progressRatio(counts, mode: .pack) == 0.0)
  }

  @Test("Pack: every counted item packed → exactly 1.0")
  func packFullyPacked() {
    let counts = PackingCounts(toPack: 0, packed: 4, repacked: 0, excluded: 2)
    #expect(PackingListHelpers.progressRatio(counts, mode: .pack) == 1.0)
  }

  @Test("Pack: half packed → 0.5")
  func packHalf() {
    let counts = PackingCounts(toPack: 2, packed: 2, repacked: 0, excluded: 0)
    #expect(PackingListHelpers.progressRatio(counts, mode: .pack) == 0.5)
  }

  @Test("Pack: 1/3 packed → 1/3")
  func packOneThird() {
    let counts = PackingCounts(toPack: 2, packed: 1, repacked: 0, excluded: 0)
    let ratio = PackingListHelpers.progressRatio(counts, mode: .pack)
    #expect(abs(ratio - (1.0 / 3.0)) < 1e-12)
  }

  @Test("Pack: nothing packed → 0.0")
  func packNothingPacked() {
    let counts = PackingCounts(toPack: 5, packed: 0, repacked: 0, excluded: 0)
    #expect(PackingListHelpers.progressRatio(counts, mode: .pack) == 0.0)
  }

  // MARK: - Repack mode

  @Test("Repack: zero denominator (packed + repacked == 0) → 0.0")
  func repackZeroDenominator() {
    let counts = PackingCounts(toPack: 0, packed: 0, repacked: 0, excluded: 0)
    #expect(PackingListHelpers.progressRatio(counts, mode: .repack) == 0.0)
  }

  @Test("Repack: only unpacked/excluded (denominator zero) → 0.0")
  func repackOnlyLeftBehind() {
    let counts = PackingCounts(toPack: 3, packed: 0, repacked: 0, excluded: 1)
    #expect(PackingListHelpers.progressRatio(counts, mode: .repack) == 0.0)
  }

  @Test("Repack: every counted item repacked → exactly 1.0")
  func repackFullyRepacked() {
    let counts = PackingCounts(toPack: 1, packed: 0, repacked: 4, excluded: 2)
    #expect(PackingListHelpers.progressRatio(counts, mode: .repack) == 1.0)
  }

  @Test("Repack: half repacked → 0.5")
  func repackHalf() {
    let counts = PackingCounts(toPack: 0, packed: 2, repacked: 2, excluded: 0)
    #expect(PackingListHelpers.progressRatio(counts, mode: .repack) == 0.5)
  }

  @Test("Repack: nothing repacked yet → 0.0")
  func repackNothingRepacked() {
    let counts = PackingCounts(toPack: 0, packed: 5, repacked: 0, excluded: 0)
    #expect(PackingListHelpers.progressRatio(counts, mode: .repack) == 0.0)
  }

  // MARK: - Bounds

  @Test(
    "Ratio is always in [0.0, 1.0] across mixed counts",
    arguments: [
      PackingCounts(toPack: 1, packed: 0, repacked: 0, excluded: 0),
      PackingCounts(toPack: 0, packed: 1, repacked: 0, excluded: 0),
      PackingCounts(toPack: 0, packed: 0, repacked: 1, excluded: 0),
      PackingCounts(toPack: 0, packed: 0, repacked: 0, excluded: 1),
      PackingCounts(toPack: 1, packed: 1, repacked: 1, excluded: 1),
      PackingCounts(toPack: 100, packed: 50, repacked: 25, excluded: 10),
    ]
  )
  func ratioBounds(_ counts: PackingCounts) {
    let pack = PackingListHelpers.progressRatio(counts, mode: .pack)
    let repack = PackingListHelpers.progressRatio(counts, mode: .repack)
    #expect(pack >= 0.0 && pack <= 1.0)
    #expect(repack >= 0.0 && repack <= 1.0)
  }
}
