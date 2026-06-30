import SwiftData
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

/// Single row in the per-phase task list. Composes a checkbox, the task name
/// (with the optional inline `WhyDisclosureView`), and an assignee avatar.
/// Long-press on the body region toggles the disclosure; swipe-trailing and
/// `contextMenu` mirror the Edit / Delete affordances per Req 7.1.
///
/// State ownership: `isDisclosureOpen` is bound by the parent; the resolved
/// `WhyDisclosure.Reason` is cached locally and recomputed only when the
/// disclosure opens or relevant inputs (`task.trip?.attributesData`,
/// `task.currentlyMatchesRules`, `task.name`) change.
struct TaskRow: View {
  let task: TripTask
  let phaseColour: Color
  let isDisclosureOpen: Bool
  let onToggleComplete: () -> Void
  let onLongPress: () -> Void
  let onEdit: () -> Void
  let onDelete: () -> Void

  @Environment(\.modelContext) private var modelContext
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.isParticipantViewingSharedTrip) private var isParticipantViewingSharedTrip
  @State private var resolvedReason: WhyDisclosure.Reason?

  var body: some View {
    let variant = theme.variant(for: colorScheme)

    HStack(alignment: .top, spacing: 12) {
      checkbox

      VStack(alignment: .leading, spacing: 6) {
        Text(task.name)
          .font(.body)
          .strikethrough(task.isCompleted)
          .foregroundStyle(variant.textPrimary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
          .onLongPressGesture(minimumDuration: 0.4) {
            #if canImport(UIKit)
              UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            onLongPress()
          }
          // keep separate from the frame above: merging would grow the long-press hit area to 44pt
          .frame(minHeight: isDisclosureOpen ? nil : 44)

        if isDisclosureOpen, let reason = resolvedReason {
          WhyDisclosureView(reason: reason, style: .tasks(phaseColour: phaseColour))
            #if DEBUG
              .accessibilityIdentifier("tripDetail.whyDisclosure.\(task.name)")
            #endif
        }
      }

      if let snapshot = Self.assigneeSnapshot(for: task) {
        PersonAvatar(name: snapshot.name, colorKey: snapshot.colourID, size: .compact)
      }
    }
    .padding(.vertical, 8)
    .frame(minHeight: 44)
    .contentShape(Rectangle())
    .opacity(rowOpacity)
    .animation(.scrambleStandard, value: task.isCompleted)
    // isDisclosureOpen isn't covered by the task.isCompleted monitor above
    .animation(.scrambleStandard, value: isDisclosureOpen)
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
      // Phase 6 Req 9.5 — "Why is this here?" custom action is
      // exposed only when the underlying item has a rule
      // justification (manual one-offs and items whose master row
      // was deleted under certain conditions return nil from
      // WhyResolver and therefore omit the action).
      if Self.hasWhyJustification(
        task: task,
        context: modelContext,
        hideOnUnresolvedMaster: isParticipantViewingSharedTrip
      ) {
        Button("Why is this here?") { onLongPress() }
      }
      Button("Edit") { onEdit() }
      Button("Delete") { onDelete() }
    }
    #if DEBUG
      .accessibilityIdentifier("tripDetail.taskRow.\(task.name)")
    #endif
    .onChange(of: isDisclosureOpen) { _, open in
      if open {
        resolvedReason = WhyResolver.reason(
          for: task,
          context: modelContext,
          hideOnUnresolvedMaster: isParticipantViewingSharedTrip
        )
      } else {
        resolvedReason = nil
      }
    }
    .onChange(of: task.trip?.attributesData) { _, _ in
      if isDisclosureOpen {
        resolvedReason = WhyResolver.reason(
          for: task,
          context: modelContext,
          hideOnUnresolvedMaster: isParticipantViewingSharedTrip
        )
      }
    }
    .onChange(of: task.currentlyMatchesRules) { _, _ in
      if isDisclosureOpen {
        resolvedReason = WhyResolver.reason(
          for: task,
          context: modelContext,
          hideOnUnresolvedMaster: isParticipantViewingSharedTrip
        )
      }
    }
    .onChange(of: task.name) { _, _ in
      if isDisclosureOpen {
        resolvedReason = WhyResolver.reason(
          for: task,
          context: modelContext,
          hideOnUnresolvedMaster: isParticipantViewingSharedTrip
        )
      }
    }
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

  // MARK: - Accessibility (Phase 6 Req 9.2, 9.5)

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

  /// Phase 6 Req 9.5 — whether the "Why is this here?" custom action
  /// should be exposed. Mirrors the long-press disclosure's gate:
  /// `WhyResolver.reason(...)` returning non-nil means there is rule
  /// justification to surface.
  static func hasWhyJustification(
    task: TripTask,
    context: ModelContext,
    hideOnUnresolvedMaster: Bool
  ) -> Bool {
    WhyResolver.reason(
      for: task,
      context: context,
      hideOnUnresolvedMaster: hideOnUnresolvedMaster
    ) != nil
  }
}
