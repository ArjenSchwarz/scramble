import SwiftUI

/// Spine marker rendered in place of a full `PhaseNode` when a phase has
/// compressed away to zero days (currently only `.duringTrip` on a 1- or
/// 2-day trip — see Req 3.1). A 4pt dot at reduced opacity sitting on the
/// spine line. No tap target, no header — `PhaseRow` handles the layout
/// surrounding this view.
struct CompressedSpineDot: View {
  let phaseColour: Color

  var body: some View {
    Circle()
      .fill(phaseColour.opacity(0.4))
      .frame(width: 4, height: 4)
  }
}
