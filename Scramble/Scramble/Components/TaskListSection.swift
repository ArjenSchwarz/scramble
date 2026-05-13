import SwiftData
import SwiftUI

/// Per-phase task content rendered inside an expanded `PhaseRow`. Filters
/// `trip.tasks` to the phase, drops soft-deleted rule rows
/// (`userDeletedOnThisTrip == true`), sorts via `TaskListHelpers.sorted`, and
/// appends a dashed "Add task" affordance.
///
/// The single source of disclosure state for the timeline is the parent's
/// `openDisclosureTaskID` binding; this section forwards it to each
/// `TaskRow` and clears it when a different row's long-press fires.
struct TaskListSection: View {
  let trip: Trip
  let phase: Phase
  let phaseColour: Color
  @Binding var openDisclosureTaskID: UUID?
  let onAdd: () -> Void
  let onEdit: (TripTask) -> Void

  @Environment(\.modelContext) private var modelContext

  var body: some View {
    let visibleTasks = TaskListHelpers.sorted(
      (trip.tasks ?? []).filter { $0.phase == phase && !$0.userDeletedOnThisTrip }
    )

    VStack(alignment: .leading, spacing: 4) {
      ForEach(visibleTasks) { task in
        TaskRow(
          task: task,
          phaseColour: phaseColour,
          isDisclosureOpen: openDisclosureTaskID == task.id,
          onToggleComplete: { toggleComplete(task) },
          onLongPress: { toggleDisclosure(task) },
          onEdit: { onEdit(task) },
          onDelete: { delete(task) }
        )
      }

      DashedAddButton(title: "Add task", accent: phaseColour, action: onAdd)
        #if DEBUG
          .accessibilityIdentifier("tripDetail.addTaskButton.\(phase.rawValue)")
        #endif
    }
    .padding(.top, 8)
    .background {
      // Disclosure-dismiss tap target. Lives on a background layer (behind
      // task rows and the add button) and is only mounted when there is an
      // open disclosure, so it can't intercept taps destined for the
      // checkbox or `DashedAddButton` when no disclosure is open.
      if openDisclosureTaskID != nil {
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture { openDisclosureTaskID = nil }
      }
    }
    #if DEBUG
      .accessibilityIdentifier("tripDetail.taskListSection.\(phase.rawValue)")
    #endif
  }

  // MARK: - Mutations

  private func toggleComplete(_ task: TripTask) {
    task.isCompleted.toggle()
    do {
      try modelContext.save()
    } catch {
      modelLogger.error(
        "TaskListSection.toggleComplete save failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func toggleDisclosure(_ task: TripTask) {
    openDisclosureTaskID = (openDisclosureTaskID == task.id) ? nil : task.id
  }

  private func delete(_ task: TripTask) {
    if task.source == .manual {
      modelContext.delete(task)
    } else {
      task.userDeletedOnThisTrip = true
    }
    do {
      try modelContext.save()
    } catch {
      modelLogger.error(
        "TaskListSection.delete save failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }
}
