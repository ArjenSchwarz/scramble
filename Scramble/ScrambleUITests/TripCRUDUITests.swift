import XCTest

/// End-to-end create / edit / delete coverage for trips, exercising the
/// `TripEditorView` form, the Trip Detail menu, and the delete-confirmation
/// dialog. Each test starts a fresh process; tests that need pre-existing
/// state seed via `-seed-fixture single-editable-trip` (see `UITestSeed`).
final class TripCRUDUITests: XCTestCase {

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

    let marker = app.descendants(matching: .any)
      .matching(identifier: "modelStore.in-memory")
      .firstMatch
    XCTAssertTrue(marker.waitForExistence(timeout: 5))
    return app
  }

  // MARK: - Create

  @MainActor
  func testCreateTripAppearsInList() {
    let app = launchedApp()
    XCTAssertTrue(app.buttons["New Trip"].waitForExistence(timeout: 3))

    app.buttons["New Trip"].tap()

    // Editor sheet — TextField placeholder is "Trip name".
    let nameField = app.textFields["Trip name"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 3))
    nameField.tap()
    nameField.typeText("My New Trip")

    // Default start/end are today (valid: end == start), so we can save now.
    app.buttons["Save"].tap()

    // Back on the list — the new trip's name appears.
    XCTAssertTrue(
      app.staticTexts["My New Trip"].waitForExistence(timeout: 3),
      "Created trip should appear in the Trip List"
    )
  }

  // MARK: - Edit

  @MainActor
  func testEditTripAttributesUpdatesChips() {
    let app = launchedApp(fixture: "single-editable-trip")
    XCTAssertTrue(app.buttons["New Trip"].waitForExistence(timeout: 3))

    // Open Trip Detail.
    let row = app.staticTexts["Sample Trip"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.tap()

    // Open the trip-actions menu and tap Edit.
    let actionsButton = app.buttons["Trip actions"]
    XCTAssertTrue(actionsButton.waitForExistence(timeout: 3))
    actionsButton.tap()

    let editButton = app.buttons["Edit"]
    XCTAssertTrue(editButton.waitForExistence(timeout: 3))
    editButton.tap()

    // Editor sheet — toggle a Weather value (the only multi-select attribute).
    // Weather rows are buttons whose label is the capitalised value.
    let rainOption = app.buttons["Rain"]
    XCTAssertTrue(rainOption.waitForExistence(timeout: 3))
    rainOption.tap()

    app.buttons["Save"].tap()

    // Back on Trip Detail — chips render the display form ("Rain") consistent
    // with the editor's picker rows (see `TripDetailView.chipRow`).
    XCTAssertTrue(
      app.buttons["Rain"].waitForExistence(timeout: 3),
      "After save, the Weather chip 'Rain' should appear in the Trip Detail header"
    )
  }

  // MARK: - Delete

  @MainActor
  func testDeleteTripRemovesItFromList() {
    let app = launchedApp(fixture: "single-editable-trip")
    XCTAssertTrue(app.buttons["New Trip"].waitForExistence(timeout: 3))

    let row = app.staticTexts["Sample Trip"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.tap()

    let actionsButton = app.buttons["Trip actions"]
    XCTAssertTrue(actionsButton.waitForExistence(timeout: 3))
    actionsButton.tap()

    let deleteMenuButton = app.buttons["Delete Trip"]
    XCTAssertTrue(deleteMenuButton.waitForExistence(timeout: 3))
    deleteMenuButton.tap()

    // Confirmation dialog — destructive button label includes the trip name.
    let confirmButton = app.buttons["Delete Sample Trip"]
    XCTAssertTrue(confirmButton.waitForExistence(timeout: 3))
    confirmButton.tap()

    // Back on Trip List, "Sample Trip" should be gone.
    XCTAssertTrue(app.buttons["New Trip"].waitForExistence(timeout: 3))
    XCTAssertFalse(
      app.staticTexts["Sample Trip"].exists,
      "Deleted trip should disappear from the Trip List"
    )
  }
}
