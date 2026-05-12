import SwiftUI

@MainActor struct MasterListsTab: View {
  enum Segment: Hashable, CaseIterable {
    case packing
    case tasks

    var title: String {
      switch self {
      case .packing: "Packing Items"
      case .tasks: "Tasks"
      }
    }
  }

  @State private var segment: Segment = .packing

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Picker("Master list segment", selection: $segment) {
          ForEach(Segment.allCases, id: \.self) { segment in
            Text(segment.title).tag(segment)
          }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, 8)

        switch segment {
        case .packing:
          MasterPackingList()
        case .tasks:
          MasterTasksList()
        }
      }
      .navigationTitle("Master Lists")
    }
  }
}
