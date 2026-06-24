import XCTest

/// `packing-item-subitems` feature — inline sub-item add / remove on a packing
/// row, plus read-only display once the item is moved to a read-only group
/// (Not bringing). Mirrors `PackingSheetUITests`: launches a fresh in-memory
/// container via `-uitest 1 -seed-fixture phase4-pack-mode-trip` and drives the
/// accessibility identifiers emitted by `PackingSubItemsView`.
final class PackingSubItemsUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  // MARK: - Helpers

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
  private func openTripDetail(_ app: XCUIApplication, tripName: String) {
    let row = app.staticTexts[tripName]
    if row.waitForExistence(timeout: 3), app.buttons["New Trip"].exists {
      row.tap()
    }
  }

  @MainActor
  private func openPackingSheetForFirstParticipant(_ app: XCUIApplication) {
    let summaryRow = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'tripDetail.packingSummary.'"))
      .firstMatch
    if summaryRow.waitForExistence(timeout: 5) {
      summaryRow.tap()
    }
  }

  /// Reveals the inline add field on the visible interactive row, types
  /// `text`, and submits (newline). The field stays open for rapid multi-add,
  /// so callers resign it by tapping the background when done.
  @MainActor
  private func addSubItem(_ app: XCUIApplication, text: String) {
    let addButton = app.descendants(matching: .any)
      .matching(identifier: "packingSubItems.addButton")
      .firstMatch
    XCTAssertTrue(addButton.waitForExistence(timeout: 3))
    addButton.tap()

    let addField = app.textFields["Add sub-item"]
    XCTAssertTrue(addField.waitForExistence(timeout: 3))
    addField.tap()
    addField.typeText(text)
    addField.typeText("\n")
  }

  @MainActor
  private func entry(_ app: XCUIApplication, _ text: String) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(identifier: "packingSubItems.entry.\(text)")
      .firstMatch
  }

  // MARK: - Inline add / remove + read-only display

  @MainActor
  func testAddRemoveAndReadOnlySubItem() {
    let app = launchedApp(fixture: "phase4-pack-mode-trip")
    openTripDetail(app, tripName: "Beach Trip")
    openPackingSheetForFirstParticipant(app)

    let header = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.header")
      .firstMatch
    XCTAssertTrue(header.waitForExistence(timeout: 5))

    // Sunscreen is `.unpacked` for Arjen → an interactive Still-need-to-pack
    // row exposing the inline add affordance.
    let row = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.itemRow.Sunscreen")
      .firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))

    // Add → renders on the row.
    addSubItem(app, text: "Spray bottle")
    XCTAssertTrue(
      entry(app, "Spray bottle").waitForExistence(timeout: 5),
      "Submitting a sub-item should render it on the row"
    )

    // Remove → drops from the row.
    let remove = app.buttons.matching(NSPredicate(format: "label == %@", "Remove Spray bottle"))
      .firstMatch
    XCTAssertTrue(remove.waitForExistence(timeout: 3))
    remove.tap()
    XCTAssertFalse(
      entry(app, "Spray bottle").waitForExistence(timeout: 2),
      "Removing the sub-item should drop it from the row"
    )

    // Re-add, then move the item to the read-only Not bringing group.
    addSubItem(app, text: "Goggles")
    XCTAssertTrue(entry(app, "Goggles").waitForExistence(timeout: 5))

    let skip = app.buttons.matching(NSPredicate(format: "label == %@", "Skip")).firstMatch
    XCTAssertTrue(skip.waitForExistence(timeout: 3))
    skip.tap()
    let restore = app.buttons.matching(NSPredicate(format: "label == %@", "Restore")).firstMatch
    XCTAssertTrue(restore.waitForExistence(timeout: 3))

    assertReadOnlyDisplay(app)
  }

  /// On the read-only Not-bringing row the sub-item still displays but neither
  /// the add affordance nor the per-entry remove control appears (Req 5.2).
  @MainActor
  private func assertReadOnlyDisplay(_ app: XCUIApplication) {
    XCTAssertTrue(
      entry(app, "Goggles").waitForExistence(timeout: 3),
      "A read-only row must still display its sub-items (Req 5.2)"
    )
    XCTAssertFalse(
      app.descendants(matching: .any)
        .matching(identifier: "packingSubItems.addButton")
        .firstMatch.exists,
      "Read-only rows must not present the add affordance (Req 5.2)"
    )
    XCTAssertFalse(
      app.buttons.matching(NSPredicate(format: "label == %@", "Remove Goggles"))
        .firstMatch.exists,
      "Read-only rows must not present a remove control (Req 5.2)"
    )
  }
}
