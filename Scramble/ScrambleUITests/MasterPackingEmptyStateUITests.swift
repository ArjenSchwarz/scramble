import XCTest

/// AC 2.7 — when no `Person` records exist, the Master Lists Packing Items
/// segment SHALL render a `ContentUnavailableView` directing the user to the
/// trip editor AND the "+ Add item" affordance SHALL be hidden.
final class MasterPackingEmptyStateUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testEmptyPeopleStateHidesAddAffordance() {
    let app = XCUIApplication()
    // No `-seed-fixture` arg → zero Person records.
    app.launchArguments = ["-uitest", "1"]
    app.launch()

    let marker = app.descendants(matching: .any)
      .matching(identifier: "modelStore.in-memory")
      .firstMatch
    XCTAssertTrue(marker.waitForExistence(timeout: 5))

    let tab = app.tabBars.buttons["Master Lists"]
    XCTAssertTrue(tab.waitForExistence(timeout: 3))
    tab.tap()

    // Packing Items is the default segment.
    XCTAssertTrue(
      app.staticTexts["No people yet"].waitForExistence(timeout: 3),
      "ContentUnavailableView title from AC 2.7 should be visible"
    )
    XCTAssertTrue(
      app.staticTexts[
        "Add a person to a trip first, then return here to define their packing items."
      ].exists,
      "ContentUnavailableView description from AC 2.7 should be visible"
    )
    XCTAssertFalse(
      app.buttons["Add item"].exists,
      "+ Add item affordance MUST be hidden in the no-people empty state"
    )
  }
}
