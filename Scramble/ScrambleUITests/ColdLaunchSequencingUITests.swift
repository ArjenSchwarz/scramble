import XCTest

/// AC 5.4 — the cold-launch rules-engine scan in `ScrambleApp.init()` runs
/// before the WindowGroup mounts any view, so by the time Phase 1's
/// auto-open task (`TripsTab.task`) fires the qualifying-trip Trip Detail
/// already sees rule-driven items. This test pins that ordering invariant:
/// seed one qualifying trip + one `MasterTaskItem` whose conditions match,
/// cold-launch, and assert the auto-opened Trip Detail observes the
/// post-scan state.
final class ColdLaunchSequencingUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testColdLaunchScanCompletesBeforeAutoOpen() {
    let app = XCUIApplication()
    app.launchArguments = ["-uitest", "1", "-seed-fixture", "phase2-rules-cold-launch"]
    app.launch()

    let marker = app.descendants(matching: .any)
      .matching(identifier: "modelStore.in-memory")
      .firstMatch
    XCTAssertTrue(marker.waitForExistence(timeout: 5))

    // Phase 1 AC 5.6: a single qualifying trip auto-opens the Trip Detail.
    XCTAssertTrue(
      app.staticTexts["Active Trip"].waitForExistence(timeout: 5),
      "Single qualifying trip should auto-open into Trip Detail"
    )

    // The seeded MasterTaskItem ("Charge devices", conditions=.always) should
    // already be on the trip with currentlyMatchesRules=true — proving the
    // ScrambleApp.init() scan ran before this view appeared.
    let chargeMarker = app.descendants(matching: .any)
      .matching(identifier: "tripDetail.task.matching.Charge devices")
      .firstMatch
    XCTAssertTrue(
      chargeMarker.waitForExistence(timeout: 5),
      "AC 5.4: cold-launch scan must populate rule-driven tasks before auto-open"
    )
  }
}
