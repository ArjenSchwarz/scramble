import SwiftData
import SwiftUI

/// AC 1.1 — list every `MasterTaskItem` grouped by `Phase` in canonical order,
/// empty groups omitted. AC 1.2 — "+ Add task" affordance opens the editor.
@MainActor struct MasterTasksList: View {
  @Query(sort: \MasterTaskItem.name) private var allTasks: [MasterTaskItem]
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  @State private var editTarget: EditTarget?

  enum EditTarget: Identifiable, Hashable {
    case create
    case edit(PersistentIdentifier)

    var id: String {
      switch self {
      case .create: "create"
      case .edit(let id): "edit-\(id.hashValue)"
      }
    }
  }

  var body: some View {
    let variant = theme.variant(for: colorScheme)
    let grouped = Dictionary(grouping: allTasks, by: \.phase)

    List {
      ForEach(Phase.allCases, id: \.self) { phase in
        if let items = grouped[phase], !items.isEmpty {
          Section(phase.displayName) {
            ForEach(items) { item in
              Button {
                editTarget = .edit(item.persistentModelID)
              } label: {
                Text(item.name.isEmpty ? "Unnamed task" : item.name)
                  .foregroundStyle(variant.textPrimary)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
        }
      }

      Section {
        DashedAddButton(title: "Add task", accent: variant.accent) {
          editTarget = .create
        }
      }
    }
    .listStyle(.insetGrouped)
    .sheet(item: $editTarget) { target in
      sheet(for: target)
    }
  }

  @ViewBuilder
  private func sheet(for target: EditTarget) -> some View {
    switch target {
    case .create:
      MasterTaskEditor(mode: .create)
    case .edit(let id):
      if let item = allTasks.first(where: { $0.persistentModelID == id }) {
        MasterTaskEditor(mode: .edit(item))
      }
    }
  }
}
