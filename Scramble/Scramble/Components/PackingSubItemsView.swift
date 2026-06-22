import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

/// Inline note + sub-item list renderer for a `PackingItemRow` (feature
/// `packing-item-subitems`, design § "Components and Interfaces →
/// PackingSubItemsView"). Purely presentational: it takes plain values, never
/// an `@Model` reference, so its only refresh trigger is the parent
/// re-rendering (`PackingItemRow` reads `item.note` / `item.subItems`
/// directly so SwiftData establishes observation — an inbound sync re-renders
/// the row, which re-seeds this view).
///
/// Layout, top to bottom:
///   - the note (secondary text; tappable → `onEditNote` on interactive rows),
///   - the sub-item rows (each with a Remove control on interactive rows),
///   - a reveal-on-tap "＋ add item" affordance (interactive rows only, hidden
///     once `subItems.count == PackingSubItems.maxCount`).
///
/// Empty + non-interactive ⇒ renders nothing, leaving the row layout
/// unchanged (Req 5.3).
struct PackingSubItemsView: View {
  let note: String?
  let subItems: [String]
  /// `== !SheetGroup.isReadOnly`. Gates the note-edit tap, the per-entry
  /// Remove control, and the add affordance (Req 5.2 / 5.4 / Decision 4).
  let isInteractive: Bool
  /// Person colour, used as the accent for the add affordance and Remove
  /// controls (matches the sheet's person-colour semantics).
  let accent: Color
  let onAdd: (String) -> Void
  /// Removes the sub-item at the given list index (by position, not value,
  /// because duplicates are allowed — Req 2.6 / 3.2).
  let onRemove: (Int) -> Void
  let onEditNote: () -> Void
  /// Reports when the inline add field is revealed (`true`) or collapsed
  /// (`false`) so the sheet can mount its background tap-catcher to dismiss it.
  let onAddFieldVisibilityChanged: (Bool) -> Void

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  /// Row-local mirror of `subItems`, giving each entry a stable identity for
  /// `ForEach` (a flat `[String]` with duplicates has no natural stable id and
  /// `id: \.self` would collapse / mis-target duplicate rows — design §
  /// "List identity"). Re-seeded on `.onChange(of: subItems)` (e.g. an inbound
  /// sync). The stored model stays `[String]` — no persisted ids.
  @State private var drafts: [SubItemDraft]
  @State private var isAddFieldVisible = false
  @State private var addText = ""
  @FocusState private var addFieldFocused: Bool

  /// One sub-item entry plus a stable id for `ForEach`. There is no inline
  /// rename, so re-seeding on sync never discards an in-progress edit.
  private struct SubItemDraft: Identifiable, Equatable {
    let id = UUID()
    let text: String
  }

  init(
    note: String?,
    subItems: [String],
    isInteractive: Bool,
    accent: Color,
    onAdd: @escaping (String) -> Void,
    onRemove: @escaping (Int) -> Void,
    onEditNote: @escaping () -> Void,
    onAddFieldVisibilityChanged: @escaping (Bool) -> Void = { _ in }
  ) {
    self.note = note
    self.subItems = subItems
    self.isInteractive = isInteractive
    self.accent = accent
    self.onAdd = onAdd
    self.onRemove = onRemove
    self.onEditNote = onEditNote
    self.onAddFieldVisibilityChanged = onAddFieldVisibilityChanged
    _drafts = State(initialValue: subItems.map { SubItemDraft(text: $0) })
  }

  var body: some View {
    let variant = theme.variant(for: colorScheme)

    VStack(alignment: .leading, spacing: 6) {
      noteView(variant: variant)
      subItemList(variant: variant)
      addAffordance(variant: variant)
    }
    .onChange(of: subItems) { _, newValue in
      drafts = newValue.map { SubItemDraft(text: $0) }
    }
    .onChange(of: isAddFieldVisible) { _, visible in
      onAddFieldVisibilityChanged(visible)
    }
  }

  // MARK: - Note

