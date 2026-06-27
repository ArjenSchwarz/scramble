import SwiftData
import SwiftUI

/// Create / edit a `MasterPackingItem`. Mirrors `MasterTaskEditor` with a Person
/// picker in place of Phase. Save validates per AC 2.5 (name + person).
@MainActor struct MasterPackingEditor: View {
  enum Mode: Equatable {
    case create
    case edit(MasterPackingItem)
  }

  let mode: Mode

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(\.tripsLocalContainer) private var tripsLocalContainer
  @Environment(\.localWriteHook) private var hook

  @Query(sort: \Person.name) private var allPeople: [Person]

  @State private var draft: MasterPackingDraft
  @State private var selections: AttributeSelections
  @State private var isAdvancedConditions: Bool
  @State private var errors: [MasterPackingDraft.Field: String] = [:]
  @State private var toastMessage: String?
  @State private var showDeleteConfirmation = false
  /// Category suggestion vocabulary, gathered once when the editor appears
  /// (never per keystroke). Drawn from both containers via
  /// `PackingCategory.distinctCategories`. (Req 2.2)
  @State private var categorySuggestions: [String] = []

  init(mode: Mode) {
    self.mode = mode
    switch mode {
    case .create:
      let initial = MasterPackingDraft.newDraft()
      _draft = State(initialValue: initial)
      _selections = State(initialValue: .empty)
      _isAdvancedConditions = State(initialValue: false)
    case .edit(let item):
      let initial = MasterPackingDraft(from: item)
      _draft = State(initialValue: initial)
      if let s = AttributeSelections.from(initial.conditions) {
        _selections = State(initialValue: s)
        _isAdvancedConditions = State(initialValue: false)
      } else {
        _selections = State(initialValue: .empty)
        _isAdvancedConditions = State(initialValue: true)
      }
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        nameSection
        personSection
        categorySection
        conditionsSection
        if case .edit = mode {
          deleteSection
        }
      }
      .onAppear {
        categorySuggestions = PackingCategory.distinctCategories(
          globals: modelContext,
          tripsLocal: tripsLocalContainer.mainContext
        )
      }
      .navigationTitle(navigationTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { attemptSave() }
        }
      }
      .confirmationDialog(
        "Delete this master packing item?",
        isPresented: $showDeleteConfirmation,
        titleVisibility: .visible
      ) {
        Button("Delete", role: .destructive) { performDelete() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Trip-level packing items referencing this item keep their snapshot.")
      }
      .transientToast(message: $toastMessage)
    }
  }

  // MARK: - Sections

  private var nameSection: some View {
    Section("Name") {
      TextField("Item name", text: $draft.name)
        .textInputAutocapitalization(.sentences)
      if let message = errors[.name] {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.red)
      }
    }
  }

  private var personSection: some View {
    Section("Person") {
      Picker("Person", selection: $draft.personID) {
        Text("Choose…").tag(UUID?.none)
        ForEach(allPeople) { person in
          Text(person.name.isEmpty ? "Unnamed" : person.name).tag(Optional(person.id))
        }
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier("masterPacking.personPicker")
      if let message = errors[.person] {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.red)
      }
    }
  }

  private var categorySection: some View {
    Section("Category") {
      TextField("Category (optional)", text: categoryBinding)
        .textInputAutocapitalization(.words)
        .accessibilityIdentifier("masterPacking.categoryField")
      if !visibleSuggestions.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(visibleSuggestions, id: \.self) { suggestion in
              // Tapping stores the suggestion's canonical spelling verbatim so a
              // case/whitespace variant is never recreated (Req 2.4).
              Button(suggestion) { draft.category = suggestion }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("masterPacking.categorySuggestion.\(suggestion)")
            }
          }
          .padding(.vertical, 2)
        }
      }
    }
  }

  /// Bridges the optional `draft.category` to the `TextField`'s `String` binding.
  /// Keeps the raw, in-progress text in the draft; normalization happens at the
  /// persistence boundary (`MasterPersistence` → `PackingCategory.storageValue`).
  private var categoryBinding: Binding<String> {
    Binding(
      get: { draft.category ?? "" },
      set: { draft.category = $0 }
    )
  }

  /// Suggestions filtered against what's currently typed: an in-memory pass over
  /// the once-gathered `categorySuggestions` (no per-keystroke fetch). Matches by
  /// normalized key so case/whitespace variants present as a single suggestion
  /// (Req 2.3), and hides the suggestion that exactly equals the current input.
  private var visibleSuggestions: [String] {
    guard let typed = PackingCategory.normalizedKey(draft.category) else {
      return categorySuggestions
    }
    return categorySuggestions.filter { suggestion in
      guard let key = PackingCategory.normalizedKey(suggestion) else { return false }
      return key != typed && key.contains(typed)
    }
  }

  @ViewBuilder
  private var conditionsSection: some View {
    if isAdvancedConditions {
      AdvancedConditionView(conditions: draft.conditions) {
        draft.conditions = .always
        selections = .empty
        isAdvancedConditions = false
      }
    } else {
      ConditionsEditor(selections: $selections)
    }
  }

  private var deleteSection: some View {
    Section {
      Button(role: .destructive) {
        showDeleteConfirmation = true
      } label: {
        Label("Delete master packing item", systemImage: "trash")
      }
    }
  }

  private var navigationTitle: String {
    switch mode {
    case .create: "New Master Packing Item"
    case .edit: "Edit Master Packing Item"
    }
  }

  // MARK: - Save

  private func attemptSave() {
    if !isAdvancedConditions {
      draft.conditions = selections.toConditions()
    }
    let newErrors = draft.validate()
    errors = newErrors
    guard newErrors.isEmpty else { return }

    switch mode {
    case .create:
      MasterPersistence.createPacking(from: draft, in: modelContext)
    case .edit(let item):
      MasterPersistence.applyPacking(draft, to: item, in: modelContext)
    }

    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
      toastMessage = "Save failed — try again."
      return
    }

    runEngineAndDismiss()
  }

  private func performDelete() {
    guard case .edit(let item) = mode else { return }
    MasterPersistence.deletePacking(item, in: modelContext)
    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
      toastMessage = "Delete failed — try again."
      return
    }
    runEngineAndDismiss()
  }

  private func runEngineAndDismiss() {
    // Phase 5.1: trips live in tripsLocal; masters live in globals
    // (the editor's @Environment(\.modelContext)).
    let runner = RulesEngineRunner(
      context: tripsLocalContainer.mainContext,
      mastersContext: modelContext,
      hook: hook
    )
    do {
      _ = try runner.runForAllNonPastTrips()
      dismiss()
    } catch {
      toastMessage = "Saved. Some trips couldn't be updated — they'll sync on next launch."
    }
  }
}
