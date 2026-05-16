import XCTest

/// Phase 5 — UI coverage for the Trip List migration-state surfaces:
/// the failed-entry retry banner
/// (Req [4.4](../../specs/phase-5-cloudkit-sharing/requirements.md#4.4))
/// and the per-trip "Syncing…" badge while Stage B is in progress
/// (Req [4.8](../../specs/phase-5-cloudkit-sharing/requirements.md#4.8)).
final class Phase5MigrationStateUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  private func launchedApp(fixture: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-uitest", "1", "-seed-fixture", fixture]
    app.launch()
    let marker = app.descendants(matching: .any)
      .matching(identifier: "modelStore.in-memory")
      .firstMatch
    XCTAssertTrue(marker.waitForExistence(timeout: 5))
    return app
  }

  // MARK: - Retry banner

  @MainActor
  func testFailedMigrationRowAppearsInRetryBanner() {
    let app = launchedApp(fixture: "phase5-migration-states")
    let banner = app.descendants(matching: .any)
      .matching(identifier: "tripList.migrationRetryBanner")
      .firstMatch
    XCTAssertTrue(
      banner.waitForExistence(timeout: 3),
      "Migration retry banner should render when at least one journal entry is .failed"
    )
  }

  // MARK: - Syncing badge

  @MainActor
  func testStageBInProgressTripShowsSyncingBadge() {
    let app = launchedApp(fixture: "phase5-migration-states")
    XCTAssertTrue(
      app.staticTexts["Syncing Trip"].waitForExistence(timeout: 3),
      "Stage-B-in-progress trip should appear in the Trip List"
    )
    let badge = app.descendants(matching: .any)
      .matching(identifier: "tripRow.syncingBadge")
      .firstMatch
    XCTAssertTrue(
      badge.waitForExistence(timeout: 3),
      "Stage-B-in-progress trip should render a 'Syncing…' badge"
    )
  }
}
