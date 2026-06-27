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
/// Day-before (`pack`) or Day-before-return (`repack`) phase. Owns its inner
/// state — active inline-add-field id, manual-add form presentation — and
/// dismisses when the bound person disappears from `trip.participants` (Req 2.8).
struct PackingSheet: View {
  let trip: Trip
  let person: Person
  let mode: PackingMode
  let onDismiss: () -> Void

  @Environment(\.modelContext) private var modelContext
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme
  // Held so they can be re-injected onto the presented `PackingItemForm`: a
  // `.sheet` does not inherit custom environment keys from its presenter, so
  // the form's read-only gate and cross-container suggestions would silently
  // break without this. `isParticipantViewingSharedTrip` is re-injected onto
  // this sheet by `TripDetailView` (it is set deep in that view, below the
  // scene root); `globalsContainer` resolves via the scene-root injection /
  // default.
  @Environment(\.isParticipantViewingSharedTrip) private var isParticipantViewingSharedTrip
  @Environment(\.globalsContainer) private var globalsContainer

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
              onClose: onDismiss
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
        // Add-field dismiss tap target, mounted only when an inline add field
        // is open. Lives on the background so it can't intercept taps destined
        // for checkboxes, action buttons, or the close button. Ending editing
        // makes the active add field lose focus, which collapses it
        // (design § "Focus / keyboard / dismissal").
        if activeAddFieldItemID != nil {
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
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
      // Re-inject both keys: a `.sheet` does not inherit custom environment
      // keys, so the form's read-only gate (Req 3.5) and cross-container
      // suggestions would otherwise fall back to their defaults.
      .environment(\.isParticipantViewingSharedTrip, isParticipantViewingSharedTrip)
      .environment(\.globalsContainer, globalsContainer)
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
  @Binding var activeAddFieldItemID: UUID?
  let onEdit: (TripPackingItem) -> Void

  @Environment(\.modelContext) private var modelContext
  @Environment(\.localWriteHook) private var hook
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let variant = theme.variant(for: colorScheme)
    // One pass per body (Req 5.7): filter to the group, then sub-group by
    // category. `sortWithin` keeps the existing active-before-dimmed, then
    // case-insensitive-name order within each category (Req 5.3). One-off items
    // (nil `masterItemID`) group identically to master-derived (Req 4.2), and
    // never-categorised items fall into the uncategorised bucket (Req 1.4).
    let sections = PackingListHelpers.categorySections(
      personItems.filter(group.matches),
      category: \.category,
      sortWithin: PackingListHelpers.sorted
    )

    VStack(alignment: .leading, spacing: 8) {
      Text(group.headerTitle)
        .font(.system(size: 11, weight: .heavy))
        .textCase(.uppercase)
        .foregroundStyle(headerColour(variant: variant))
        .padding(.top, 4)

      // A category sub-header renders only when the section has a label. The
      // all-uncategorised case is a single `key == nil` / `label == nil`
      // section, so its rows render flat with no sub-header (Req 5.5); a mixed
      // list shows a header per categorised group and leaves the trailing
      // uncategorised rows un-headered.
      ForEach(sections, id: \.key) { section in
        if let label = section.label {
          // `verbatim:` — category labels are user-typed free text, not a
          // localisation key.
          Text(verbatim: label)
            .font(.system(size: 11, weight: .heavy))
            .textCase(.uppercase)
            .foregroundStyle(variant.textSecondary)
            .padding(.top, 2)
            .accessibilityAddTraits(.isHeader)
        }
        ForEach(section.items, id: \.id) { item in
          row(for: item)
        }
      }
    }
  }

  /// One packing row, factored out so the flat and sub-grouped branches share
  /// identical row wiring.
  @ViewBuilder
  private func row(for item: TripPackingItem) -> some View {
    PackingItemRow(
      item: item,
      group: group,
      mode: mode,
      personColour: personColour,
      onToggleState: { toggleState(item) },
      onSkipOrRestore: { skipOrRestore(item) },
      onEdit: { onEdit(item) },
      onSaveNote: { raw in saveNote(item, raw) },
      onAddSubItem: { raw in addSubItem(item, raw) },
      onRemoveSubItem: { index in removeSubItem(item, at: index) },
      onAddFieldVisibilityChanged: { visible in
        if visible {
          activeAddFieldItemID = item.id
        } else if activeAddFieldItemID == item.id {
          // Clear only when *this* row owns the catcher. Opening a
          // different row's editor closes this one in the same render pass;
          // cross-row onChange ordering is unspecified, so an additive set
          // (above) plus an own-id-gated clear keeps the tap-catcher
          // mounted for whichever editor is actually open.
          activeAddFieldItemID = nil
        }
      }
    )
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

  /// Saves the inline-edited note via the same `sanitizedNote` semantics as the
  /// edit form (trim + 500-cap, nil on empty) and commits through the hook
  /// chokepoint. Never changes the item's state or group. No-op when the
  /// sanitized value is unchanged so merely opening + dismissing the note
  /// editor (or a save-on-disappear fallback firing after a blur save) does
  /// not dirty the model and push a spurious CKRecord to trip participants.
  private func saveNote(_ item: TripPackingItem, _ raw: String) {
    let sanitized = PackingSubItems.sanitizedNote(raw)
    guard sanitized != item.note else { return }
    item.note = sanitized
    save("saveNote")
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
