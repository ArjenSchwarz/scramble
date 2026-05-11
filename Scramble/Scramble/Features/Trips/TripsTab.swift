import SwiftUI

@MainActor struct TripsTab: View {
  var body: some View {
    NavigationStack {
      ContentUnavailableView(
        "Trips",
        systemImage: "suitcase",
        description: Text("Trip list and editor arrive in a later task.")
      )
      .navigationTitle("Trips")
    }
  }
}
