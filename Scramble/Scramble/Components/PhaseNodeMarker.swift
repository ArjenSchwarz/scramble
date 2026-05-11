import SwiftUI

enum PhaseNodeState: Hashable, Sendable {
  case past
  case current
  case future
}

struct PhaseNodeMarker: View {
  let state: PhaseNodeState
  let phaseColor: Color
  var diameter: CGFloat = 20

  var body: some View {
    switch state {
    case .past:
      Circle()
        .fill(phaseColor)
        .overlay(
          Image(systemName: "checkmark")
            .font(.system(size: diameter * 0.5, weight: .bold))
            .foregroundStyle(.white)
        )
        .frame(width: diameter, height: diameter)
    case .current:
      Circle()
        .fill(phaseColor)
        .frame(width: diameter, height: diameter)
    case .future:
      Circle()
        .strokeBorder(phaseColor, lineWidth: 1.5)
        .frame(width: diameter, height: diameter)
    }
  }
}
