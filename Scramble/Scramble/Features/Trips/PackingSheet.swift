import SwiftData
import SwiftUI
import os

#if canImport(UIKit)
  import UIKit
#endif

/// Sheet presentation identity for `PackingSheet`. Bound to
/// `TripDetailView.packingSheetState` via `.sheet(item:)`. `id` keys on the
/// person so SwiftUI uses the same sheet instance when re-presenting for the
/// same person across re-renders.
struct PackingSheetState: Identifiable {
  let person: Person
  let mode: PackingMode

  var id: UUID { person.id }
}

/// Per-person packing surface presented from a participant row inside the
/// Departure (`pack`) or Day-before-return (`repack`) phase. Owns its inner
/// state — disclosure id, manual-add form presentation — and dismisses when
/// the bound person disappears from `trip.participants` (Req 2.8).
struct PackingSheet: View {
  let trip: Trip
  let person: Person
  let mode: PackingMode
  let onDismiss: () -> Void

  @Environment(\.modelContext) private var modelContext
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  @State private var openDisclosureItemID: UUID?
  @State private var pendingForm: PackingItemFormPresentation?
  @AccessibilityFocusState private var headerFocused: Bool

  private var groups: [SheetGroup] {
    switch mode {
    case .pack: return [.stillNeedToPack, .packed, .notBringing]
    case .repack: return [.stillInSuitcase, .backInSuitcase, .leftBehind]
    }
  }

  private var personColour: Color {
    theme.personColor(key: person.colorKey, in: colorScheme) ?? .gray
  }

  private var participantIDSignature: Set<UUID> {
    Set((trip.participants ?? []).map(\.id))
  }

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 16) {
            PackingSheetHeader(
              trip: trip,
              person: person,
              mode: mode,
              personColour: personColour,
              headerFocused: $headerFocused,
              onClose: handleClose
            )
            #if DEBUG
              .accessibilityIdentifier("packingSheet.header")
            #endif

            ForEach(groups, id: \.self) { group in
              PackingItemGroup(
                trip: trip,
                person: person,
                group: group,
                mode: mode,
                personColour: personColour,
                openDisclosureItemID: $openDisclosureItemID,
                onEdit: { item in
                  pendingForm = .edit(item: item)
                }
              )
              .id(scrollAnchor(for: group))
            }

            if mode == .pack {
              DashedAddButton(
                title: "Add item for \(person.shortDisplayName)",
                accent: personColour,
                action: { pendingForm = .add(person: person, trip: trip) }
              )
              #if DEBUG
                .accessibilityIdentifier("packingSheet.addItemButton")
              #endif
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
        }
        .task {
          if let firstAnchor = groups.first.map(scrollAnchor(for:)) {
            proxy.scrollTo(firstAnchor, anchor: .top)
          }
          try? await Task.sleep(for: .milliseconds(500))
          headerFocused = true
        }
      }
      .background {
        // Disclosure-dismiss tap target, mounted only when a disclosure is
        // open. Lives on the background so it can't intercept taps destined
        // for checkboxes, action buttons, or the close button.
        if openDisclosureItemID != nil {
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture { openDisclosureItemID = nil }
        }
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    .task(id: participantIDSignature) {
      if !participantIDSignature.contains(person.id) {
        onDismiss()
      }
    }
    .sheet(item: $pendingForm) { presentation in
      PackingItemForm(
        mode: presentation,
        onSave: { pendingForm = nil },
        onCancel: { pendingForm = nil }
      )
    }
  }

  private func handleClose() {
    if openDisclosureItemID != nil {
      openDisclosureItemID = nil
    } else {
      onDismiss()
    }
  }

  private func scrollAnchor(for group: SheetGroup) -> String {
    "packingSheet.section.\(scrollAnchorRaw(for: group))"
  }

  private func scrollAnchorRaw(for group: SheetGroup) -> String {
    switch group {
    case .stillNeedToPack: return "stillNeedToPack"
    case .packed: return "packed"
    case .notBringing: return "notBringing"
    case .stillInSuitcase: return "stillInSuitcase"
    case .backInSuitcase: return "backInSuitcase"
    case .leftBehind: return "leftBehind"
    }
  }
}

// MARK: - PackingSheetHeader

/// Drag handle is system-supplied via `presentationDragIndicator(.visible)`.
/// The header hosts the avatar, name, counter, and close button. The counter
/// reads `PackingListHelpers.counts(for:in:)` directly off `trip` so it
/// re-renders on any underlying `TripPackingItem.state` change.
private struct PackingSheetHeader: View {
  let trip: Trip
  let person: Person
  let mode: PackingMode
  let personColour: Color
  @AccessibilityFocusState.Binding var headerFocused: Bool
  let onClose: () -> Void

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let variant = theme.variant(for: colorScheme)
    let counts = PackingListHelpers.counts(for: person, in: trip)

