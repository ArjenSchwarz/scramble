import SwiftData
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

/// Identifies the section a `PackingItemRow` belongs to inside the
/// `PackingSheet`. The first three cases are pack-mode sections; the last
/// three are repack-mode sections. The enum is file-scope (not private)
/// because both `PackingItemRow` and `PackingSheet` (Task 11) need to refer
/// to the same set of sections.
enum SheetGroup: Sendable {
  case stillNeedToPack
  case packed
  case notBringing
  case stillInSuitcase
  case backInSuitcase
  case leftBehind

  /// `true` for sections whose rows show a dashed-border placeholder instead
  /// of an interactive checkbox. These sections also suppress the inline
  /// Skip/Restore button and the Edit affordance per Req 4.5 / 6.1.
  var isReadOnly: Bool {
    switch self {
    case .notBringing, .leftBehind: return true
    case .stillNeedToPack, .packed, .stillInSuitcase, .backInSuitcase: return false
    }
  }

  /// Localised section header used both as the visible header text and as
  /// the target-group title in the `UIAccessibility.Notification.announcement`
  /// posted on group-move per Req 9.8.
  var headerTitle: String {
    switch self {
    case .stillNeedToPack: return "Still need to pack"
    case .packed: return "Packed"
    case .notBringing: return "Not bringing"
    case .stillInSuitcase: return "Still in suitcase"
    case .backInSuitcase: return "Back in suitcase"
    case .leftBehind: return "Left behind"
    }
  }

  /// `ScrollViewReader` anchor id for this section. Doubles as the
  /// `accessibilityIdentifier` suffix for the section header in UI tests.
  var scrollAnchor: String {
    switch self {
    case .stillNeedToPack: return "packingSheet.section.stillNeedToPack"
    case .packed: return "packingSheet.section.packed"
    case .notBringing: return "packingSheet.section.notBringing"
    case .stillInSuitcase: return "packingSheet.section.stillInSuitcase"
    case .backInSuitcase: return "packingSheet.section.backInSuitcase"
    case .leftBehind: return "packingSheet.section.leftBehind"
    }
  }

  /// Predicate selecting items that belong in this section.
  func matches(_ item: TripPackingItem) -> Bool {
    switch self {
    case .stillNeedToPack: return item.state == .unpacked
    case .packed: return item.state == .packed
    case .notBringing: return item.state == .excluded
    case .stillInSuitcase: return item.state == .packed
    case .backInSuitcase: return item.state == .repacked
    case .leftBehind: return item.state == .unpacked || item.state == .excluded
    }
  }
}

/// Single row inside the `PackingSheet`. Mirrors `TaskRow`'s structure with
/// packing-specific differences: the trailing avatar is replaced by an inline
/// Skip / Restore button (or nothing for read-only / repack groups), the
/// checkbox follows the pack vs repack colour rules in the UI doc, and the
/// `WhyDisclosureView` renders with `.packing(personColour:)` style.
///
/// Long-press is spatially constrained to the name + tags region so it does
/// not overlap with the trailing context menu (Req 6.5). Read-only rows
/// (`notBringing` / `leftBehind`) keep the long-press for `WhyDisclosure` per
/// Req 7.10 but expose no checkbox toggle, no Skip/Restore, and no Edit.
struct PackingItemRow: View {
  let item: TripPackingItem
  let group: SheetGroup
  let mode: PackingMode
  let personColour: Color
  let isDisclosureOpen: Bool
  let onToggleState: () -> Void
  let onSkipOrRestore: () -> Void
  let onLongPress: () -> Void
  let onEdit: () -> Void

