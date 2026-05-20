import SwiftUI

/// Phase 6 — shared animation constant used by polish-pass transitions
/// (Reqs 7.1, 7.2). One curve, one duration, across phase-row toggles
/// and task/packing checkbox toggles, so the app's motion feels coherent.
///
/// Req 7.4 (Reduce Motion → opacity cross-fade with the same duration) is
/// satisfied implicitly: the `if isExpanded { content() }` accordion uses
/// SwiftUI's default opacity transition, and the checkbox state change is
/// already an opacity / strikethrough swap rather than a geometric morph.
/// No call site adds a custom `.transition(.move)`/`.scale`/parallax, so
/// Reduce Motion users observe the same cross-fade as everyone else.
extension Animation {
  static let scrambleStandard: Animation = .easeInOut(duration: 0.22)
}
