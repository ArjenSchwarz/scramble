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

    var systemImage: String {
      switch self {
      case .packing: "shippingbox"
      case .tasks: "checklist"
      }
    }

    var placeholderText: String {
      switch self {
      case .packing:
        return """
          Master packing items arrive in a later phase. You'll define reusable items here \
          that automatically populate trips based on attribute rules.
          """
      case .tasks:
        return """
          Master tasks arrive in a later phase. You'll define reusable tasks here that \
          automatically populate trips based on attribute rules.
          """
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

        ContentUnavailableView(
          segment.title,
          systemImage: segment.systemImage,
          description: Text(segment.placeholderText)
        )
        .frame(maxHeight: .infinity)
      }
      .navigationTitle("Master Lists")
    }
  }
}
