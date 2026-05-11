import SwiftUI

@MainActor struct MasterListsTab: View {
  var body: some View {
    NavigationStack {
      ContentUnavailableView(
        "Master Lists",
        systemImage: "list.bullet.rectangle",
        description: Text("Master-list editing arrives in a later phase.")
      )
      .navigationTitle("Master Lists")
    }
  }
}
