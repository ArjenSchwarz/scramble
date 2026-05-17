import SwiftData
import SwiftUI
import os

@MainActor struct RootView: View {
  enum Tab: Hashable { case trips, masterLists }

  @State private var tab: Tab = .trips
  /// `true` once the app has been observed in `.background`. The
  /// scenePhase trigger fires on the next transition into `.active`, then
  /// resets. This is more robust than comparing `previousScenePhase` to
  /// `.background` directly — iOS delivers `.background → .inactive → .active`
  /// with `.inactive` in between, so a direct `.background → .active` edge is
  /// never observed by `onChange`.
  @State private var hasBeenBackgrounded: Bool = false
  @Environment(\.scenePhase) private var scenePhase
  /// Phase 5.1 — scene-phase rules-engine warm-pass runs against
  /// `tripsLocal`, the container that holds the trip-domain rows the
  /// engine reads and writes. `RootView` itself does not bind a container,
  /// so each tab subtree re-roots to the appropriate one (Trips →
  /// tripsLocal, Master Lists → globals); the warm-pass therefore reaches
  /// into the environment-injected tripsLocal container directly rather
  /// than relying on `@Environment(\.modelContext)`.
  @Environment(\.tripsLocalContainer) private var tripsLocalContainer

  #if DEBUG
    @State private var scenePhaseRunnerCalls: Int = 0
  #endif

  var body: some View {
    TabView(selection: $tab) {
      TripsTab()
        .modelContainer(tripsLocalContainer)
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
      if newPhase == .background {
        hasBeenBackgrounded = true
        return
      }
      guard newPhase == .active, hasBeenBackgrounded else { return }
      hasBeenBackgrounded = false
      do {
        _ = try RulesEngineRunner(context: tripsLocalContainer.mainContext)
          .runForAllNonPastTrips()
      } catch {
        modelLogger.error(
          "[RulesEngine.scenePhase-failed] error=\(String(describing: error), privacy: .public)"
        )
      }
      #if DEBUG
        scenePhaseRunnerCalls += 1
      #endif
    }
    #if DEBUG
      .background {
        Color.clear
        .frame(width: 1, height: 1)
        .accessibilityElement()
        .accessibilityIdentifier(Self.modelStoreModeIdentifier)
      }
      .background {
        // Counter exposed for RootViewScenePhaseTests. Starts at 0 — the
        // cold-launch carve-out in `.onChange(of: scenePhase)` guarantees the
        // initial nil → .inactive → .active sequence does NOT increment it.
        Color.clear
        .frame(width: 1, height: 1)
        .accessibilityElement()
        .accessibilityIdentifier(
          "\(DebugAccessibilityID.scenePhaseRunnerCallsPrefix)\(scenePhaseRunnerCalls)"
        )
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
