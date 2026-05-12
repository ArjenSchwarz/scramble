import XCTest

/// AC 5.7 — the `RootView` scenePhase trigger runs the rules engine on
/// `.background → .active` transitions but NOT on the cold-launch
/// `nil → .inactive → .active` sequence. `RootView` exposes a debug-only
/// counter via an accessibility identifier prefixed
/// `rulesEngine.scenePhaseRunnerCalls.` so this test can assert the count
/// at each lifecycle point.
final class RootViewScenePhaseTests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  /// Reads the scene-phase runner-call counter from the accessibility tree.
  /// Returns nil when no matching marker exists yet (e.g. during a
  /// transient state).
  @MainActor
  private func currentSceneRunnerCount(_ app: XCUIApplication) -> Int? {
    let prefix = "rulesEngine.scenePhaseRunnerCalls."
    // Counters are emitted by RootView's background marker view; they remain
    // in the accessibility hierarchy even when not on-screen.
    let predicate = NSPredicate(format: "identifier BEGINSWITH %@", prefix)
    let element = app.descendants(matching: .any).matching(predicate).firstMatch
    guard element.waitForExistence(timeout: 3) else { return nil }
    let identifier = element.identifier
    guard let count = Int(identifier.dropFirst(prefix.count)) else { return nil }
    return count
  }

  // MARK: - AC 5.7 — cold-launch carve-out

  @MainActor
  func testColdLaunchDoesNotInvokeSceneRunner() {
    let app = XCUIApplication()
    app.launchArguments = ["-uitest", "1"]
    app.launch()

    let marker = app.descendants(matching: .any)
      .matching(identifier: "modelStore.in-memory")
      .firstMatch
    XCTAssertTrue(marker.waitForExistence(timeout: 5))

    // The nil → .inactive → .active sequence MUST NOT increment the counter:
    // RootView's `previousScenePhase == .background` guard short-circuits.
    XCTAssertEqual(
      currentSceneRunnerCount(app),
      0,
      "Cold-launch scene-phase sequence must NOT invoke the runner — only the init() scan does"
    )
  }

  // MARK: - AC 5.7 — background → foreground transition fires once

  @MainActor
  func testBackgroundForegroundTransitionInvokesRunnerOnce() {
    let app = XCUIApplication()
    app.launchArguments = ["-uitest", "1"]
    app.launch()

    let marker = app.descendants(matching: .any)
      .matching(identifier: "modelStore.in-memory")
      .firstMatch
    XCTAssertTrue(marker.waitForExistence(timeout: 5))

    XCTAssertEqual(currentSceneRunnerCount(app), 0)

    // Send to background then reactivate.
    XCUIDevice.shared.press(.home)
    sleep(2)
    app.activate()

    // Wait for the marker to confirm we're back foreground and the counter
    // identifier has updated to "...1".
    let onePredicate = NSPredicate(
      format: "identifier == %@", "rulesEngine.scenePhaseRunnerCalls.1")
    let oneMarker = app.descendants(matching: .any).matching(onePredicate).firstMatch
    XCTAssertTrue(
      oneMarker.waitForExistence(timeout: 5),
      "AC 5.7: the .background → .active transition should invoke the runner exactly once"
    )
  }
}
