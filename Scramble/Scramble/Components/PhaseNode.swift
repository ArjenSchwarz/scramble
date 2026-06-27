import SwiftUI

/// Visual node rendered for each phase on the Trip Detail accordion timeline.
///
/// Three states (past / current / future) per UI doc §"Phase node visual
/// states":
/// - `.past`   — filled circle in phase colour with white checkmark, 24pt.
/// - `.current` — filled circle, 28pt, with a glow ring rendered via two
///   stacked shadows so the bloom is visible on both light and dark variants.
/// - `.future` — outlined circle (1.5pt stroke), 24pt.
///
/// When `isPackingPhase == true` and the state is `.current` or `.future`, an
/// SF Symbol packing glyph overlays the node at ~50% of its diameter
/// (`suitcase.fill` for the day-before pack, `shippingbox.fill` for the
/// day-before-return repack). The NOW pill is owned by `PhaseRow`, not by this view.
struct PhaseNode: View {
  let phase: Phase
  let state: PhaseNodeState
  let isPackingPhase: Bool
  let phaseColour: Color
  var diameter: CGFloat?

  init(
    phase: Phase,
    state: PhaseNodeState,
    isPackingPhase: Bool,
    phaseColour: Color,
    diameter: CGFloat? = nil
  ) {
    self.phase = phase
    self.state = state
    self.isPackingPhase = isPackingPhase
    self.phaseColour = phaseColour
    self.diameter = diameter
  }

  private var resolvedDiameter: CGFloat {
    if let diameter { return diameter }
    return state == .current ? 28 : 24
  }

  var body: some View {
    let d = resolvedDiameter

    ZStack {
      circle(diameter: d)
      glyph(diameter: d)
    }
    .frame(width: d, height: d)
  }

  @ViewBuilder
  private func circle(diameter d: CGFloat) -> some View {
    switch state {
    case .past:
      Circle()
        .fill(phaseColour)
        .overlay(
          Image(systemName: "checkmark")
            .font(.system(size: d * 0.5, weight: .bold))
            .foregroundStyle(.white)
        )
        .frame(width: d, height: d)
    case .current:
      Circle()
        .fill(phaseColour)
        .frame(width: d, height: d)
        .shadow(color: phaseColour.opacity(0.5), radius: 6)
        .shadow(color: phaseColour.opacity(0.3), radius: 12)
    case .future:
      Circle()
        .strokeBorder(phaseColour, lineWidth: 1.5)
        .frame(width: d, height: d)
    }
  }

  @ViewBuilder
  private func glyph(diameter d: CGFloat) -> some View {
    if isPackingPhase, state != .past, let symbol = glyphSymbol {
      Image(systemName: symbol)
        .font(.system(size: d * 0.5, weight: .semibold))
        .foregroundStyle(glyphForeground)
    }
  }

  private var glyphSymbol: String? {
    switch phase {
    case .dayBefore: "suitcase.fill"
    case .dayBeforeReturn: "shippingbox.fill"
    default: nil
    }
  }

  private var glyphForeground: Color {
    state == .current ? .white : phaseColour
  }
}
