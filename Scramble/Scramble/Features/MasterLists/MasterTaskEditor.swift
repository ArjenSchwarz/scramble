import SwiftData
import SwiftUI

/// Create / edit a `MasterTaskItem`. The editor owns the mutate → save → run-engine
/// sequence per design Error Handling table; `MasterPersistence` only mutates.
@MainActor struct MasterTaskEditor: View {
  enum Mode: Equatable {
    case create
    case edit(MasterTaskItem)
  }

  let mode: Mode

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @State private var draft: MasterTaskDraft
  @State private var selections: AttributeSelections
  @State private var isAdvancedConditions: Bool
  @State private var errors: [MasterTaskDraft.Field: String] = [:]
  @State private var toastMessage: String?
  @State private var showDeleteConfirmation = false

  init(mode: Mode) {
    self.mode = mode
    switch mode {
    case .create:
      let initial = MasterTaskDraft.newDraft()
      _draft = State(initialValue: initial)
      _selections = State(initialValue: .empty)
      _isAdvancedConditions = State(initialValue: false)
    case .edit(let item):
      let initial = MasterTaskDraft(from: item)
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
        phaseSection
        conditionsSection
        if case .edit = mode {
          deleteSection
        }
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
        "Delete this master task?",
        isPresented: $showDeleteConfirmation,
        titleVisibility: .visible
      ) {
        Button("Delete", role: .destructive) { performDelete() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Trip-level tasks referencing this item keep their snapshot.")
      }
      .transientToast(message: $toastMessage)
    }
  }

  // MARK: - Sections

  private var nameSection: some View {
    Section("Name") {
      TextField("Task name", text: $draft.name)
        .textInputAutocapitalization(.sentences)
      if let message = errors[.name] {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.red)
      }
    }
  }

  private var phaseSection: some View {
    Section("Phase") {
      Picker("Phase", selection: $draft.phase) {
        ForEach(Phase.allCases, id: \.self) { phase in
          Text(phase.displayName).tag(phase)
        }
      }
      .pickerStyle(.menu)
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
        Label("Delete master task", systemImage: "trash")
      }
    }
  }

  private var navigationTitle: String {
    switch mode {
    case .create: "New Master Task"
    case .edit: "Edit Master Task"
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
      MasterPersistence.createTask(from: draft, in: modelContext)
    case .edit(let item):
      MasterPersistence.applyTask(draft, to: item, in: modelContext)
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
    MasterPersistence.deleteTask(item, in: modelContext)
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
    let runner = RulesEngineRunner(context: modelContext)
    do {
      _ = try runner.runForAllNonPastTrips()
      dismiss()
    } catch {
      toastMessage = "Saved. Some trips couldn't be updated — they'll sync on next launch."
    }
  }
}
