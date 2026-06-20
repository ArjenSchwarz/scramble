import XCTest

/// Task 9 — happy-path coverage for the "Copy to people…" flow on the Master
/// Lists packing list. Seeds two people (Alex owns "Socks"; Sam owns nothing),
/// reveals the per-row copy action, selects Sam, confirms, and asserts the
/// sheet dismisses and the confirmation toast names Sam (Req 1.1 / 1.2 / 5.1).
/// Driven entirely through the `accessibilityIdentifier`s added in Tasks 7/8.
final class CopyMasterPackingItemUITests: XCTestCase {

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

  @MainActor
  private func openMasterLists(_ app: XCUIApplication) {
    let tab = app.tabBars.buttons["Master Lists"]
    XCTAssertTrue(tab.waitForExistence(timeout: 3))
    tab.tap()
    XCTAssertTrue(app.navigationBars["Master Lists"].waitForExistence(timeout: 3))
  }

  @MainActor
  func testCopyToPersonShowsConfirmationToast() {
    let app = launchedApp(fixture: "master-packing-copy-two-people")
    openMasterLists(app)
    // Packing Items is the default segment.

    let row = app.descendants(matching: .any)
      .matching(identifier: "masterPacking.itemRow.Socks")
      .firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 3), "Seeded 'Socks' row should be visible")

    // Reveal the trailing swipe action and tap "Copy to people…".
    row.swipeLeft()
    let copyAction = app.buttons["Copy to people…"]
    XCTAssertTrue(
      copyAction.waitForExistence(timeout: 3),
      "Trailing swipe should reveal the 'Copy to people…' action"
    )
    copyAction.tap()

    // The picker presents Sam as an eligible target (Alex is the owner).
    let samRow = app.descendants(matching: .any)
      .matching(identifier: "copyPacking.person.Sam")
      .firstMatch
    XCTAssertTrue(samRow.waitForExistence(timeout: 3), "Sam should be an eligible copy target")
    samRow.tap()

    let confirm = app.buttons["copyPacking.confirm"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 3))
    XCTAssertTrue(confirm.isEnabled, "Confirm should enable once Sam is selected")
    confirm.tap()

    // Assert the toast FIRST: it is set the instant `performCopy` runs (right
    // after dismissing the picker) and self-dismisses after a few seconds, so
    // checking it before the slower dismissal poll avoids racing its timeout.
    let toast = app.staticTexts["Copied to Sam."]
    XCTAssertTrue(
      toast.waitForExistence(timeout: 5),
      "A confirmation toast naming Sam should appear on the list"
    )

    // And the picker is gone (its confirm button no longer exists).
    XCTAssertFalse(
      confirm.exists,
      "The copy sheet should dismiss after confirming"
    )
  }
}
