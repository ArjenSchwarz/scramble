import XCTest

/// Smoke test for ModelContainer wiring: launching with `-uitest 1` MUST
/// produce the in-memory `ModelStore` so UI tests never touch CloudKit.
/// Companion to `ScrambleTests/Persistence/ModelStoreEnvironmentTests` which
/// covers the probe in isolation; this verifies the host-app side.
final class AppLaunchUITests: XCTestCase {

  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    // launchArguments MUST be set BEFORE launch() — setting them after is a no-op.
    app.launchArguments = ["-uitest", "1"]
    app.launch()
  }

  @MainActor
  func testLaunchUsesInMemoryContainer() {
    let marker = app.descendants(matching: .any)
      .matching(identifier: "modelStore.in-memory")
      .firstMatch
    XCTAssertTrue(
      marker.waitForExistence(timeout: 5),
      "Expected RootView to expose the modelStore.in-memory accessibility identifier when launched with -uitest 1"
    )
  }
}