    HStack(alignment: .center, spacing: 12) {
      PersonAvatar(
        name: person.name,
        colorKey: person.colorKey,
        size: .large,
        isActive: true
      )

      VStack(alignment: .leading, spacing: 2) {
        Text(person.name)
          .font(.headline)
          .foregroundStyle(variant.textPrimary)
        Text(counterText(counts: counts))
          .font(.subheadline)
          .foregroundStyle(variant.textSecondary)
          #if DEBUG
            .accessibilityIdentifier("packingSheet.counter")
          #endif
      }

      Spacer(minLength: 0)

      Button(action: onClose) {
        Image(systemName: "xmark.circle.fill")
          .font(.title2)
          .foregroundStyle(variant.textSecondary)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.escape, modifiers: [])
      .accessibilityLabel("Close")
    }
    .padding(.vertical, 8)
    .accessibilityElement(children: .combine)
    .accessibilityFocused($headerFocused)
  }

  private func counterText(counts: PackingCounts) -> String {
    switch mode {
    case .pack:
      let denom = counts.toPack + counts.packed
      return "\(counts.packed)/\(denom) packed"
    case .repack:
      let denom = counts.packed + counts.repacked
      return "\(counts.repacked)/\(denom) repacked"
    }
  }
}

// MARK: - PackingItemGroup

/// One section inside the sheet body. Filters `trip.packingItems` to the
/// active `Person`, narrows to the group's predicate, sorts via
/// `PackingListHelpers.sorted`, and renders the section header plus a row
/// per item. Empty groups render the header only (Req 3.2).
private struct PackingItemGroup: View {
  let trip: Trip
  let person: Person
  let group: SheetGroup
  let mode: PackingMode
  let personColour: Color
  @Binding var openDisclosureItemID: UUID?
  let onEdit: (TripPackingItem) -> Void

  @Environment(\.modelContext) private var modelContext
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let variant = theme.variant(for: colorScheme)
    let items = visibleItems

    VStack(alignment: .leading, spacing: 8) {
      Text(group.headerTitle)
        .font(.system(size: 11, weight: .heavy))
        .textCase(.uppercase)
        .foregroundStyle(headerColour(variant: variant))
        .padding(.top, 4)

      ForEach(items, id: \.id) { item in
        PackingItemRow(
          item: item,
          group: group,
          mode: mode,
          personColour: personColour,
          isDisclosureOpen: openDisclosureItemID == item.id,
          onToggleState: { toggleState(item) },
          onSkipOrRestore: { skipOrRestore(item) },
          onLongPress: { toggleDisclosure(item) },
          onEdit: { onEdit(item) }
        )
      }
    }
  }

  private var visibleItems: [TripPackingItem] {
    let all = (trip.packingItems ?? []).filter { $0.person?.id == person.id }
    let filtered = all.filter(matches)
    return PackingListHelpers.sorted(filtered)
  }

  private func matches(_ item: TripPackingItem) -> Bool {
    switch group {
    case .stillNeedToPack: return item.state == .unpacked
    case .packed: return item.state == .packed
    case .notBringing: return item.state == .excluded
    case .stillInSuitcase: return item.state == .packed
    case .backInSuitcase: return item.state == .repacked
    case .leftBehind: return item.state == .unpacked || item.state == .excluded
    }
  }

  private func headerColour(variant: ThemeVariant) -> Color {
    switch group {
    case .stillNeedToPack, .stillInSuitcase: return variant.warnColour
    case .packed, .backInSuitcase: return variant.checkColour
    case .notBringing, .leftBehind: return variant.textSecondary
    }
  }

  // MARK: - Mutations

  private func toggleState(_ item: TripPackingItem) {
    switch (mode, item.state) {
    case (.pack, .unpacked): item.state = .packed
    case (.pack, .packed): item.state = .unpacked
    case (.repack, .packed): item.state = .repacked
    case (.repack, .repacked): item.state = .packed
    default: return
    }
    save("toggleState")
  }

  private func skipOrRestore(_ item: TripPackingItem) {
    switch group {
    case .stillNeedToPack, .packed: item.state = .excluded
    case .notBringing: item.state = .unpacked
    default: return
    }
    save("skipOrRestore")
  }

  private func toggleDisclosure(_ item: TripPackingItem) {
    openDisclosureItemID = (openDisclosureItemID == item.id) ? nil : item.id
  }

  private func save(_ marker: String) {
    do {
      try modelContext.save()
    } catch {
      modelLogger.error(
        "[PackingSheet.save-failed] \(marker, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
    }
  }
}
