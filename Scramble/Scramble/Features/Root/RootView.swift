import SwiftData
import SwiftUI

@MainActor struct RootView: View {
  enum Tab: Hashable { case trips, masterLists }

  @State private var tab: Tab = .trips
  @State private var previousScenePhase: ScenePhase?
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.modelContext) private var modelContext

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
    .onChange(of: scenePhase) { _, newPhase in
      defer { previousScenePhase = newPhase }
      guard previousScenePhase == .background, newPhase == .active else { return }
      _ = try? RulesEngineRunner(context: modelContext).runForAllNonPastTrips()
    }
    #if DEBUG
      .background {
        Color.clear
        .frame(width: 1, height: 1)
        .accessibilityElement()
        .accessibilityIdentifier(Self.modelStoreModeIdentifier)
      }
    #endif
  }

  #if DEBUG
    /// Debug-only marker the UI tests use to assert the host app booted with
    /// the in-memory `ModelContainer` (rather than the production CloudKit
    /// container). See `AppLaunchUITests.testLaunchUsesInMemoryContainer`.
    static var modelStoreModeIdentifier: String {
      let probe = EnvironmentProbe.production
      if probe.isUITestHost || probe.isTest || probe.isPreview {
        return DebugAccessibilityID.modelStoreInMemory
      }
      return DebugAccessibilityID.modelStoreCloud
    }
  #endif
}
