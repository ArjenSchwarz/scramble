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

  /// Phase 6 — owned here so a notification-tap consumption can push to
  /// the Trips tab's navigation stack regardless of which tab is showing.
  @State private var tripsPath = NavigationPath()
  @Environment(\.activationRouter) private var activationRouter
  /// Phase 5.1 — scene-phase rules-engine warm-pass runs against
  /// `tripsLocal`, the container that holds the trip-domain rows the
  /// engine reads and writes. `RootView` itself does not bind a container,
  /// so each tab subtree re-roots to the appropriate one (Trips →
  /// tripsLocal, Master Lists → globals); the warm-pass therefore reaches
  /// into the environment-injected tripsLocal container directly rather
  /// than relying on `@Environment(\.modelContext)`.
  @Environment(\.tripsLocalContainer) private var tripsLocalContainer
  @Environment(\.globalsContainer) private var globalsContainer
  @Environment(\.localWriteHook) private var hook

  #if DEBUG
    @State private var scenePhaseRunnerCalls: Int = 0
  #endif

  var body: some View {
    TabView(selection: $tab) {
      TripsTab(path: $tripsPath)
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
    .onChange(of: activationRouter?.pendingRoute) { _, _ in
      consumeActivationRoute()
    }
    .task {
      // Drain any cold-launch route enqueued before this view appeared.
      consumeActivationRoute()
    }
    .onChange(of: scenePhase) { _, newPhase in
      if newPhase == .background {
        hasBeenBackgrounded = true
        return
      }
      guard newPhase == .active, hasBeenBackgrounded else { return }
      hasBeenBackgrounded = false
      do {
        _ = try RulesEngineRunner(
          context: tripsLocalContainer.mainContext,
          mastersContext: globalsContainer.mainContext,
          hook: hook
        )
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

  /// Phase 6 Req 5.1 / 5.4 — peek at the router's `pendingRoute`, navigate
  /// to the referenced trip, and leave the slot filled so `TripDetailView`
  /// can consume it on appear and apply `route.phase` to its
  /// `expandedPhase`. A miss on the trip lookup discards the route per
  /// Req 5.4 without modifying navigation state.
  private func consumeActivationRoute() {
    guard let router = activationRouter,
      let route = router.pendingRoute
    else { return }
    let tripID = route.tripID
    let descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == tripID })
    guard let trip = try? tripsLocalContainer.mainContext.fetch(descriptor).first else {
      _ = router.consumeRoute()
      return
    }
    tab = .trips
    tripsPath = NavigationPath()
    tripsPath.append(trip)
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
