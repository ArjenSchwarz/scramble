import SwiftData
import SwiftUI
import os

#if canImport(UIKit)
  import UIKit
#endif

/// Per-person packing summary block rendered inside the Departure phase
/// (`mode: .pack`) and the Day-before-return phase (`mode: .repack`). Each
/// participant gets a `PackingSummaryRow`; tapping a row asks the parent to
/// open the `PackingSheet`. Participants are sorted by snapshot `name`
/// case-insensitive ascending, with stable tiebreak on `personID`. When
/// the trip has no roster snapshots, a single non-interactive placeholder
/// row is rendered per Req 1.8.
///
/// Phase 5.1 — identity is read from `trip.participantSnapshots`
/// (constraint C3); the Person reference handed to `onOpenSheet` is
/// resolved via `PersonLookup` against the globals container so the
/// PackingSheet downstream API is unchanged.
struct PackingSummarySection: View {
  let trip: Trip
  let mode: PackingMode
  let onOpenSheet: (Person, PackingMode) -> Void
  @AccessibilityFocusState.Binding var focusOnDismiss: UUID?

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.globalsContainer) private var globalsContainer

  var body: some View {
    let variant = theme.variant(for: colorScheme)
    let snapshots = sortedRosterSnapshots
    let countsByPerson = PackingListHelpers.countsByPerson(trip)
    // Phase 5.1 — resolve every roster Person in a single batch fetch
    // against globals instead of one fetch per ForEach iteration. The
    // dictionary is rebuilt each render pass, which costs at most one
    // SwiftData query per render rather than N.
    let peopleByID = resolvePersons(for: snapshots)

    VStack(alignment: .leading, spacing: 4) {
      if snapshots.isEmpty {
        Text("No participants yet — add people on the trip details screen")
          .font(.system(size: 13))
          .foregroundStyle(variant.textSecondary)
          .frame(minHeight: 44, alignment: .leading)
      } else {
        ForEach(snapshots, id: \.personID) { snapshot in
          let resolvedPerson = peopleByID[snapshot.personID]
          PackingSummaryRow(
            snapshot: snapshot,
            counts: countsByPerson[snapshot.personID]
              ?? PackingCounts(toPack: 0, packed: 0, repacked: 0, excluded: 0),
            mode: mode,
            focusOnDismiss: $focusOnDismiss,
            isEnabled: resolvedPerson != nil,
            onOpen: { handleOpen(snapshot: snapshot, person: resolvedPerson) }
          )
        }
      }
    }
  }

  private func resolvePersons(for snapshots: [TripPersonSnapshot]) -> [UUID: Person] {
    let ids = snapshots.map(\.personID)
    let resolved = TripPersistence.resolveParticipants(
      ids: ids, in: globalsContainer.mainContext
    )
    return Dictionary(uniqueKeysWithValues: resolved.resolved.map { ($0.id, $0) })
  }

  private func handleOpen(snapshot: TripPersonSnapshot, person: Person?) {
    guard let person else {
      // The snapshot references a Person that isn't in this device's
      // globals store — likely a stale snapshot whose owner removed
      // the Person, or an in-progress relocation. The row is rendered
      // as disabled, so this branch only fires if a tap races the
      // resolution; log it so Console surfaces the gap rather than
      // silently no-op'ing.
      let personID = snapshot.personID
      let snapshotName = snapshot.name
      modelLogger.error(
        """
        [PackingSummarySection] cannot open sheet — Person \
        \(personID, privacy: .public) not found in globals \
        (snapshot name=\(snapshotName, privacy: .public))
        """
      )
      return
    }
    onOpenSheet(person, mode)
  }

  private var sortedRosterSnapshots: [TripPersonSnapshot] {
    let snapshots = (trip.participantSnapshots ?? []).filter(\.isRosterMember)
    return snapshots.sorted { lhs, rhs in
      let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
      if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
      return lhs.personID.uuidString < rhs.personID.uuidString
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
  let snapshot: TripPersonSnapshot
  let counts: PackingCounts
  let mode: PackingMode
  @AccessibilityFocusState.Binding var focusOnDismiss: UUID?
  /// Phase 5.1 — false when the underlying `Person` cannot be resolved
  /// from the globals container (stale snapshot, in-progress relocation).
  /// Disables the button so the row gives a visible signal that tapping
  /// won't do anything, instead of silently no-op'ing.
  let isEnabled: Bool
  let onOpen: () -> Void

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let variant = theme.variant(for: colorScheme)
    let personColour = theme.personColor(key: snapshot.colourID, in: colorScheme) ?? .gray
    let ratio = PackingListHelpers.progressRatio(counts, mode: mode)
    let status = PackingListHelpers.summaryStatus(counts, mode: mode)

    Button(action: tap) {
      HStack(spacing: 12) {
        PersonAvatar(
          name: snapshot.name,
          colorKey: snapshot.colourID,
          size: .standard,
          isActive: true
        )

        VStack(alignment: .leading, spacing: 4) {
          Text(snapshot.name)
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
    .disabled(!isEnabled)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityValue(
      PackingSummaryRow.composedAccessibilityValue(
        personName: snapshot.name, counts: counts, mode: mode
      )
    )
    .accessibilityFocused($focusOnDismiss, equals: snapshot.personID)
    #if DEBUG
      .accessibilityIdentifier("tripDetail.packingSummary.\(snapshot.personID.uuidString)")
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
      return "\(snapshot.name)'s packing, no items, double tap to open packing sheet"
    }
    return
      "\(snapshot.name)'s packing, \(numerator) of \(denominator) \(action), double tap to open packing sheet"
  }

  /// Phase 6 Req 9.4 — `accessibilityValue` of the form
  /// `"{name}'s packing, {packed} of {total} packed"`. Surfaced on top
  /// of the existing label so VoiceOver users hear both the
  /// progress-bar value and the row's action hint.
  static func composedAccessibilityValue(
    personName: String, counts: PackingCounts, mode: PackingMode
  ) -> String {
    let action = (mode == .pack) ? "packed" : "repacked"
    let total: Int =
      (mode == .pack)
      ? counts.toPack + counts.packed
      : counts.packed + counts.repacked
    let done: Int = (mode == .pack) ? counts.packed : counts.repacked
    return "\(personName)'s packing, \(done) of \(total) \(action)"
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
