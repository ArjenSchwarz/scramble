import SwiftUI

/// Single row on the accordion timeline. Composes:
/// - left column: `PhaseNode` or `CompressedSpineDot` plus the 2pt spine line
/// - right column: phase header (label + NOW pill + subline) and, when
///   expanded, the caller-supplied `content` view (typically `TaskListSection`)
///
/// Generic over `Content` (no `AnyView`) so SwiftUI's view-identity stays
/// stable across expansion changes. Tap-to-toggle is only attached when the
/// phase is expandable per Req 2.5/2.6: a non-packing phase with no
/// matching-or-pinned tasks is a non-expandable spine marker, and a
/// compressed phase is never tappable.
struct PhaseRow<Content: View>: View {
  let phase: Phase
  let state: PhaseNodeState
  let counts: PhaseCounts
  let isExpanded: Bool
  let isCompressed: Bool
  let phaseColour: Color
  var packingSubline: String?
  let onToggle: () -> Void
  @ViewBuilder let content: () -> Content

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  private var expandable: Bool {
    !isCompressed && (counts.total > 0 || phase.packingMode != nil)
  }

  var body: some View {
    let variant = theme.variant(for: colorScheme)

    HStack(alignment: .top, spacing: 16) {
      leftColumn(variant: variant)

      if !isCompressed {
        rightColumn(variant: variant)
      } else {
        Spacer(minLength: 0)
      }
    }
    .frame(minHeight: isCompressed ? 20 : 56)
    .padding(.horizontal)
  }

  // MARK: - Left column (spine + node/dot)

  private func leftColumn(variant: ThemeVariant) -> some View {
    VStack(spacing: 0) {
      if isCompressed {
        // Continuous spine through the compressed marker.
        Rectangle()
          .fill(spineColour(variant: variant))
          .frame(width: 2)
          .frame(height: 12)
        CompressedSpineDot(phaseColour: phaseColour)
        Rectangle()
          .fill(spineColour(variant: variant))
          .frame(width: 2)
          .frame(maxHeight: .infinity)
      } else {
        // The visible circle is 24–28pt (PhaseNode owns its size); the
        // surrounding 44×44 frame supplies the Req 1.7 / Req 10.4 hit
        // target. The same tap toggles the accordion so tapping the node
        // is interchangeable with tapping the header.
        PhaseNode(
          phase: phase,
          state: state,
          phaseColour: phaseColour
        )
        #if DEBUG
          .accessibilityIdentifier("tripDetail.phaseNode.\(phase.rawValue)")
        #endif
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .modifier(TapToToggleModifier(enabled: expandable, action: onToggle))
        Rectangle()
          .fill(spineColour(variant: variant))
          .frame(width: 2)
          .frame(maxHeight: .infinity)
      }
    }
    .frame(width: 44)
  }

  private func spineColour(variant: ThemeVariant) -> Color {
    state == .past ? phaseColour : variant.surfaceBorder
  }

  // MARK: - Right column (header + content)

  private func rightColumn(variant: ThemeVariant) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      header(variant: variant)

      if isExpanded {
        content()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func header(variant: ThemeVariant) -> some View {
    let label = Self.accessibilityLabel(
      phase: phase,
      state: state,
      counts: counts,
      packingSubline: packingSubline
    )
    let hint = Self.accessibilityHint(expandable: expandable, isExpanded: isExpanded)

    return VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 8) {
        Text(phase.displayName)
          .font(.headline)
          .foregroundStyle(variant.textPrimary)

        if state == .current {
          Text("NOW")
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(phaseColour))
        }

        Spacer(minLength: 0)
      }

      Text(sublineText)
        .font(.caption)
        .foregroundStyle(variant.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .modifier(TapToToggleModifier(enabled: expandable, action: onToggle))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(label)
    .accessibilityHint(hint)
    #if DEBUG
      .accessibilityIdentifier("tripDetail.phaseHeader.\(phase.rawValue)")
    #endif
  }

  private var sublineText: String {
    if let packingSubline {
      if counts.total == 0 {
        return packingSubline
      }
      return "\(TaskListHelpers.subline(counts)) · \(packingSubline)"
    }
    if counts.total == 0 {
      return "Nothing here yet"
    }
    return TaskListHelpers.subline(counts)
  }

  // MARK: - Accessibility (Phase 6 Req 9.1)

  /// Combined accessibility label of the form
  /// `"{phase display name}, {state}, {N of M tasks complete}"` per
  /// Req 9.1. The task-count clause is omitted entirely when
  /// `counts.total == 0`. The packing-subline (when present) is
  /// appended after the task count so VoiceOver users hear the same
  /// information visible sighted users get from the subline.
  static func accessibilityLabel(
    phase: Phase,
    state: PhaseNodeState,
    counts: PhaseCounts,
    packingSubline: String?
  ) -> String {
    let stateText: String
    switch state {
    case .past: stateText = "past"
    case .current: stateText = "current phase"
    case .future: stateText = "upcoming"
    }
    var label = "\(phase.displayName), \(stateText)"
    if counts.total > 0 {
      label += ", \(counts.completed) of \(counts.total) tasks complete"
    }
    if counts.inactive > 0 {
      label += ", plus \(counts.inactive) inactive"
    }
    if let packingSubline {
      label += ", \(packingSubline)"
    }
    return label
  }

  /// Action hint that flips based on the current expansion state.
  /// Non-expandable spine markers expose no hint.
  static func accessibilityHint(expandable: Bool, isExpanded: Bool) -> String {
    guard expandable else { return "" }
    return isExpanded ? "double tap to collapse" : "double tap to expand"
  }
}

/// View modifier that only attaches `.onTapGesture` when `enabled` is true —
/// preserves the "compressed / non-expandable spine marker is not tappable"
/// rule (Req 2.5 / 3.2) without conditionally wrapping the view tree.
///
/// Phase 6 — Req 8.2: tap fires a medium-impact haptic on the same view
/// event that initiates expand/collapse.
private struct TapToToggleModifier: ViewModifier {
  let enabled: Bool
  let action: () -> Void

  func body(content: Content) -> some View {
    if enabled {
      content.onTapGesture {
        #if canImport(UIKit)
          UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        action()
      }
    } else {
      content
    }
  }
}
