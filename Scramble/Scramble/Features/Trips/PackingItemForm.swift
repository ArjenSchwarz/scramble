import SwiftData
import SwiftUI
import os

/// Sheet presentation identity for `PackingItemForm`. `.add` carries the
/// active person and trip; `.edit` carries the existing `TripPackingItem`.
/// Form-internal errors. Currently surfaces only the
/// `missingPersonSnapshot` case (defensive guard against an add against
/// a Person who isn't on the trip's roster); the form's catch path
/// renders an inline error like any other save failure.
enum PackingItemFormError: Error {
  case missingPersonSnapshot
}

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
  @Environment(\.localWriteHook) private var hook

  @State private var name: String = ""
  @State private var note: String = ""
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
          TextField("Note (optional)", text: $note, axis: .vertical)
            .lineLimit(1...4)
            .onChange(of: note) { _, new in
              // Live 500-grapheme cap (Req 4.4); trimming to nil happens at
              // save via PackingSubItems.sanitizedNote.
              let capped = Self.cappedNote(new)
              if capped != new { note = capped }
            }
            #if DEBUG
              .accessibilityIdentifier("packingItemForm.noteField")
            #endif
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
      note = ""
    case .edit(let item):
      name = item.name
      note = item.note ?? ""
    }
    inlineError = nil
  }

  // MARK: - Save

  private func attemptSave() {
    do {
      switch mode {
      case .add(let person, let trip):
        _ = try Self.performAdd(
          name: name, note: note, person: person, trip: trip,
          context: modelContext, hook: hook
        )
      case .edit(let item):
        try Self.performEdit(
          item: item, name: name, note: note, context: modelContext, hook: hook
        )
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

  /// Live length cap for the note field (Req 4.4) — delegates to the single
  /// `PackingSubItems.cappedNote` so the form and the inline editor share one
  /// cap. Trimming to `nil` for an empty note happens at save via
  /// `PackingSubItems.sanitizedNote`.
  static func cappedNote(_ input: String) -> String {
    PackingSubItems.cappedNote(input)
  }

  /// Inserts a manual `TripPackingItem` with the documented field values
  /// (Req 5.3). Phase 5.1: writes the V3 `personSnapshotID` value
  /// reference (looked up against `trip.participantSnapshots` by
  /// `person.id`) instead of the V2 `person → Person` relationship that would span
  /// containers under the dual-container split. Throws on
  /// `modelContext.save()` failure; on throw the inserted instance is
  /// removed from the context so the caller's retry does not
  /// double-insert.
  @MainActor
  @discardableResult
  static func performAdd(
    name: String,
    note: String = "",
    person: Person,
    trip: Trip,
    context: ModelContext,
    hook: LocalWriteHook
  ) throws -> TripPackingItem {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      let snapshot = (trip.participantSnapshots ?? [])
        .first(where: { $0.personID == person.id })
    else {
      // Defensive — the picker shouldn't surface a Person who isn't on
      // the trip's roster, but if the participantSnapshots list is
      // mid-mutation (e.g. roster removal racing the form), creating
      // an ownerless TripPackingItem would render incorrectly on every
      // device. Match `Apply.swift insertAddedPacking`: log info and
      // throw so the caller surfaces its inline-error toast instead of
      // saving silently.
      modelLogger.info(
        "[PackingItemForm.performAdd] no roster snapshot for personID=\(person.id, privacy: .public); skipping add"
      )
      throw PackingItemFormError.missingPersonSnapshot
    }
    let item = TripPackingItem(
      trip: trip,
      masterItemID: nil,
      name: trimmed,
      state: .unpacked,
      source: .manual,
      currentlyMatchesRules: true,
      pinnedByUser: false,
      personSnapshot: snapshot,
      note: PackingSubItems.sanitizedNote(note)
    )
    context.insert(item)
    do {
      try hook.commit(context)
    } catch {
      context.delete(item)
      throw error
    }
    return item
  }

  /// Renames an existing `TripPackingItem` and sets its note from `note`
  /// (`PackingSubItems.sanitizedNote` ⇒ `nil` when empty, Req 4.3). On save
  /// failure the catch path calls `context.rollback()` so the `@Model`
  /// instance reverts to its pre-edit values (SwiftData does not auto-rollback
  /// in-memory edits).
  @MainActor
  static func performEdit(
    item: TripPackingItem,
    name: String,
    note: String = "",
    context: ModelContext,
    hook: LocalWriteHook
  ) throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    item.name = trimmed
    item.note = PackingSubItems.sanitizedNote(note)
    do {
      try hook.commit(context)
    } catch {
      context.rollback()
      throw error
    }
  }
}
