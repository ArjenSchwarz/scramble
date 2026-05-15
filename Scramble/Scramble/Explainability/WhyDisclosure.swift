import SwiftUI

/// Namespace for the explainability panel and its `Reason` enum. The view
/// (`WhyDisclosureView`) and the resolved reason share this namespace so
/// `WhyResolver` can produce a `WhyDisclosure.Reason` without depending on
/// the view layer.
enum WhyDisclosure {
  /// Why a given `TripTask` is on this trip. Computed on demand by
  /// `WhyResolver` and rendered by `WhyDisclosureView`.
  enum Reason: Equatable, Sendable {
    /// User added this task manually for this trip.
    case manual
    /// The rule that created this task no longer exists (master deleted or
    /// `masterItemID` is nil).
    case ruleMasterDeleted
    /// The rule's master exists and at least one of its conditions currently
    /// matches the trip's attributes. `conditionsText` is the formatted
    /// explanation produced by `ConditionsFormatter`.
    case ruleMatched(conditionsText: String)
    /// The rule's master exists but no condition currently matches the
    /// trip's attributes.
    case ruleNoLongerMatches
  }

  /// Visual treatment for `WhyDisclosureView`. Tasks render with a phase-tinted
  /// background and 1pt border; packing rows render with a softer person-tinted
  /// background and no border (Phase 4 design §"Integration with WhyDisclosure").
  nonisolated enum Style: Sendable {
    case tasks(phaseColour: Color)
    case packing(personColour: Color)

    var resolvedAppearance: ResolvedAppearance {
      switch self {
      case .tasks(let phaseColour):
        return ResolvedAppearance(tint: phaseColour, backgroundOpacity: 0.08, borderOpacity: 0.20)
      case .packing(let personColour):
        return ResolvedAppearance(tint: personColour, backgroundOpacity: 0.06, borderOpacity: nil)
      }
    }
  }

  /// Snapshot of the resolved appearance values driven by `Style`. Exposed
  /// `nonisolated` so unit tests can assert the mapping table without
  /// instantiating SwiftUI.
  nonisolated struct ResolvedAppearance: Sendable, Equatable {
    let tint: Color
    let backgroundOpacity: Double
    /// `nil` when no border should be drawn (packing variant).
    let borderOpacity: Double?
  }
}

/// Inline explainability panel rendered below a `TaskRow` (or a packing item
/// row) when its disclosure is open. Consumes a `WhyDisclosure.Reason`
/// (resolved by `WhyResolver`) and renders it per UI doc §"Visual treatment":
/// - Tasks context:   phase colour at 8% bg, 20% border, phase-coloured WHY?
/// - Packing context: person colour at 6% bg, no border, person-coloured WHY?
struct WhyDisclosureView: View {
  let reason: WhyDisclosure.Reason
  let style: WhyDisclosure.Style

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let variant = theme.variant(for: colorScheme)
    let appearance = style.resolvedAppearance

    VStack(alignment: .leading, spacing: 4) {
      Text("WHY?")
        .font(.system(size: 9, weight: .heavy))
        .foregroundStyle(appearance.tint)

      Text(bodyText)
        .font(.footnote)
        .foregroundStyle(variant.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(appearance.tint.opacity(appearance.backgroundOpacity))
    )
    .overlay(borderOverlay(appearance: appearance))
  }

  @ViewBuilder
  private func borderOverlay(appearance: WhyDisclosure.ResolvedAppearance) -> some View {
    if let borderOpacity = appearance.borderOpacity {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(appearance.tint.opacity(borderOpacity), lineWidth: 1)
    }
  }

  private var bodyText: String {
    switch reason {
    case .manual:
      return "You added this manually for this trip."
    case .ruleMasterDeleted:
      return "Originally added by a rule that has since been removed."
    case .ruleMatched(let conditionsText):
      if conditionsText.isEmpty {
        return "Matches your trip."
      }
      return "Matches your trip: \(conditionsText)"
    case .ruleNoLongerMatches:
      return
        "No conditions currently match your trip's attributes — this task may have matched previously."
    }
  }
}
