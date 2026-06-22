import SwiftData
import SwiftUI
import os

#if canImport(UIKit)
  import UIKit
#endif

/// Sheet presentation identity for `PackingSheet`. Bound to
/// `TripDetailView.packingSheetState` via `.sheet(item:)`. The identity
/// includes both person and mode so SwiftUI dismisses-and-replaces correctly
/// if the same person is opened in a different mode (defensive: the
/// one-at-a-time accordion already prevents two packing phases from being
/// open simultaneously, but the identity should not depend on that).
struct PackingSheetState: Identifiable {
  let person: Person
  let mode: PackingMode

  var id: String {
    let modeKey: String = {
      switch mode {
      case .pack: return "pack"
      case .repack: return "repack"
      }
    }()
    return "\(person.id.uuidString)|\(modeKey)"
  }
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
  /// Identity of the row whose inline sub-item add field is currently
  /// revealed, so the background tap-catcher can be mounted to dismiss it
  /// (design § "Focus / keyboard / dismissal"). Reported by `PackingItemRow`.
  @State private var activeAddFieldItemID: UUID?
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
    Set((trip.participantSnapshots ?? []).map(\.personID))
  }

  var body: some View {
    let personItems = PackingListHelpers.itemsForPerson(trip, person: person)

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
                personItems: personItems,
                group: group,
                mode: mode,
                personColour: personColour,
                openDisclosureItemID: $openDisclosureItemID,
                activeAddFieldItemID: $activeAddFieldItemID,
                onEdit: { item in
                  pendingForm = .edit(item: item)
                }
              )
              .id(group.scrollAnchor)
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
          if let firstAnchor = groups.first?.scrollAnchor {
            proxy.scrollTo(firstAnchor, anchor: .top)
          }
          try? await Task.sleep(for: .milliseconds(500))
          headerFocused = true
        }
      }
      .background {
        // Disclosure / add-field dismiss tap target, mounted only when a
        // disclosure or an inline add field is open. Lives on the background
        // so it can't intercept taps destined for checkboxes, action buttons,
        // or the close button. Ending editing makes the active add field lose
        // focus, which collapses it (design § "Focus / keyboard / dismissal").
        if openDisclosureItemID != nil || activeAddFieldItemID != nil {
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
              openDisclosureItemID = nil
              activeAddFieldItemID = nil
              endTextEditing()
            }
        }
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    // Phase 6 Req 8.3 — soft-impact haptic when the sheet presents.
    .onAppear {
      #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
      #endif
    }
    .task(id: participantIDSignature) {
      // Capture once so the id-driven re-evaluation and the body check
      // always observe the same snapshot, independent of any in-flight
      // SwiftData mutation that might land between the two reads.
      let signature = participantIDSignature
      if !signature.contains(person.id) {
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

  /// Resigns first responder app-wide so the inline add field loses focus and
  /// self-collapses. No-op off UIKit.
  private func endTextEditing() {
    #if canImport(UIKit)
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
      )
    #endif
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
  let personItems: [TripPackingItem]
  let group: SheetGroup
  let mode: PackingMode
  let personColour: Color
  @Binding var openDisclosureItemID: UUID?
  @Binding var activeAddFieldItemID: UUID?
  let onEdit: (TripPackingItem) -> Void

  @Environment(\.modelContext) private var modelContext
  @Environment(\.localWriteHook) private var hook
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let variant = theme.variant(for: colorScheme)
    let items = PackingListHelpers.sorted(personItems.filter(group.matches))

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
          onEdit: { onEdit(item) },
          onAddSubItem: { raw in addSubItem(item, raw) },
          onRemoveSubItem: { index in removeSubItem(item, at: index) },
          onAddFieldVisibilityChanged: { visible in
            activeAddFieldItemID = visible ? item.id : nil
          }
        )
      }
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

  /// Appends a sub-item via the pure `PackingSubItems` helper, then commits
  /// through the same `hook.commit` chokepoint as the checkbox/skip
  /// mutations. The cap / empty guards reject *before* any write (Decision 9),
  /// and adding never changes the item's state or group (Req 2.5).
  private func addSubItem(_ item: TripPackingItem, _ raw: String) {
    switch PackingSubItems.appending(raw, to: item.subItems) {
    case .added(let list):
      item.subItems = list
      save("addSubItem")
    case .rejectedEmpty, .rejectedFull:
      return
    }
  }

  /// Removes the sub-item at `index` (positional, Req 3.2) and commits.
  /// Removing never changes the item's state (Req 3.3).
  private func removeSubItem(_ item: TripPackingItem, at index: Int) {
    item.subItems = PackingSubItems.removing(at: index, from: item.subItems)
    save("removeSubItem")
  }

  private func save(_ marker: String) {
    do {
      try hook.commit(modelContext)
    } catch {
      modelLogger.error(
        "[PackingSheet.save-failed] \(marker, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
    }
  }
}
