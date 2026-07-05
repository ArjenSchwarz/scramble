import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

/// Single row in the per-phase task list. Composes a checkbox, the task name,
/// and an assignee avatar. Swipe-trailing and `contextMenu` mirror the Edit /
/// Delete affordances per Req 7.1.
struct TaskRow: View {
  let task: TripTask
  let phaseColour: Color
  let onToggleComplete: () -> Void
  let onEdit: () -> Void
  let onDelete: () -> Void

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let variant = theme.variant(for: colorScheme)

    HStack(alignment: .top, spacing: 12) {
      checkbox

      Text(task.name)
        .font(.body)
        .strikethrough(task.isCompleted)
        .foregroundStyle(variant.textPrimary)
        // minHeight: 44 centres a single-line name with the checkbox's 44pt box
        // (both top-align in the HStack); taller names grow past it and wrap.
        // Mirrors PackingItemRow's name column (T-1619); unconditional here since
        // the WhyDisclosure that once gated it is gone.
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

      if let snapshot = Self.assigneeSnapshot(for: task) {
        PersonAvatar(name: snapshot.name, colorKey: snapshot.colourID, size: .compact)
      }
    }
    .padding(.vertical, 8)
    .frame(minHeight: 44)
    .contentShape(Rectangle())
    .opacity(rowOpacity)
    .animation(.scrambleStandard, value: task.isCompleted)
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button(role: .destructive) {
        onDelete()
      } label: {
        Label("Delete", systemImage: "trash")
      }
      Button {
        onEdit()
      } label: {
        Label("Edit", systemImage: "pencil")
      }
    }
    .contextMenu {
      Button {
        onEdit()
      } label: {
        Label("Edit", systemImage: "pencil")
      }
      Button(role: .destructive) {
        onDelete()
      } label: {
        Label("Delete", systemImage: "trash")
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Self.accessibilityLabel(for: task))
    .accessibilityActions {
      Button("Edit") { onEdit() }
      Button("Delete") { onDelete() }
    }
    #if DEBUG
      .accessibilityIdentifier("tripDetail.taskRow.\(task.name)")
    #endif
  }

  // MARK: - Subviews

  private var checkbox: some View {
    Button {
      #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
      #endif
      withAnimation(.scrambleStandard) {
        onToggleComplete()
      }
    } label: {
      ZStack {
        if task.isCompleted {
          Circle()
            .fill(theme.variant(for: colorScheme).checkColour)
            .frame(width: 24, height: 24)
          Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
        } else {
          Circle()
            .strokeBorder(phaseColour, lineWidth: 2)
            .frame(width: 24, height: 24)
        }
      }
      .frame(width: 44, height: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Mark complete")
  }

  /// Phase 5.1 — looks up the assignee's `TripPersonSnapshot` instead of
  /// traversing the V2-era `Trip.participants → Person` relationship,
  /// which spans containers under the Phase 5.1 dual-container split and
  /// is forbidden by constraint C3. The snapshot carries the same name +
  /// colour the avatar needs and lives in `tripsLocal` alongside the
  /// trip and task. Reused by `TaskForm`'s assignee picker.
  static func assigneeSnapshot(for task: TripTask) -> TripPersonSnapshot? {
    guard let id = task.assigneePersonID else { return nil }
    return task.trip?.participantSnapshots?.first { $0.personID == id }
  }

  /// Combines the "completed" dim (UI doc §"Tasks") with the "rule no longer
  /// matches" ghosting into a single opacity. Chained `.opacity()` modifiers
  /// compose multiplicatively, so the previous `.opacity(0.5).opacity(0.45)`
  /// pair rendered the combined state at `0.225` — far dimmer than either
  /// single state intends. Take the dimmer of the two so the row matches the
  /// stronger signal; strikethrough text already distinguishes completed.
  private var rowOpacity: Double {
    let completedFactor = task.isCompleted ? 0.5 : 1.0
    let matchFactor = (task.currentlyMatchesRules || task.pinnedByUser) ? 1.0 : 0.45
    return min(completedFactor, matchFactor)
  }

  // MARK: - Accessibility (Phase 6 Req 9.2)

  /// Combined accessibility label: task name, completion state, optional
  /// assignee, phase. Read once per body re-evaluation; safe to call
  /// off-context (uses only stored model properties).
  static func accessibilityLabel(for task: TripTask) -> String {
    var parts: [String] = [task.name]
    parts.append(task.isCompleted ? "completed" : "not completed")
    if let snapshot = assigneeSnapshot(for: task) {
      parts.append("assigned to \(snapshot.name)")
    }
    parts.append("phase \(task.phase.displayName)")
    return parts.joined(separator: ", ")
  }
}
