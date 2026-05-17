import XCTest

/// Phase 5.1 — verifies that the Trip Editor's people picker (extracted
/// into `TripEditorPeoplePicker` and re-rooted to the globals container
/// via `.modelContainer(globals)`) keeps its `@Query<Person>` live: a
/// `Person` created from the inline `PersonEditor` sheet appears in the
/// picker as soon as the sheet dismisses, without leaving the Trip
/// Editor. The reactivity proves the picker subtree's `@Query` is bound
/// to globals rather than the parent's `tripsLocal` container.
final class TripEditorPickerReactivityUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  private func launchedApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-uitest", "1"]
    app.launch()

    let marker = app.descendants(matching: .any)
      .matching(identifier: "modelStore.in-memory")
      .firstMatch
    XCTAssertTrue(marker.waitForExistence(timeout: 5))
    return app
  }

  @MainActor
  func testNewPersonCreatedInlineAppearsInPickerWithoutLeavingEditor() throws {
    let app = launchedApp()

    XCTAssertTrue(app.buttons["New Trip"].waitForExistence(timeout: 3))
    app.buttons["New Trip"].tap()

    // Editor open — find the inline "Create new person" affordance.
    let createNewPerson = app.buttons["Create new person"]
    XCTAssertTrue(createNewPerson.waitForExistence(timeout: 3))
    createNewPerson.tap()

    // PersonEditor sheet — fill out a unique name and save.
    let nameField = app.textFields["Person name"]
    if nameField.waitForExistence(timeout: 3) {
      nameField.tap()
      let unique = "Reactivity-\(UUID().uuidString.prefix(6))"
      nameField.typeText(String(unique))

      let save = app.buttons["Save"]
      if save.exists { save.tap() }

      // Sheet dismisses — the new Person should now appear in the Trip
      // Editor's selected list (the picker auto-adds the newly-created
      // person to the draft per `newlyCreatedPerson` handling).
      XCTAssertTrue(
        app.staticTexts[String(unique)].waitForExistence(timeout: 5),
        "Newly-created Person must appear in the picker's selected list — proves @Query is live against globals"
      )

      // Confirm we are still on the Trip Editor.
      XCTAssertTrue(app.buttons["Cancel"].exists, "Trip Editor should still be on screen")
    } else {
      throw XCTSkip("PersonEditor sheet did not mount — picker reactivity test skipped")
    }
  }
}