  @ViewBuilder
  private func noteView(variant: ThemeVariant) -> some View {
    if let note, !note.isEmpty {
      Text(note)
        .font(.footnote)
        .italic()
        .foregroundStyle(variant.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(NoteTapModifier(enabled: isInteractive, onEditNote: onEditNote))
        .accessibilityLabel("Note: \(note)")
        .accessibilityAddTraits(isInteractive ? .isButton : [])
        #if DEBUG
          .accessibilityIdentifier("packingSubItems.note")
        #endif
    }
  }

  // MARK: - Sub-item list

  @ViewBuilder
  private func subItemList(variant: ThemeVariant) -> some View {
    if !drafts.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(drafts) { draft in
          subItemRow(draft, variant: variant)
        }
      }
      .accessibilityElement(children: .contain)
    }
  }

  @ViewBuilder
  private func subItemRow(_ draft: SubItemDraft, variant: ThemeVariant) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Text("•")
        .font(.footnote)
        .foregroundStyle(variant.textSecondary)
        .accessibilityHidden(true)

      // The text is the entry's addressable element: labelled "sub-item: …"
      // and carrying the per-entry Remove custom action (Req 8.2). The visible
      // remove button is a separate sibling so it stays tappable by pointer /
      // UI tests without being flattened into the text element.
      Text(draft.text)
        .font(.footnote)
        .foregroundStyle(variant.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("sub-item: \(draft.text)")
        .modifier(
          RemoveAccessibilityAction(
            enabled: isInteractive,
            onRemove: { removeDraft(draft) }
          )
        )
        #if DEBUG
          .accessibilityIdentifier("packingSubItems.entry.\(draft.text)")
        #endif

      if isInteractive {
        removeButton(for: draft, variant: variant)
      }
    }
  }

  @ViewBuilder
  private func removeButton(for draft: SubItemDraft, variant: ThemeVariant) -> some View {
    Button {
      removeDraft(draft)
    } label: {
      Image(systemName: "minus.circle")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(accent)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Remove \(draft.text)")
    #if DEBUG
      .accessibilityIdentifier("packingSubItems.remove.\(draft.text)")
    #endif
  }

  // MARK: - Add affordance

  @ViewBuilder
  private func addAffordance(variant: ThemeVariant) -> some View {
    if isInteractive && subItems.count < PackingSubItems.maxCount {
      if isAddFieldVisible {
        addField(variant: variant)
      } else {
        Button {
          revealAddField()
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "plus")
            Text("add item")
          }
          .font(.footnote.weight(.semibold))
          .foregroundStyle(accent)
          .frame(minHeight: 44, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add sub-item")
        #if DEBUG
          .accessibilityIdentifier("packingSubItems.addButton")
        #endif
      }
    }
  }

  @ViewBuilder
  private func addField(variant: ThemeVariant) -> some View {
    TextField("Add sub-item", text: $addText)
      .font(.footnote)
      .foregroundStyle(variant.textPrimary)
      .focused($addFieldFocused)
      .submitLabel(.done)
      .padding(.vertical, 8)
      .padding(.horizontal, 10)
      .frame(minHeight: 44)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(variant.surface)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(accent.opacity(0.6), lineWidth: 1)
      )
      .onChange(of: addText) { _, new in
        // Live 200-grapheme cap, mirroring `PackingItemForm.cappedName`.
        let capped = PackingSubItems.cappedEntry(new)
        if capped != new { addText = capped }
      }
      .onSubmit(submitAddField)
      .onChange(of: addFieldFocused) { _, focused in
        // Blur dismisses the field (design § "Focus / keyboard / dismissal").
        if !focused { isAddFieldVisible = false }
      }
      #if DEBUG
        .accessibilityIdentifier("packingSubItems.addField")
      #endif
  }

  // MARK: - Actions

  private func revealAddField() {
    addText = ""
    isAddFieldVisible = true
    addFieldFocused = true
  }

  /// Appends the typed entry (if non-empty) and keeps the field open for rapid
  /// multi-add (design § "Density"). An empty submit dismisses the field.
  private func submitAddField() {
    let trimmed = addText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      isAddFieldVisible = false
      addFieldFocused = false
      return
    }
    onAdd(addText)
    addText = ""
    // Stay open and focused for the next entry.
    addFieldFocused = true
  }

  /// Maps the draft to its current position in `subItems` and removes by index
  /// (positional, so duplicates target the right row — Req 2.6 / 3.2).
  private func removeDraft(_ draft: SubItemDraft) {
    guard let index = drafts.firstIndex(of: draft) else { return }
    onRemove(index)
  }
}

// MARK: - Conditional modifiers

/// The note is tappable-to-edit only on interactive rows; on read-only rows it
/// displays as plain text (Decision 4 / 13).
private struct NoteTapModifier: ViewModifier {
  let enabled: Bool
  let onEditNote: () -> Void

  func body(content: Content) -> some View {
    if enabled {
      content.onTapGesture { onEditNote() }
    } else {
      content
    }
  }
}

/// Per-entry VoiceOver Remove action, present only on interactive rows
/// (Req 8.2). The visible Remove button is `accessibilityHidden` so the
/// custom action is the single addressable removal path per entry.
private struct RemoveAccessibilityAction: ViewModifier {
  let enabled: Bool
  let onRemove: () -> Void

  func body(content: Content) -> some View {
    if enabled {
      content.accessibilityAction(named: Text("Remove")) { onRemove() }
    } else {
      content
    }
  }
}
