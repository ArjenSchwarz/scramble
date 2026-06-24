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
///   - the inline add field, shown only while the parent row's `+` button
///     (left of Skip) has set `isAddFieldVisible` (interactive rows only,
///     suppressed once `subItems.count == PackingSubItems.maxCount`).
///
/// Empty + non-interactive ⇒ renders nothing; empty + interactive with the
/// add field closed ⇒ also renders nothing, so a sub-item-less row stays a
/// single line (the `+` lives in `PackingItemRow`, not here).
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
  /// Saves the inline-edited note (raw text; the sheet applies `sanitizedNote`).
  let onSaveNote: (String) -> Void

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  /// Row-local mirror of `subItems`, giving each entry a stable identity for
  /// `ForEach` (a flat `[String]` with duplicates has no natural stable id and
  /// `id: \.self` would collapse / mis-target duplicate rows — design §
  /// "List identity"). Re-seeded on `.onChange(of: subItems)` (e.g. an inbound
  /// sync). The stored model stays `[String]` — no persisted ids.
  @State private var drafts: [SubItemDraft]
  /// Controlled by the parent row's `+` button (left of Skip) so the add
  /// field reveals from the trailing controls instead of a persistent
  /// affordance row under the item.
  @Binding private var isAddFieldVisible: Bool
  @State private var addText = ""
  @FocusState private var addFieldFocused: Bool
  /// Controlled by the parent row's note glyph. When true, the note renders as
  /// an editable field (seeded from `note`) instead of static text.
  @Binding private var isEditingNote: Bool
  @State private var noteDraft = ""
  @FocusState private var noteFocused: Bool

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
    isAddFieldVisible: Binding<Bool>,
    isEditingNote: Binding<Bool>,
    onAdd: @escaping (String) -> Void,
    onRemove: @escaping (Int) -> Void,
    onSaveNote: @escaping (String) -> Void
  ) {
    self.note = note
    self.subItems = subItems
    self.isInteractive = isInteractive
    self.accent = accent
    _isAddFieldVisible = isAddFieldVisible
    _isEditingNote = isEditingNote
    self.onAdd = onAdd
    self.onRemove = onRemove
    self.onSaveNote = onSaveNote
    _drafts = State(initialValue: subItems.map { SubItemDraft(text: $0) })
  }

  var body: some View {
    let variant = theme.variant(for: colorScheme)

    VStack(alignment: .leading, spacing: 6) {
      noteSection(variant: variant)
      subItemList(variant: variant)
      addAffordance(variant: variant)
    }
    .onChange(of: subItems) { _, newValue in
      drafts = reseededDrafts(for: newValue)
    }
    .onChange(of: isAddFieldVisible) { _, visible in
      // Reveal originates from the parent's list glyph; seed + focus the field
      // here when it becomes visible. The parent owns visibility reporting to
      // the sheet (one combined source of truth), so this view no longer fires
      // a per-binding callback.
      if visible {
        addText = ""
        addFieldFocused = true
      }
    }
    .onChange(of: isEditingNote) { _, editing in
      if editing {
        // Seed the draft from the current note and focus when the glyph opens it.
        noteDraft = note ?? ""
        noteFocused = true
      } else {
        // Commit on *any* close — a blur, the background tap, or switching to the
        // sub-item glyph (which sets this false before the field can blur-save).
        // `saveNote` no-ops on an unchanged value, so this never double-writes.
        onSaveNote(noteDraft)
      }
    }
    .onDisappear {
      // Save fallback: on a native sheet swipe-down dismiss, `@FocusState` blur
      // (and the `isEditingNote` `.onChange` above) are not guaranteed to fire
      // before teardown, which would silently drop an in-progress note edit.
      guard isEditingNote else { return }
      onSaveNote(noteDraft)
    }
  }

  /// Re-seed the draft mirror from `subItems`, preserving each existing entry's
  /// id where the value at that position is unchanged. Sub-items only ever
  /// append or remove-by-position (no reorder / inline rename), so positional
  /// reuse keeps `ForEach` identity stable for untouched rows — a one-item sync
  /// no longer re-animates the whole list.
  private func reseededDrafts(for newValue: [String]) -> [SubItemDraft] {
    newValue.enumerated().map { index, text in
      if index < drafts.count, drafts[index].text == text { return drafts[index] }
      return SubItemDraft(text: text)
    }
  }

  // MARK: - Note

  /// The note region: an editable field while the note glyph has opened it,
  /// otherwise the static (tappable-to-edit) note text when a note exists.
  @ViewBuilder
  private func noteSection(variant: ThemeVariant) -> some View {
    if isEditingNote {
      noteEditor(variant: variant)
    } else if let note, !note.isEmpty {
      noteText(note, variant: variant)
    }
  }

  @ViewBuilder
  private func noteText(_ note: String, variant: ThemeVariant) -> some View {
    Text(note)
      .font(.subheadline)
      .italic()
      .foregroundStyle(variant.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .modifier(NoteTapModifier(enabled: isInteractive, onEditNote: revealNoteEditor))
      .accessibilityLabel("Note: \(note)")
      .accessibilityAddTraits(isInteractive ? .isButton : [])
      #if DEBUG
        .accessibilityIdentifier("packingSubItems.note")
      #endif
  }

  @ViewBuilder
  private func noteEditor(variant: ThemeVariant) -> some View {
    TextField("Note", text: $noteDraft, axis: .vertical)
      .font(.subheadline)
      .foregroundStyle(variant.textPrimary)
      .focused($noteFocused)
      .lineLimit(1...4)
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
      .onChange(of: noteDraft) { _, new in
        // Live 500-grapheme cap (mirrors the edit form's note cap).
        let capped = PackingSubItems.cappedNote(new)
        if capped != new { noteDraft = capped }
      }
      .onChange(of: noteFocused) { _, focused in
        // Blur closes the editor; the actual save happens on the
        // `isEditingNote` false transition (one place, covers every close path).
        if !focused { isEditingNote = false }
      }
      #if DEBUG
        .accessibilityIdentifier("packingSubItems.noteField")
      #endif
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
    // Centre-aligned so the bullet and the 44pt Remove button line up with the
    // entry text (top alignment left the Remove glyph sitting below the line).
    HStack(alignment: .center, spacing: 8) {
      Text("•")
        .font(.subheadline)
        .foregroundStyle(variant.textSecondary)
        .accessibilityHidden(true)

      // The entry text is the row's label element; the per-entry removal is the
      // sibling Remove button (labelled "Remove …", Req 8.2) — a single,
      // discoverable VoiceOver removal path rather than a duplicate rotor
      // action on the text. On read-only rows the button is absent (no remove).
      Text(draft.text)
        .font(.subheadline)
        .foregroundStyle(variant.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("sub-item: \(draft.text)")
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

  /// The inline add field, shown only while the parent's `+` button has
  /// revealed it (`isAddFieldVisible`). The persistent "add item" affordance
  /// row was removed in favour of the trailing `+` so an item with no
  /// sub-items keeps a single-line row.
  @ViewBuilder
  private func addAffordance(variant: ThemeVariant) -> some View {
    if isInteractive && subItems.count < PackingSubItems.maxCount && isAddFieldVisible {
      addField(variant: variant)
    }
  }

  @ViewBuilder
  private func addField(variant: ThemeVariant) -> some View {
    TextField("Add sub-item", text: $addText)
      .font(.subheadline)
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

  /// Tapping the static note text opens the inline editor (same path as the
  /// note glyph). Closes the sub-item add field for one-editor-at-a-time.
  private func revealNoteEditor() {
    isAddFieldVisible = false
    isEditingNote = true
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
    // `trimmed` is already non-empty here; `appending`'s `sanitizedEntry` still
    // caps length, so passing the trimmed value avoids a second trim/allocation.
    onAdd(trimmed)
    addText = ""
    if subItems.count + 1 >= PackingSubItems.maxCount {
      // This add fills the list. The cap guard removes the field on the next
      // render, so its blur `.onChange` won't fire — close it explicitly here
      // to keep `isAddFieldVisible` (and the parent's list glyph) in sync.
      isAddFieldVisible = false
      addFieldFocused = false
    } else {
      // Stay open and focused for the next entry.
      addFieldFocused = true
    }
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
