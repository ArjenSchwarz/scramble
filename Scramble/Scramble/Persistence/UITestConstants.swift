import Foundation

/// Shared constants for the UI-test launch contract. The UI test targets
/// reference the same string literals directly (XCUIApplication has no shared
/// build with the app target), but keeping the names in one place inside the
/// app prevents `EnvironmentProbe`, `UITestSeed`, and `RootView` from drifting
/// independently.
nonisolated enum UITestArguments {
  /// Launch arg that flips the app into UI-test mode (in-memory container).
  /// Passed as a pair: `["-uitest", "1"]`.
  static let uitestFlag = "-uitest"
  static let uitestValue = "1"

  /// Launch arg that seeds a fixture into the in-memory container before
  /// first render. Passed as a pair: `["-seed-fixture", "<fixture-name>"]`.
  static let seedFixtureKey = "-seed-fixture"
}

#if DEBUG
  /// Accessibility identifiers used by `RootView` to signal which `ModelContainer`
  /// branch the host app booted with. Only emitted in DEBUG.
  nonisolated enum DebugAccessibilityID {
    static let modelStoreInMemory = "modelStore.in-memory"
    static let modelStoreCloud = "modelStore.cloud"

    /// Prefix for the `RootView` counter exposing how many times the
    /// scenePhase `.background → .active` trigger has invoked the rules
    /// engine runner during this app session. Used by
    /// `RootViewScenePhaseTests` to verify the cold-launch carve-out.
    static let scenePhaseRunnerCallsPrefix = "rulesEngine.scenePhaseRunnerCalls."
  }
#endif
