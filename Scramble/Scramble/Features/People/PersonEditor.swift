import SwiftData
import SwiftUI

/// Inline person create/edit sheet used by `TripEditorView`.
///
/// On save the editor inserts a new `Person` into the model context and writes the
/// created person to `newlyCreated`; the parent reads that binding to attach the
/// person to the draft's `participantIDs`. Duplicate colour selection is permitted
/// (AC 9.4): the editor shows a non-blocking advisory naming the conflicting person.
@MainActor struct PersonEditor: View {
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  @Query private var existingPeople: [Person]

  @Binding var newlyCreated: Person?

  @State private var name: String = ""
  @State private var selectedKey: String = ""

  var body: some View {
    NavigationStack {
      Form {
        Section("Name") {
          TextField("Person name", text: $name)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
        }

        Section("Colour") {
          paletteGrid
          if let advisory = duplicateAdvisory {
            Text(advisory)
              .font(.footnote)
              .foregroundStyle(variant.warnColour)
          }
        }
      }
      .navigationTitle("New Person")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }
            .disabled(trimmedName.isEmpty)
        }
      }
      .onAppear(perform: assignDefaultColour)
    }
  }

  private var variant: ThemeVariant { theme.variant(for: colorScheme) }

  private var palette: PersonPalette { theme.personPalette }

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var takenColourKeys: Set<String> {
    Set(existingPeople.map(\.colorKey))
  }

  private var duplicateAdvisory: String? {
    guard !selectedKey.isEmpty else { return nil }
    let owners = existingPeople.filter { $0.colorKey == selectedKey }
    guard !owners.isEmpty else { return nil }
    let names = owners.map { $0.name.isEmpty ? "Unnamed" : $0.name }.joined(separator: ", ")
    return "Also used by \(names)"
  }

  private var paletteGrid: some View {
    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    return LazyVGrid(columns: columns, spacing: 12) {
      ForEach(palette.entries) { entry in
        paletteSwatch(entry)
      }
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private func paletteSwatch(_ entry: PaletteEntry) -> some View {
    let color = colorScheme == .light ? entry.light : entry.dark
    let isSelected = entry.key == selectedKey
    Button {
      selectedKey = entry.key
    } label: {
      Circle()
        .fill(color.opacity(0.20))
        .overlay(
          Circle().strokeBorder(color, lineWidth: isSelected ? 3 : 1)
        )
        .overlay(
          Image(systemName: "checkmark")
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(color)
            .opacity(isSelected ? 1 : 0)
        )
        .frame(width: 40, height: 40)
        .accessibilityLabel(entry.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    .buttonStyle(.plain)
  }

  private func assignDefaultColour() {
    guard selectedKey.isEmpty else { return }
    selectedKey = palette.nextUnusedKey(among: takenColourKeys).key
  }

  private func save() {
    let person = Person(name: trimmedName, colorKey: selectedKey)
    context.insert(person)
    do {
      try context.save()
      newlyCreated = person
      dismiss()
    } catch {
      // Surface the failure but don't crash the editor; the user can retry or cancel.
      context.rollback()
    }
  }
}
