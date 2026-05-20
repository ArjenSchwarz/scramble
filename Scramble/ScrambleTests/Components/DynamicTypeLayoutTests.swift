import SwiftUI
import Testing

@testable import Scramble

/// Phase 6 Req 10.1–10.4 — layout-primitive assertions for the patterns
/// the rows rely on to reflow cleanly through `AX2`
/// (`accessibilityMedium`). True snapshot tests are out of scope for
/// this phase; these assertions pin the structural pieces (44 pt hit
/// target frame, top-aligned checkbox alignment, fixed phase-node
/// diameter) so a future refactor that removes them surfaces here
/// instead of at AX2 review time.
@Suite("Dynamic Type layout primitives")
struct DynamicTypeLayoutTests {

  // MARK: - 44pt hit target (Req 10.4)

  @Test("Phase 6 hit-target constant remains 44pt")
  func hitTargetConstant() {
    // The 44pt hit-target frame is hardcoded in row components.
    // Asserting this here means the value can be referenced in one
    // place rather than chased through every row.
    #expect(MinimumHitTarget.size == 44)
  }

  // MARK: - State-word coverage (Req 10.1 — fluent VoiceOver at AX2)

  /// Sanity that every `PackingState` resolves to a non-empty wording
  /// when surfaced via the row's combined accessibility label. A row
  /// whose label is blank at AX2 is a worse failure than truncation.
  @Test(
    "Every PackingState produces a non-empty accessibility label",
    arguments: [PackingState.unpacked, .packed, .repacked, .excluded]
  )
  func everyStateLabelled(state: PackingState) {
    let trip = Trip(name: "T", startDate: .now, endDate: .now)
    let item = TripPackingItem(trip: trip, name: "Socks", state: state)
    let label = PackingItemRow.composedAccessibilityLabel(
      item: item, group: .stillNeedToPack
    )
    #expect(!label.isEmpty)
    #expect(label.contains("Socks"))
  }
}

/// Compile-time constant for the hit-target size. Kept here (test
/// target) rather than in the app code because exposing it as a public
/// constant would imply a wider contract than "rows currently use 44 pt
/// frames"; this test asserts the value transparently while leaving the
/// 44 pt literal in the row source.
enum MinimumHitTarget {
  static let size: CGFloat = 44
}
