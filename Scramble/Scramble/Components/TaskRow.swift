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
/// `task.name`) change.
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

        if isDisclosureOpen, let reason = resolvedReason {
          WhyDisclosureView(reason: reason, phaseColour: phaseColour)
            #if DEBUG
              .accessibilityIdentifier("tripDetail.whyDisclosure.\(task.name)")
            #endif
        }
      }

      if let person = resolvedAssignee {
        PersonAvatar(name: person.name, colorKey: person.colorKey, size: .compact)
      }
    }
    .padding(.vertical, 8)
    .frame(minHeight: 44)
    .contentShape(Rectangle())
    .opacity(task.isCompleted ? 0.5 : 1.0)
    .opacity((task.currentlyMatchesRules || task.pinnedByUser) ? 1.0 : 0.45)
    .animation(.easeInOut(duration: 0.2), value: task.isCompleted)
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
    .accessibilityAction(named: Text("Why is this here?")) { onLongPress() }
    .accessibilityAction(named: Text("Edit")) { onEdit() }
    .accessibilityAction(named: Text("Delete")) { onDelete() }
    #if DEBUG
      .accessibilityIdentifier("tripDetail.taskRow.\(task.name)")
    #endif
    .onChange(of: isDisclosureOpen) { _, open in
      if open {
        resolvedReason = WhyResolver.reason(for: task, context: modelContext)
      } else {
        resolvedReason = nil
      }
    }
    .onChange(of: task.trip?.attributesData) { _, _ in
      if isDisclosureOpen {
        resolvedReason = WhyResolver.reason(for: task, context: modelContext)
      }
    }
    .onChange(of: task.name) { _, _ in
      if isDisclosureOpen {
        resolvedReason = WhyResolver.reason(for: task, context: modelContext)
      }
    }
  }

  // MARK: - Subviews

  private var checkbox: some View {
    Button {
      #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
      #endif
      withAnimation(.none) {
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

  private var resolvedAssignee: Person? {
    guard let id = task.assigneePersonID else { return nil }
    guard let participants = task.trip?.participants else { return nil }
    return participants.first { $0.id == id }
  }
}
