import Foundation
import Testing

@testable import Scramble

@Suite("PackingListHelpers.summaryStatus")
@MainActor
struct PackingStatusTests {

  // MARK: - Pack mode

  @Test("Pack: zero items in unpacked ∪ packed ∪ excluded → 'No items'")
  func packZero() {
    let counts = PackingCounts(toPack: 0, packed: 0, repacked: 0, excluded: 0)
    #expect(PackingListHelpers.summaryStatus(counts, mode: .pack) == "No items")
  }

  @Test("Pack: only excluded items → '—'")
  func packOnlyExcluded() {
    let counts = PackingCounts(toPack: 0, packed: 0, repacked: 0, excluded: 3)
    #expect(PackingListHelpers.summaryStatus(counts, mode: .pack) == "—")
  }

  @Test("Pack: every unpacked-or-packed item is packed → '✓ ready'")
  func packAllPacked() {
    let counts = PackingCounts(toPack: 0, packed: 5, repacked: 0, excluded: 0)
    #expect(PackingListHelpers.summaryStatus(counts, mode: .pack) == "✓ ready")
  }

  @Test("Pack: every unpacked-or-packed packed AND some excluded too → '✓ ready'")
  func packAllPackedSomeExcluded() {
    let counts = PackingCounts(toPack: 0, packed: 2, repacked: 0, excluded: 1)
    #expect(PackingListHelpers.summaryStatus(counts, mode: .pack) == "✓ ready")
  }

  @Test("Pack: some unpacked → '{N} to pack'")
  func packSomeToPack() {
    let counts = PackingCounts(toPack: 3, packed: 1, repacked: 0, excluded: 0)
    #expect(PackingListHelpers.summaryStatus(counts, mode: .pack) == "3 to pack")
  }

  @Test("Pack: only unpacked, no packed → '{N} to pack'")
  func packAllUnpacked() {
    let counts = PackingCounts(toPack: 4, packed: 0, repacked: 0, excluded: 0)
    #expect(PackingListHelpers.summaryStatus(counts, mode: .pack) == "4 to pack")
  }

  // MARK: - Repack mode

  @Test("Repack: zero items in unpacked ∪ packed ∪ repacked ∪ excluded → 'No items'")
  func repackZero() {
    let counts = PackingCounts(toPack: 0, packed: 0, repacked: 0, excluded: 0)
    #expect(PackingListHelpers.summaryStatus(counts, mode: .repack) == "No items")
  }

  @Test("Repack: items exist but packed ∪ repacked is empty → '—'")
  func repackPackedRepackedEmpty() {
    let counts = PackingCounts(toPack: 2, packed: 0, repacked: 0, excluded: 1)
    #expect(PackingListHelpers.summaryStatus(counts, mode: .repack) == "—")
  }

  @Test("Repack: only excluded items → '—'")
  func repackOnlyExcluded() {
    let counts = PackingCounts(toPack: 0, packed: 0, repacked: 0, excluded: 3)
    #expect(PackingListHelpers.summaryStatus(counts, mode: .repack) == "—")
  }

  @Test("Repack: every packed-or-repacked item is repacked → '✓ all back in'")
  func repackAllRepacked() {
    let counts = PackingCounts(toPack: 0, packed: 0, repacked: 4, excluded: 0)
    #expect(PackingListHelpers.summaryStatus(counts, mode: .repack) == "✓ all back in")
  }

  @Test("Repack: all repacked even with unpacked/excluded present → '✓ all back in'")
  func repackAllRepackedSomeLeftBehind() {
    let counts = PackingCounts(toPack: 1, packed: 0, repacked: 3, excluded: 2)
    #expect(PackingListHelpers.summaryStatus(counts, mode: .repack) == "✓ all back in")
  }

  @Test("Repack: some packed (still to repack) → '{N} to repack'")
  func repackSomeToRepack() {
    let counts = PackingCounts(toPack: 0, packed: 2, repacked: 3, excluded: 0)
    #expect(PackingListHelpers.summaryStatus(counts, mode: .repack) == "2 to repack")
  }

  @Test("Repack: only packed, none repacked yet → '{N} to repack'")
  func repackAllPacked() {
    let counts = PackingCounts(toPack: 0, packed: 5, repacked: 0, excluded: 0)
    #expect(PackingListHelpers.summaryStatus(counts, mode: .repack) == "5 to repack")
  }
}
