import SwiftUI

/// Phase 6 — shared animation constant used by polish-pass transitions
/// (Reqs 7.1, 7.2). One curve, one duration, across phase-row toggles and
/// task/packing checkbox toggles, so the app's motion feels coherent.
///
/// `accessibilityReduceMotion` is read at the call site (the modifier
/// pattern is `withAnimation(reduceMotion ? .easeInOut(duration: 0.18)
/// : .scrambleStandard) { ... }` — Reduce Motion gets the same duration
/// but renders as a cross-fade because the call site swaps the
/// transition to `.opacity`).
extension Animation {
  static let scrambleStandard: Animation = .easeInOut(duration: 0.22)
}
