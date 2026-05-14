import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

/// Per-person packing summary block rendered inside the Departure phase
/// (`mode: .pack`) and the Day-before-return phase (`mode: .repack`). Each
/// participant gets a `PackingSummaryRow`; tapping a row asks the parent to
/// open the `PackingSheet`. Participants are sorted by `Person.name`
/// case-insensitive ascending, with stable tiebreak on `Person.id`. When
/// `trip.participants` is empty, a single non-interactive placeholder row
/// is rendered per Req 1.8.
struct PackingSummarySection: View {
  let trip: Trip
  let mode: PackingMode
  let onOpenSheet: (Person, PackingMode) -> Void
  @AccessibilityFocusState.Binding var focusOnDismiss: UUID?

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let variant = theme.variant(for: colorScheme)
    let participants = sortedParticipants

    VStack(alignment: .leading, spacing: 4) {
      if participants.isEmpty {
        Text("No participants yet — add people on the trip details screen")
          .font(.system(size: 13))
          .foregroundStyle(variant.textSecondary)
          .frame(minHeight: 44, alignment: .leading)
      } else {
        ForEach(participants, id: \.id) { person in
          PackingSummaryRow(
            person: person,
            counts: PackingListHelpers.counts(for: person, in: trip),
            mode: mode,
            focusOnDismiss: $focusOnDismiss,
            onOpen: { onOpenSheet(person, mode) }
          )
        }
      }
    }
  }

  private var sortedParticipants: [Person] {
    let participants = trip.participants ?? []
    return participants.sorted { lhs, rhs in
      let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
      if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }
}

/// Row inside `PackingSummarySection`. 26pt active-style avatar, name, 3pt
/// progress bar, status label, trailing chevron. Tapping the row fires
/// `onOpen` and emits the soft-impact "Sheet present" haptic per Req 1.7.
/// `focusOnDismiss` is a parent-owned `@AccessibilityFocusState` keyed by
/// `Person.id`; the parent restores VoiceOver focus to the originating row
/// on sheet dismiss per Req 9.7.
struct PackingSummaryRow: View {
  let person: Person
  let counts: PackingCounts
  let mode: PackingMode
  @AccessibilityFocusState.Binding var focusOnDismiss: UUID?
  let onOpen: () -> Void

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let variant = theme.variant(for: colorScheme)
    let personColour = theme.personColor(key: person.colorKey, in: colorScheme) ?? .gray
    let ratio = PackingListHelpers.progressRatio(counts, mode: mode)
    let status = PackingListHelpers.summaryStatus(counts, mode: mode)

    Button(action: tap) {
      HStack(spacing: 12) {
        PersonAvatar(
          name: person.name,
          colorKey: person.colorKey,
          size: .standard,
          isActive: true
        )

        VStack(alignment: .leading, spacing: 4) {
          Text(person.name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(variant.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)

          PackingProgressBar(ratio: ratio, personColour: personColour)
        }

        Text(status)
          .font(.system(size: 12))
          .foregroundStyle(variant.textSecondary)

        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(variant.textSecondary)
      }
      .padding(.vertical, 8)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityFocused($focusOnDismiss, equals: person.id)
    #if DEBUG
      .accessibilityIdentifier("tripDetail.packingSummary.\(person.id.uuidString)")
    #endif
  }

  private func tap() {
    #if canImport(UIKit)
      UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    #endif
    onOpen()
  }

  private var accessibilityLabel: String {
    let action = (mode == .pack) ? "packed" : "repacked"
    let denominator: Int =
      (mode == .pack)
      ? counts.toPack + counts.packed
      : counts.packed + counts.repacked
    let numerator: Int = (mode == .pack) ? counts.packed : counts.repacked
    if denominator == 0 {
      return "\(person.name)'s packing, no items, double tap to open packing sheet"
    }
    return
      "\(person.name)'s packing, \(numerator) of \(denominator) \(action), double tap to open packing sheet"
  }
}

/// 3pt-high progress bar in person colour. Track is the person colour at 12%
/// opacity; fill is the person colour at full opacity for `ratio in [0, 1)`
/// and the theme's `checkColour` at exactly `1.0` per Req 1.5.
private struct PackingProgressBar: View {
  let ratio: Double
  let personColour: Color

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let clamped = min(max(ratio, 0.0), 1.0)
    let fillColour: Color =
      (clamped >= 1.0)
      ? theme.variant(for: colorScheme).checkColour
      : personColour

    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 2)
          .fill(personColour.opacity(0.12))
        RoundedRectangle(cornerRadius: 2)
          .fill(fillColour)
          .frame(width: proxy.size.width * clamped)
      }
    }
    .frame(height: 3)
  }
}
