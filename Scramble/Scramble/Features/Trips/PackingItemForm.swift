import SwiftData
import SwiftUI
import os

/// Sheet presentation identity for `PackingItemForm`. `.add` carries the
/// active person and trip; `.edit` carries the existing `TripPackingItem`.
enum PackingItemFormPresentation: Identifiable {
  case add(person: Person, trip: Trip)
  case edit(item: TripPackingItem)

  var id: String {
    switch self {
    case .add(let person, let trip): "add-\(person.id.uuidString)-\(trip.id.uuidString)"
    case .edit(let item): "edit-\(item.id.uuidString)"
    }
  }
}

/// Sheet form for creating manual `TripPackingItem`s and renaming existing
/// ones. The form intentionally has no assignee picker (the active person is
/// implied by the parent sheet) and no conditions field (manual items are
/// always active; rule items have conditions on the master).
///
/// Save semantics differ from `TaskForm`: on `modelContext.save()` failure,
/// the form remains open with the user's input intact and an inline error
/// string. For `.edit`, the catch path calls `modelContext.rollback()` so the
/// `@Model` instance reverts to its pre-edit name.
struct PackingItemForm: View {
  let mode: PackingItemFormPresentation
  let onSave: () -> Void
  let onCancel: () -> Void

  @Environment(\.modelContext) private var modelContext

  @State private var name: String = ""
  @State private var inlineError: String?

  private static let nameLimit = 200

  var body: some View {
    NavigationStack {
      Form {
        Section("Item") {
          TextField("Item name", text: $name)
            .onChange(of: name) { _, new in
              let capped = Self.cappedName(new)
              if capped != new { name = capped }
            }
        }

        if let inlineError {
          Section {
            Text(inlineError)
              .font(.footnote)
              .foregroundStyle(.red)
          }
        }
      }
      .navigationTitle(navigationTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") {
            onCancel()
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Save") {
            attemptSave()
          }
          .disabled(!Self.isSubmitEnabled(name))
        }
      }
      .onAppear(perform: prefill)
    }
  }

  // MARK: - State

  private var navigationTitle: String {
    switch mode {
    case .add: "Add Item"
    case .edit: "Edit Item"
    }
  }

  private func prefill() {
    switch mode {
    case .add:
      name = ""
    case .edit(let item):
      name = item.name
    }
    inlineError = nil
  }

  // MARK: - Save

  private func attemptSave() {
    do {
      switch mode {
      case .add(let person, let trip):
        _ = try Self.performAdd(name: name, person: person, trip: trip, context: modelContext)
      case .edit(let item):
        try Self.performEdit(item: item, name: name, context: modelContext)
      }
      onSave()
    } catch {
      modelLogger.error(
        "[PackingSheet.save-failed]: \(error.localizedDescription, privacy: .public)"
      )
      inlineError = "Couldn't save — try again."
    }
  }
}

// MARK: - Pure helpers (testable)

extension PackingItemForm {

  /// Returns true when the trimmed name has at least one non-whitespace
  /// character. The Save button binds to this.
  static func isSubmitEnabled(_ name: String) -> Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Truncates input to the 200-grapheme limit (Req 5.5). `String.prefix`
  /// counts graphemes so multi-scalar emoji survive intact at the boundary.
  static func cappedName(_ input: String) -> String {
    String(input.prefix(nameLimit))
  }

  /// Inserts a manual `TripPackingItem` with the documented field values
  /// (Req 5.3). Throws on `modelContext.save()` failure; on throw the
  /// inserted instance is removed from the context so the caller's retry does
  /// not double-insert.
  @MainActor
  @discardableResult
  static func performAdd(
    name: String,
    person: Person,
    trip: Trip,
    context: ModelContext
  ) throws -> TripPackingItem {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let item = TripPackingItem(
      trip: trip,
      person: person,
      masterItemID: nil,
      name: trimmed,
      state: .unpacked,
      source: .manual,
      currentlyMatchesRules: true,
      pinnedByUser: false
    )
    context.insert(item)
    do {
      try context.save()
    } catch {
      context.delete(item)
      throw error
    }
    return item
  }

  /// Renames an existing `TripPackingItem`. On save failure the catch path
  /// calls `context.rollback()` so the `@Model` instance reverts to its
  /// pre-edit name (SwiftData does not auto-rollback in-memory edits).
  @MainActor
  static func performEdit(
    item: TripPackingItem,
    name: String,
    context: ModelContext
  ) throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    item.name = trimmed
    do {
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
  }
}
