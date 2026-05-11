import XCTest

/// Cold-launch navigation behaviour for `TripsTab`:
/// - zero / non-qualifying / multiple-qualifying trips → land on Trip List
/// - exactly one qualifying trip → auto-open Trip Detail
/// - tab bar hidden inside Trip Detail and restored on pop
/// - auto-open does NOT re-fire when the user switches tabs and returns
///
/// Each test launches a fresh process with a debug-only `-seed-fixture` arg
/// that pre-populates the in-memory `ModelContainer` (see `UITestSeed`).
final class RootNavigationUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  // MARK: - Helpers

  @MainActor
  private func launchedApp(fixture: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    var args = ["-uitest", "1"]
    if let fixture {
      args += ["-seed-fixture", fixture]
    }
    app.launchArguments = args
    app.launch()
    return app
  }

  /// Wait for the in-memory marker so we know the app finished its first body
  /// pass before we make navigation assertions.
  @MainActor
  private func waitForFirstFrame(_ app: XCUIApplication, timeout: TimeInterval = 5) {
    let marker = app.descendants(matching: .any)
      .matching(identifier: "modelStore.in-memory")
      .firstMatch
    XCTAssertTrue(marker.waitForExistence(timeout: timeout))
  }

  /// True when the root Trip List screen is visible (the "New Trip" button is
  /// only on the list, never on Trip Detail).
  @MainActor
  private func isOnTripList(_ app: XCUIApplication) -> Bool {
    app.buttons["New Trip"].exists
  }

  // MARK: - Cold launch outcomes

  @MainActor
  func testColdLaunchZeroTripsShowsTripList() {
    let app = launchedApp()
    waitForFirstFrame(app)

    XCTAssertTrue(
      app.buttons["New Trip"].waitForExistence(timeout: 3),
      "Expected Trip List with +New affordance when no trips exist"
    )
    XCTAssertTrue(app.tabBars.firstMatch.exists, "Tab bar should be visible at the root")
  }

  @MainActor
  func testColdLaunchOneQualifyingTripAutoOpensDetail() {
    let app = launchedApp(fixture: "one-qualifying-trip")
    waitForFirstFrame(app)

    // Detail header shows the trip name; this proves we auto-pushed Trip Detail.
    XCTAssertTrue(
      app.staticTexts["Active Trip"].waitForExistence(timeout: 5),
      "Expected to be auto-pushed into Trip Detail for the single qualifying trip"
    )
    XCTAssertFalse(
      isOnTripList(app),
      "Trip List affordances should not be visible while Trip Detail is showing"
    )
  }

  @MainActor
  func testColdLaunchOneNonQualifyingTripShowsTripList() {
    let app = launchedApp(fixture: "one-non-qualifying-trip")
    waitForFirstFrame(app)

    XCTAssertTrue(
      app.buttons["New Trip"].waitForExistence(timeout: 3),
      "A non-qualifying trip must not auto-open; user should land on Trip List"
    )
  }

  @MainActor
  func testColdLaunchTwoQualifyingTripsShowsTripList() {
    let app = launchedApp(fixture: "two-qualifying-trips")
    waitForFirstFrame(app)

    XCTAssertTrue(
      app.buttons["New Trip"].waitForExistence(timeout: 3),
      "Two qualifying trips must NOT auto-open; user should land on Trip List"
    )
  }

  // MARK: - Tab bar visibility

  @MainActor
  func testTabBarHiddenOnDetailRestoredOnPop() {
    let app = launchedApp(fixture: "one-qualifying-trip")
    waitForFirstFrame(app)

    XCTAssertTrue(app.staticTexts["Active Trip"].waitForExistence(timeout: 5))
    XCTAssertFalse(
      app.tabBars.firstMatch.exists,
      "Tab bar must be hidden while Trip Detail is on screen"
    )

    // Pop back to Trip List via the navigation back button (labelled with the
    // parent screen's nav title, "Trips").
    let backButton = app.navigationBars.buttons["Trips"]
    XCTAssertTrue(backButton.waitForExistence(timeout: 3))
    backButton.tap()

    XCTAssertTrue(
      app.buttons["New Trip"].waitForExistence(timeout: 3),
      "After pop, Trip List should be visible"
    )
    XCTAssertTrue(
      app.tabBars.firstMatch.waitForExistence(timeout: 3),
      "Tab bar should reappear after popping out of Trip Detail"
    )
  }

  // MARK: - Auto-open re-fire guard

  @MainActor
  func testAutoOpenDoesNotRefireOnTabSwitch() {
    let app = launchedApp(fixture: "one-qualifying-trip")
    waitForFirstFrame(app)

    // 1. Auto-opened to Trip Detail.
    XCTAssertTrue(app.staticTexts["Active Trip"].waitForExistence(timeout: 5))

    // 2. Pop back to Trip List.
    let backButton = app.navigationBars.buttons["Trips"]
    XCTAssertTrue(backButton.waitForExistence(timeout: 3))
    backButton.tap()
    XCTAssertTrue(app.buttons["New Trip"].waitForExistence(timeout: 3))

    // 3. Switch tabs and back.
    let masterListsTab = app.tabBars.buttons["Master Lists"]
    XCTAssertTrue(masterListsTab.waitForExistence(timeout: 3))
    masterListsTab.tap()
    // MasterListsTab shows the segmented Picker — wait on a known control.
    XCTAssertTrue(
      app.navigationBars["Master Lists"].waitForExistence(timeout: 3),
      "Should land on the Master Lists tab"
    )

    let tripsTab = app.tabBars.buttons["Trips"]
    XCTAssertTrue(tripsTab.waitForExistence(timeout: 3))
    tripsTab.tap()

    // 4. Trip List should still be the visible screen — auto-open MUST NOT
    //    re-trigger on tab re-selection (per AC 5.7 / design.md).
    XCTAssertTrue(
      app.buttons["New Trip"].waitForExistence(timeout: 3),
      "Trip List should remain visible — auto-open must not re-fire on tab switch"
    )
  }
}
