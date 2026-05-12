import XCTest

/// End-to-end create / edit / delete coverage for the Master Lists tab (Tasks
/// and Packing Items segments), exercising `MasterTasksList`, `MasterPackingList`,
/// `MasterTaskEditor`, and `MasterPackingEditor`. Master Packing tests rely on
/// the `master-lists-empty-with-person` fixture to satisfy AC 2.7's empty-state
/// rule (no Person → no "+ Add item").
final class MasterListsCRUDUITests: XCTestCase {

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

  @MainActor
  private func openMasterLists(_ app: XCUIApplication) {
    let tab = app.tabBars.buttons["Master Lists"]
    XCTAssertTrue(tab.waitForExistence(timeout: 3))
    tab.tap()
    XCTAssertTrue(app.navigationBars["Master Lists"].waitForExistence(timeout: 3))
  }

  @MainActor
  private func selectSegment(_ app: XCUIApplication, _ title: String) {
    let segment = app.buttons[title]
    XCTAssertTrue(segment.waitForExistence(timeout: 3))
    segment.tap()
  }

  /// Swipe up on the editor sheet's Form to bring lazy-rendered cells (e.g.
  /// the Delete section, which sits below the chip-grid Conditions section)
  /// into the accessibility hierarchy. Iterates a few times for tall forms.
  @MainActor
  private func scrollFormToBottom(_ app: XCUIApplication) {
    let nav = app.navigationBars.firstMatch
    if nav.exists { nav.tap() }
    for _ in 0..<5 {
      app.swipeUp()
    }
  }

  // MARK: - Master Task CRUD

  @MainActor
  func testCreateMasterTaskAppearsUnderPhaseHeader() {
    let app = launchedApp(fixture: "master-lists-empty-with-person")
    openMasterLists(app)
    selectSegment(app, "Tasks")

    app.buttons["Add task"].tap()

    let nameField = app.textFields["Task name"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 3))
    nameField.tap()
    nameField.typeText("Pack chargers")

    // Default phase is .weeksBefore (per `MasterTaskDraft.newDraft()`) which
    // renders as "Weeks before". Skip conditions — leave all chips empty.
    app.buttons["Save"].tap()

