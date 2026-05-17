import SwiftData
import SwiftUI
import os

/// Sheet presentation identity for `TaskForm`, used by
/// `TripDetailView`'s `.sheet(item:)`. `.add` carries the phase + trip the
/// new task should attach to; `.edit` carries the existing `TripTask`.
enum TaskFormPresentation: Identifiable {
  case add(phase: Phase, trip: Trip)
  case edit(task: TripTask)

  var id: String {
    switch self {
    case .add(let phase, let trip): "add-\(phase.rawValue)-\(trip.id.uuidString)"
    case .edit(let task): "edit-\(task.id.uuidString)"
    }
  }

  fileprivate var trip: Trip? {
    switch self {
    case .add(_, let trip): trip
    case .edit(let task): task.trip
    }
  }
}

/// Sheet form for creating manual trip tasks and editing existing ones. A
/// single component covers both modes — they differ only in initial values
/// and the save mutation. The form deliberately does **not** use `@Query`:
/// concurrent rules-engine runs cannot mutate form state mid-edit
/// (Req 6.7).
struct TaskForm: View {
  let mode: TaskFormPresentation
  let onSave: () -> Void
  let onCancel: () -> Void

  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss

  @State private var name: String = ""
  @State private var assigneePersonID: UUID?

  private static let nameLimit = 200

  var body: some View {
    NavigationStack {
      Form {
        Section("Task") {
          TextField("Task name", text: $name)
            .onChange(of: name) { _, new in
              if new.count > Self.nameLimit {
                name = String(new.prefix(Self.nameLimit))
              }
            }
        }

        Section("Assignee") {
          let snapshots = mode.trip?.participantSnapshots ?? []
          if snapshots.isEmpty {
            Text("No participants yet — add people on the trip details screen")
              .foregroundStyle(.secondary)
          } else {
            Picker("Assignee", selection: $assigneePersonID) {
              Text("None").tag(UUID?.none)
              ForEach(snapshots) { snapshot in
                Text(snapshot.name).tag(Optional(snapshot.personID))
              }
            }
          }
        }
      }
      .navigationTitle(navigationTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") {
            onCancel()
            dismiss()
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Save") {
            save()
          }
          .disabled(trimmedName.isEmpty)
        }
      }
      .onAppear(perform: prefill)
    }
  }

  // MARK: - State

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var navigationTitle: String {
    switch mode {
    case .add: "Add Task"
    case .edit: "Edit Task"
    }
  }

  private func prefill() {
    switch mode {
    case .add:
      name = ""
      assigneePersonID = nil
    case .edit(let task):
      name = task.name
      assigneePersonID = task.assigneePersonID
    }
  }

  // MARK: - Save

  private func save() {
    let trimmed = trimmedName
    guard !trimmed.isEmpty else { return }
    switch mode {
    case .add(let phase, let trip):
      let task = TripTask(
        trip: trip,
        masterItemID: nil,
        name: trimmed,
        phase: phase,
        isCompleted: false,
        source: .manual,
        currentlyMatchesRules: true,
        pinnedByUser: false,
        assigneePersonID: assigneePersonID,
        userDeletedOnThisTrip: false
      )
      modelContext.insert(task)
    case .edit(let task):
      task.name = trimmed
      task.assigneePersonID = assigneePersonID
    }
    // Intentional: the form dismisses even if save throws. Phase 3 has no
    // user-facing error-UI for SwiftData failures (see CLAUDE.md "Out of
    // scope for v1"); the breadcrumb in os_log is the diagnostic. Revisit
    // when error surfacing is in scope.
    do {
      try modelContext.save()
    } catch {
      modelLogger.error(
        "TaskForm.save failed: \(error.localizedDescription, privacy: .public)"
      )
    }
    onSave()
    dismiss()
  }
}
