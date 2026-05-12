import SwiftUI

/// Inline explainability panel rendered below a `TaskRow` when its disclosure
/// is open. Consumes a `WhyDisclosure.Reason` (resolved by `WhyResolver`) and
/// renders it per UI doc §"Visual treatment — Tasks context":
/// - Background: phase colour at 8% opacity
/// - Border:     1pt at phase colour at 20% opacity
/// - Header:     9pt heavy uppercase "WHY?" in phase colour
/// - Body:       per-`Reason` sentence in primary text
struct WhyDisclosureView: View {
  let reason: WhyDisclosure.Reason
  let phaseColour: Color

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let variant = theme.variant(for: colorScheme)

    VStack(alignment: .leading, spacing: 4) {
      Text("WHY?")
        .font(.system(size: 9, weight: .heavy))
        .foregroundStyle(phaseColour)

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
        .fill(phaseColour.opacity(0.08))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(phaseColour.opacity(0.20), lineWidth: 1)
    )
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
