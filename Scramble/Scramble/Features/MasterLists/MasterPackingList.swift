import SwiftData
import SwiftUI

/// AC 2.1 — list every `MasterPackingItem` grouped by `Person`, sorted by
/// `Person.name` ascending, people with zero items omitted, per-person count
/// in the header. AC 2.7 — when no `Person` exists, show empty state and hide
/// the "+ Add item" affordance.
@MainActor struct MasterPackingList: View {
  @Query(sort: \MasterPackingItem.name) private var allItems: [MasterPackingItem]
  @Query(sort: \Person.name) private var allPeople: [Person]
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
    if allPeople.isEmpty {
      ContentUnavailableView(
        "No people yet",
        systemImage: "person.crop.circle.badge.plus",
        description: Text(
          "Add a person to a trip first, then return here to define their packing items."
        )
      )
    } else {
      let variant = theme.variant(for: colorScheme)
      let grouped = Dictionary(grouping: allItems) { $0.person?.id }
      let sortedPeople = allPeople.sorted { $0.name < $1.name }

      List {
        ForEach(sortedPeople) { person in
          let items = grouped[person.id] ?? []
          if !items.isEmpty {
            Section {
              ForEach(items) { item in
                Button {
                  editTarget = .edit(item.persistentModelID)
                } label: {
                  Text(item.name.isEmpty ? "Unnamed item" : item.name)
                    .foregroundStyle(variant.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            } header: {
              HStack {
                Text(person.name.isEmpty ? "Unnamed" : person.name)
                Spacer()
                Text("\(items.count)")
                  .foregroundStyle(.secondary)
              }
            }
          }
        }

        Section {
          DashedAddButton(title: "Add item", accent: variant.accent) {
            editTarget = .create
          }
        }
      }
      .listStyle(.insetGrouped)
      .sheet(item: $editTarget) { target in
        sheet(for: target)
      }
    }
  }

  @ViewBuilder
  private func sheet(for target: EditTarget) -> some View {
    switch target {
    case .create:
      MasterPackingEditor(mode: .create)
    case .edit(let id):
      if let item = allItems.first(where: { $0.persistentModelID == id }) {
        MasterPackingEditor(mode: .edit(item))
      }
    }
  }
}
