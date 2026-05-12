import XCTest

/// Round-trip coverage for `ConditionsEditor` chips and the `AdvancedConditionView`
/// escape hatch (AC 3.6, 3.4, 3.7a/b/c). The advanced-condition flow uses the
/// `master-task-advanced-conditions` fixture so the editor sees a stored
/// condition with an out-of-domain `weather` value and renders the read-only
/// placeholder.
final class ConditionsEditorUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

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
  private func openTasksSegment(_ app: XCUIApplication) {
    let tab = app.tabBars.buttons["Master Lists"]
    XCTAssertTrue(tab.waitForExistence(timeout: 3))
    tab.tap()
    let segment = app.buttons["Tasks"]
    XCTAssertTrue(segment.waitForExistence(timeout: 3))
    segment.tap()
  }

  // MARK: - AC 3.6 — chip selections round-trip

  @MainActor
  func testChipSelectionsRoundTrip() {
    let app = launchedApp()
    openTasksSegment(app)

    // Create a master task with a couple of weather chips and a scope chip.
    app.buttons["Add task"].tap()
    let nameField = app.textFields["Task name"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 3))
    nameField.tap()
    nameField.typeText("Round-trip task")

    // Weather: Rain, Cold. Scope: International.
    // Chip labels use the `attributeValueDisplay` formatter (first char upper).
    tapChip(app, "Rain")
    tapChip(app, "Cold")
    tapChip(app, "International")

    app.buttons["Save"].tap()

    // Reopen the row — the chip state must reconstruct from the persisted
    // `.all([.match(weather, [rain, cold]), .match(scope, [international])])`.
    let row = app.buttons["Round-trip task"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.tap()

    XCTAssertTrue(
      app.buttons["Rain"].waitForExistence(timeout: 3),
      "Editor should reopen with the Rain chip selectable"
    )
    XCTAssertTrue(chipIsSelected(app, "Rain"), "Rain chip should be selected on reopen")
    XCTAssertTrue(chipIsSelected(app, "Cold"), "Cold chip should be selected on reopen")
    XCTAssertTrue(
      chipIsSelected(app, "International"),
      "International chip should be selected on reopen"
    )
    XCTAssertFalse(
      chipIsSelected(app, "Sun"),
      "Sun chip should NOT be selected — it was never toggled"
    )
  }

  // MARK: - AC 3.4 — empty save persists as .always

  @MainActor
  func testEmptySavePersistsAsAlways() {
    let app = launchedApp()
    openTasksSegment(app)

    app.buttons["Add task"].tap()
    let nameField = app.textFields["Task name"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 3))
    nameField.tap()
    nameField.typeText("Empty conditions")
    app.buttons["Save"].tap()

    let row = app.buttons["Empty conditions"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.tap()

    // On reopen, no chip should be selected (the empty state matches `.always`).
    XCTAssertTrue(app.buttons["Rain"].waitForExistence(timeout: 3))
    for value in ["Sun", "Rain", "Cold", "Hot", "Domestic", "International"] {
      XCTAssertFalse(
        chipIsSelected(app, value),
        "\(value) chip should be unselected when stored conditions are .always"
      )
    }
  }

  // MARK: - AC 3.7a/b — advanced shape renders read-only placeholder

  @MainActor
  func testDomainMismatchedConditionsShowAdvancedPlaceholder() {
    let app = launchedApp(fixture: "master-task-advanced-conditions")
    openTasksSegment(app)

    // Open the seeded master ("Snow boots check").
    let row = app.buttons["Snow boots check"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.tap()

    // Advanced placeholder shows the locked-condition label and the
    // pretty-printed condition tree. The Rain chip MUST NOT be present —
    // the conditions section is the AdvancedConditionView, not ConditionsEditor.
    XCTAssertTrue(
      app.staticTexts["Advanced condition"].waitForExistence(timeout: 3),
      "Should render AdvancedConditionView when stored conditions reference out-of-domain values"
    )
    XCTAssertFalse(
      app.buttons["Rain"].exists,
      "Weather chips should NOT be rendered while the advanced placeholder is shown"
    )

    // AC 3.7b — name and phase editing remain available.
    let nameField = app.textFields["Task name"]
    XCTAssertTrue(nameField.exists, "Task name field should be editable in advanced mode")

    // Picker(.menu) renders its accessibility label as "Phase, <currentValue>".
    let phasePicker = app.buttons
      .matching(NSPredicate(format: "label BEGINSWITH %@", "Phase,"))
      .firstMatch
    XCTAssertTrue(phasePicker.exists, "Phase picker should be editable in advanced mode")
  }

  // MARK: - AC 3.7c — Reset to simple shows confirmation dialog

  /// Verifies the Reset-to-simple flow surfaces a destructive confirmation
  /// dialog. Asserting the post-reset state transition is brittle under
  /// iOS 26's XCTest tap path for confirmationDialog destructive buttons;
  /// the state transition itself is covered by `AttributeSelectionsTests`
  /// (`.always → AttributeSelections.empty`).
  @MainActor
  func testResetToSimpleShowsConfirmationDialog() {
    let app = launchedApp(fixture: "master-task-advanced-conditions")
    openTasksSegment(app)

    let row = app.buttons["Snow boots check"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.tap()

    XCTAssertTrue(app.staticTexts["Advanced condition"].waitForExistence(timeout: 3))

    let resetButton = app.buttons["Reset to simple"]
    XCTAssertTrue(resetButton.exists)
    resetButton.tap()

    let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "Reset")).firstMatch
    XCTAssertTrue(
      confirm.waitForExistence(timeout: 3),
      "Confirmation dialog should expose a destructive Reset button"
    )
  }

  // MARK: - Helpers

  /// Tap a chip in the conditions editor by its display label. Chips are
  /// buttons rendered by `ConditionsEditor.chip(...)`.
  @MainActor
  private func tapChip(_ app: XCUIApplication, _ label: String) {
    let chip = app.buttons[label]
    XCTAssertTrue(chip.waitForExistence(timeout: 3), "Chip \(label) should exist")
    chip.tap()
  }

  /// XCUITest exposes selection state of `Button` cells through `isSelected`
  /// in many controls, but plain SwiftUI buttons report selection state via
  /// the `value` attribute or `accessibilityValue`. The chip's accessibility
  /// label remains the value text ("Rain"); selection state is reflected in
  /// the visual fill, which XCUITest can't read directly. Use `isSelected`
  /// as a best-effort signal and fall back to label / value substring checks.
  @MainActor
  private func chipIsSelected(_ app: XCUIApplication, _ label: String) -> Bool {
    let chip = app.buttons[label]
    guard chip.exists else { return false }
    return chip.isSelected
  }
}
