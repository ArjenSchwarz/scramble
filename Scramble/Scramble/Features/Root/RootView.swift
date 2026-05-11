import SwiftUI

@MainActor struct RootView: View {
  enum Tab: Hashable { case trips, masterLists }

  @State private var tab: Tab = .trips

  var body: some View {
    TabView(selection: $tab) {
      TripsTab()
        .tabItem {
          Label("Trips", systemImage: "suitcase")
        }
        .tag(Tab.trips)

      MasterListsTab()
        .tabItem {
          Label("Master Lists", systemImage: "list.bullet.rectangle")
        }
        .tag(Tab.masterLists)
    }
  }
}