    // Back on the Tasks segment — row appears under the "Weeks before" header.
    // Rows render as Buttons (Master*List uses `Button { ... } label: { Text }`).
    XCTAssertTrue(
      app.buttons["Pack chargers"].waitForExistence(timeout: 3),
      "New master task should appear in the Tasks segment"
    )
    XCTAssertTrue(
      app.staticTexts["Weeks before"].exists,
      "The 'Weeks before' phase header should be visible (its only row was just inserted)"
    )
  }

  @MainActor
  func testEditMasterTaskRowUpdates() {
    let app = launchedApp(fixture: "master-lists-empty-with-person")
    openMasterLists(app)
    selectSegment(app, "Tasks")

    // Create a row first.
    app.buttons["Add task"].tap()
    let nameField = app.textFields["Task name"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 3))
    nameField.tap()
    nameField.typeText("Charge Kindle")
    app.buttons["Save"].tap()

    let row = app.buttons["Charge Kindle"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.tap()

    // Editor reopens with the existing name. Clear and retype.
    let editField = app.textFields["Task name"]
    XCTAssertTrue(editField.waitForExistence(timeout: 3))
    editField.tap()
    editField.clearText()
    editField.typeText("Charge tablet")
    app.buttons["Save"].tap()

    XCTAssertTrue(
      app.buttons["Charge tablet"].waitForExistence(timeout: 3),
      "Renamed task should be visible in the list"
    )
    XCTAssertFalse(
      app.buttons["Charge Kindle"].exists,
      "Original task name should be gone after rename"
    )
  }

  /// Verifies the destructive-confirmation flow is reachable in the master
  /// task editor. The actual delete-and-flag-orphans persistence is covered
  /// by `MasterPersistenceTests` and `RulesEngineRunnerTests`; under iOS 26
  /// the confirmationDialog destructive button's action does not always fire
  /// through XCTest's synthesized tap path, so we limit the assertion to the
  /// dialog appearing with the expected destructive label.
  @MainActor
  func testDeleteMasterTaskShowsConfirmationDialog() {
    let app = launchedApp(fixture: "master-lists-empty-with-person")
    openMasterLists(app)
    selectSegment(app, "Tasks")

    app.buttons["Add task"].tap()
    let nameField = app.textFields["Task name"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 3))
    nameField.tap()
    nameField.typeText("Temporary task")
    app.buttons["Save"].tap()

    let row = app.buttons["Temporary task"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.tap()

    scrollFormToBottom(app)
    let deleteRow = app.buttons["Delete master task"]
    XCTAssertTrue(deleteRow.waitForExistence(timeout: 3))
    deleteRow.tap()

    let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "Delete")).firstMatch
    XCTAssertTrue(
      confirm.waitForExistence(timeout: 3),
      "Confirmation dialog should expose a destructive Delete button"
    )
  }

  // MARK: - Master Packing CRUD
  //
  // These tests start from a fixture that seeds a `Seeded item` MasterPackingItem
  // owned by `Alex`. The create-path is not driven through the UI because the
  // Form's `Picker(.menu)` person selector does not reliably open under
  // XCTest on iOS 26 — the create path is covered instead by
  // `MasterPersistenceTests.testCreatePacking_*` unit tests. These tests
  // verify list rendering (AC 2.1, AC 2.2) and the edit / delete UI flows.

  @MainActor
  func testSeededMasterPackingItemAppearsUnderPersonGroup() {
    let app = launchedApp(fixture: "master-lists-empty-with-person")
    openMasterLists(app)

    XCTAssertTrue(
      app.buttons["Seeded item"].waitForExistence(timeout: 3),
      "Seeded master packing item should appear in the Packing Items segment"
    )
    XCTAssertTrue(
      app.staticTexts["Alex"].exists,
      "Owning person group header should be visible"
    )
    XCTAssertTrue(
      app.buttons["Add item"].exists,
      "+ Add item affordance should be visible when at least one Person exists"
    )
  }

  @MainActor
  func testEditMasterPackingItemRowUpdates() {
    let app = launchedApp(fixture: "master-lists-empty-with-person")
    openMasterLists(app)

    let row = app.buttons["Seeded item"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.tap()

    let editField = app.textFields["Item name"]
    XCTAssertTrue(editField.waitForExistence(timeout: 3))
    editField.tap()
    editField.clearText()
    editField.typeText("New name")
    app.buttons["Save"].tap()

    XCTAssertTrue(
      app.buttons["New name"].waitForExistence(timeout: 3),
      "Renamed packing item should be visible"
    )
    XCTAssertFalse(app.buttons["Seeded item"].exists)
  }

  /// See `testDeleteMasterTaskShowsConfirmationDialog` — same iOS 26 XCTest
  /// limitation around confirmationDialog destructive buttons.
  @MainActor
  func testDeleteMasterPackingItemShowsConfirmationDialog() {
    let app = launchedApp(fixture: "master-lists-empty-with-person")
    openMasterLists(app)

    let row = app.buttons["Seeded item"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.tap()

    scrollFormToBottom(app)
    let deleteRow = app.buttons["Delete master packing item"]
    XCTAssertTrue(deleteRow.waitForExistence(timeout: 3))
    deleteRow.tap()

    let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "Delete")).firstMatch
    XCTAssertTrue(
      confirm.waitForExistence(timeout: 3),
      "Confirmation dialog should expose a destructive Delete button"
    )
  }
}

extension XCUIElement {
  /// Clears the current text in a text field by selecting all and typing the
  /// delete key. The standard `XCUIElement.typeText("")` is a no-op; this is
  /// the path Apple's sample UI tests use.
  fileprivate func clearText() {
    guard let stringValue = self.value as? String else { return }
    let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
    self.typeText(deleteString)
  }
}
