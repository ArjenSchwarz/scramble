import SwiftUI

/// Phase 6 — shared animation constant used by polish-pass transitions
/// (Reqs 7.1, 7.2). One curve, one duration, across phase-row toggles
/// and task/packing checkbox toggles, so the app's motion feels coherent.
///
/// Req 7.4 ("WHEN `accessibilityReduceMotion` is true ... SHALL be
/// replaced with `.opacity` cross-fades") is *vacuously* satisfied today:
/// no call site applies a geometric `.transition(.move/.scale/...)` or
/// any custom parallax, so SwiftUI's default conditional-insertion
/// transition (`.opacity`) is what runs for every user — Reduce Motion
/// on or off. The accordion's `if isExpanded { content() }` and the
/// checkbox's state-driven opacity / strikethrough swap both rely on
/// that default.
///
/// **Future call sites adding `.transition(.move/.scale/...)` MUST
/// gate the transition behind `@Environment(\.accessibilityReduceMotion)`
/// themselves** — this constant only owns the curve and duration.
extension Animation {
  static let scrambleStandard: Animation = .easeInOut(duration: 0.22)
}