  @Environment(\.modelContext) private var modelContext
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.isParticipantViewingSharedTrip) private var isParticipantViewingSharedTrip
  @State private var resolvedReason: WhyDisclosure.Reason?

  var body: some View {
    let variant = theme.variant(for: colorScheme)

    HStack(alignment: .top, spacing: 12) {
      checkbox(variant: variant)

      VStack(alignment: .leading, spacing: 6) {
        // Italic condition tags rendered when master available (deferred; placeholder for v1)
        Text(item.name)
          .font(.body)
          .foregroundStyle(group.isReadOnly ? variant.textSecondary : variant.textPrimary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
          .onLongPressGesture(minimumDuration: 0.4) {
            #if canImport(UIKit)
              UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            onLongPress()
          }

        if isDisclosureOpen, let reason = resolvedReason {
          WhyDisclosureView(reason: reason, style: .packing(personColour: personColour))
            #if DEBUG
              .accessibilityIdentifier("packingSheet.whyDisclosure.\(item.name)")
            #endif
        }
      }

      trailingAction(variant: variant)
    }
    .padding(.vertical, 8)
    .frame(minHeight: 44)
    .contentShape(Rectangle())
    .opacity(rowOpacity)
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      if !group.isReadOnly {
        Button {
          onEdit()
        } label: {
          Label("Edit", systemImage: "pencil")
        }
      }
    }
    .contextMenu {
      if !group.isReadOnly {
        Button {
          onEdit()
        } label: {
          Label("Edit", systemImage: "pencil")
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .modifier(
      WhyAccessibilityAction(
        enabled: PackingItemRow.hasWhyJustification(
          item: item,
          context: modelContext,
          hideOnUnresolvedMaster: isParticipantViewingSharedTrip
        ),
        onWhy: onLongPress
      )
    )
    .modifier(EditAccessibilityAction(enabled: !group.isReadOnly, onEdit: onEdit))
    .modifier(
      SkipRestoreAccessibilityAction(
        label: inlineActionLabel,
        onAction: onSkipOrRestore
      )
    )
    #if DEBUG
      .accessibilityIdentifier("packingSheet.itemRow.\(item.name)")
    #endif
    .onChange(of: isDisclosureOpen) { _, open in
      if open {
        resolvedReason = WhyResolver.reason(
          for: item,
          context: modelContext,
          hideOnUnresolvedMaster: isParticipantViewingSharedTrip
        )
      } else {
        resolvedReason = nil
      }
    }
    .onChange(of: item.trip?.attributesData) { _, _ in
      if isDisclosureOpen {
        resolvedReason = WhyResolver.reason(
          for: item,
          context: modelContext,
          hideOnUnresolvedMaster: isParticipantViewingSharedTrip
        )
      }
    }
    .onChange(of: item.currentlyMatchesRules) { _, _ in
      if isDisclosureOpen {
        resolvedReason = WhyResolver.reason(
          for: item,
          context: modelContext,
          hideOnUnresolvedMaster: isParticipantViewingSharedTrip
        )
      }
    }
  }

  // MARK: - Subviews

  @ViewBuilder
  private func checkbox(variant: ThemeVariant) -> some View {
    if group.isReadOnly {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(
          variant.textSecondary,
          style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
        )
        .frame(width: 24, height: 24)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    } else {
      Button(action: handleCheckboxTap) {
        ZStack {
          if isChecked {
            Circle()
              .fill(variant.checkColour)
              .frame(width: 24, height: 24)
            Image(systemName: "checkmark")
              .font(.system(size: 12, weight: .bold))
              .foregroundStyle(.white)
          } else {
            Circle()
              .strokeBorder(uncheckedStrokeColour(variant: variant), lineWidth: 2)
              .frame(width: 24, height: 24)
          }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isChecked ? "Mark not packed" : "Mark packed")
    }
  }

  @ViewBuilder
  private func trailingAction(variant: ThemeVariant) -> some View {
    if let label = inlineActionLabel {
      Button(action: handleSkipRestoreTap) {
        Text(label)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(variant.accent)
          .frame(minWidth: 44, minHeight: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(label)
    }
  }

  // MARK: - Interaction handlers

  private func handleCheckboxTap() {
    let target = targetGroupTitleForToggle
    #if canImport(UIKit)
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    #endif
    // Phase 6 Req 7.2 — fill/outline + row opacity/strikethrough
    // animate atomically inside a single withAnimation block.
    withAnimation(.scrambleStandard) {
      onToggleState()
    }
    if let target {
      announce(target)
    }
  }

  private func handleSkipRestoreTap() {
    let target = targetGroupTitleForSkipRestore
    #if canImport(UIKit)
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    #endif
    withAnimation(.scrambleStandard) {
      onSkipOrRestore()
    }
    if let target {
      announce(target)
    }
  }

  private func announce(_ targetGroupTitle: String) {
    #if canImport(UIKit)
      UIAccessibility.post(notification: .announcement, argument: "Moved to \(targetGroupTitle)")
    #endif
  }

  // MARK: - Visual state derivation

  /// Whether the row's checkbox is rendered in the "checked" state. Items
  /// already in their group's goal state (`.packed` for pack-mode, `.repacked`
  /// for repack-mode) appear pre-checked; tapping unchecks them.
  private var isChecked: Bool {
    switch group {
    case .packed, .backInSuitcase: return true
    case .stillNeedToPack, .stillInSuitcase: return false
    case .notBringing, .leftBehind: return false
    }
  }

  private func uncheckedStrokeColour(variant: ThemeVariant) -> Color {
    switch mode {
    case .pack: return personColour.opacity(0.67)
    case .repack: return variant.checkColour.opacity(0.67)
    }
  }

  /// Trailing inline-action label per group:
  /// - `Skip` for `stillNeedToPack` / `packed` (pack mode active groups)
  /// - `Restore` for `notBringing` (pack mode read-only group)
  /// - `nil` for repack-mode groups (no inline action per Req 4.2)
  private var inlineActionLabel: String? {
    switch group {
    case .stillNeedToPack, .packed: return "Skip"
    case .notBringing: return "Restore"
    case .stillInSuitcase, .backInSuitcase, .leftBehind: return nil
    }
  }

  /// Title of the section the item moves to when the checkbox is tapped, used
  /// for the VoiceOver announcement per Req 9.8. Returns `nil` for read-only
  /// groups (no toggle interaction) and for the repack-mode no-op edge cases.
  private var targetGroupTitleForToggle: String? {
    switch group {
    case .stillNeedToPack: return SheetGroup.packed.headerTitle
    case .packed: return SheetGroup.stillNeedToPack.headerTitle
    case .stillInSuitcase: return SheetGroup.backInSuitcase.headerTitle
    case .backInSuitcase: return SheetGroup.stillInSuitcase.headerTitle
    case .notBringing, .leftBehind: return nil
    }
  }

  /// Title of the section the item moves to when Skip/Restore is activated.
  private var targetGroupTitleForSkipRestore: String? {
    switch group {
    case .stillNeedToPack, .packed: return SheetGroup.notBringing.headerTitle
    case .notBringing: return SheetGroup.stillNeedToPack.headerTitle
    case .stillInSuitcase, .backInSuitcase, .leftBehind: return nil
    }
  }

  /// Combined VoiceOver label per Phase 6 Req 9.3 — item name + current
  /// `PackingState` + owning person. Read-only groups (`.leftBehind`,
  /// `.notBringing`) substitute the special state suffix the spec
  /// mandates ("left behind", "not bringing") rather than the raw
  /// PackingState word.
  private var accessibilityLabel: String {
    PackingItemRow.composedAccessibilityLabel(item: item, group: group)
  }

  static func composedAccessibilityLabel(
    item: TripPackingItem,
    group: SheetGroup
  ) -> String {
    var parts: [String] = [item.name]
    switch group {
    case .leftBehind:
      parts.append("left behind")
    case .notBringing:
      parts.append("not bringing")
    default:
      parts.append(stateWord(for: item.state))
    }
    if let ownerName = item.personSnapshot?.name, !ownerName.isEmpty {
      parts.append("owned by \(ownerName)")
    }
    return parts.joined(separator: ", ")
  }

  private static func stateWord(for state: PackingState) -> String {
    switch state {
    case .unpacked: return "not packed"
    case .packed: return "packed"
    case .repacked: return "repacked"
    case .excluded: return "not bringing"
    }
  }

  // Phase 6 Req 9.5 — "Why is this here?" gate, mirrors the long-press
  // disclosure's resolved-reason check.
  static func hasWhyJustification(
    item: TripPackingItem,
    context: ModelContext,
    hideOnUnresolvedMaster: Bool
  ) -> Bool {
    WhyResolver.reason(
      for: item, context: context, hideOnUnresolvedMaster: hideOnUnresolvedMaster
    ) != nil
  }

  /// Flat 0.5 dimming for unmatched-non-pinned rows per Req 3.9 / 4.8.
  /// Single multiplier — chained `.opacity()` modifiers compose
  /// multiplicatively, which would overshoot the design intent.
  private var rowOpacity: Double {
    (item.currentlyMatchesRules || item.pinnedByUser) ? 1.0 : 0.5
  }
}

// MARK: - Conditional accessibility-action modifiers

/// `.accessibilityAction(named:)` does not accept an `if` inline; conditional
/// rotor entries are expressed as small `ViewModifier`s that no-op when the
/// action is unavailable for the current group.
private struct EditAccessibilityAction: ViewModifier {
  let enabled: Bool
  let onEdit: () -> Void

  func body(content: Content) -> some View {
    if enabled {
      content.accessibilityAction(named: Text("Edit")) { onEdit() }
    } else {
      content
    }
  }
}

/// Phase 6 Req 9.5 — exposes the "Why is this here?" custom action only
/// when the underlying item has a non-nil `WhyResolver.reason(...)`.
private struct WhyAccessibilityAction: ViewModifier {
  let enabled: Bool
  let onWhy: () -> Void

  func body(content: Content) -> some View {
    if enabled {
      content.accessibilityAction(named: Text("Why is this here?")) { onWhy() }
    } else {
      content
    }
  }
}

private struct SkipRestoreAccessibilityAction: ViewModifier {
  let label: String?
  let onAction: () -> Void

  func body(content: Content) -> some View {
    if let label {
      content.accessibilityAction(named: Text(label)) { onAction() }
    } else {
      content
    }
  }
}
