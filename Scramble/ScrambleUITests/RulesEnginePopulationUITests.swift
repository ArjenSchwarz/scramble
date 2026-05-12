import XCTest

/// AC 5.1 (trip create) and AC 5.2 (trip edit) — the rules engine must
/// re-evaluate against a trip exactly once at save commit and populate any
/// matching `MasterPackingItem` as a `TripPackingItem` with
/// `currentlyMatchesRules = true`. The assertions read debug-only
/// accessibility identifiers emitted by `TripDetailView.inspectionMarkers`
/// because Phase 2 does not ship a trip-timeline UI consumer for these
/// records — Phase 3 will.
final class RulesEnginePopulationUITests: XCTestCase {

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

  // MARK: - AC 5.1 — trip create populates matching rule items

  @MainActor
  func testCreateTripPopulatesMatchingMasterPackingItem() {
    let app = launchedApp(fixture: "phase2-rules-fixture")

    // Trip List visible — no qualifying trip seeded, no auto-open.
    XCTAssertTrue(app.buttons["New Trip"].waitForExistence(timeout: 3))
    app.buttons["New Trip"].tap()

    let nameField = app.textFields["Trip name"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 3))
    nameField.tap()
    nameField.typeText("Wet trip")

    // Toggle Weather=Rain (Weather is the multi-select attribute, rendered as
    // a button row in the trip editor — see `TripEditorView.multiSelectRows`).
    let rainOption = app.buttons["Rain"]
    XCTAssertTrue(rainOption.waitForExistence(timeout: 3))
    rainOption.tap()

    app.buttons["Save"].tap()

    // Back on Trip List. Open Trip Detail to read the inspection markers.
    let row = app.staticTexts["Wet trip"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.tap()

    let marker = app.descendants(matching: .any)
      .matching(identifier: "tripDetail.packingItem.matching.Rain jacket")
      .firstMatch
    XCTAssertTrue(
      marker.waitForExistence(timeout: 5),
      "AC 5.1: 'Rain jacket' should be auto-populated with currentlyMatchesRules=true after Save"
    )
  }

  // MARK: - AC 5.2 — trip edit re-runs engine and matches the new attributes

  @MainActor
  func testEditTripAttributesPopulatesMatchingMasterPackingItem() {
    let app = launchedApp(fixture: "phase2-rules-fixture-sun-trip")

    XCTAssertTrue(app.buttons["New Trip"].waitForExistence(timeout: 3))

    // Open the seeded "Sunny Trip" (Weather=Sun; no Rain jacket yet because
    // master conditions evaluate false).
    let row = app.staticTexts["Sunny Trip"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.tap()

    // Before edit: Rain jacket should NOT be on the trip.
    XCTAssertFalse(
      app.descendants(matching: .any)
        .matching(identifier: "tripDetail.packingItem.matching.Rain jacket")
        .firstMatch.exists,
      "Before edit, the Sun trip should NOT have 'Rain jacket' populated"
    )

    // Open the edit sheet via the actions menu.
    let actionsButton = app.buttons["Trip actions"]
    XCTAssertTrue(actionsButton.waitForExistence(timeout: 3))
    actionsButton.tap()
    app.buttons["Edit"].tap()

    // Toggle Sun off, Rain on. Both labels exist in two places — the editor's
    // multi-select row AND the Trip Detail chip row in the background —
    // so use `.firstMatch` on a predicate query to pick the editor row
    // (which has the `Selected` trait when its value is part of the trip).
    let sunOption = app.buttons.matching(NSPredicate(format: "label == %@", "Sun")).firstMatch
    XCTAssertTrue(sunOption.waitForExistence(timeout: 3))
    sunOption.tap()
    let rainOption = app.buttons.matching(NSPredicate(format: "label == %@", "Rain")).firstMatch
    XCTAssertTrue(rainOption.waitForExistence(timeout: 3))
    rainOption.tap()

    app.buttons["Save"].tap()

    let marker = app.descendants(matching: .any)
      .matching(identifier: "tripDetail.packingItem.matching.Rain jacket")
      .firstMatch
    XCTAssertTrue(
      marker.waitForExistence(timeout: 5),
      "AC 5.2: changing Weather to Rain should populate 'Rain jacket' with currentlyMatchesRules=true"
    )
  }
}
