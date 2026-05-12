import XCTest

/// AC 8.2 — when a `Person` owns a `MasterPackingItem`, the delete affordance
/// in `TripEditorView`'s person picker SHALL be blocked with an alert listing
/// the master-list reference. Phase 1's existing `PersonDeleteBlocker` helper
/// already handles both trip-level and master-level references (see Phase 1
/// AC 9.7 / Decision 16); this test proves the master-level path surfaces
/// correctly in the UI when a Phase 2 master-list reference exists.
final class PersonDeletionGuardUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testPersonOwningMasterPackingItemCannotBeDeleted() {
    let app = XCUIApplication()
    app.launchArguments = ["-uitest", "1", "-seed-fixture", "person-with-master-packing-only"]
    app.launch()

    let marker = app.descendants(matching: .any)
      .matching(identifier: "modelStore.in-memory")
      .firstMatch
    XCTAssertTrue(marker.waitForExistence(timeout: 5))

    // Open the seeded trip ("Sample Trip"), then the actions menu → Edit
    // sheet, then long-press the participant row to surface the destructive
    // context menu.
    let row = app.staticTexts["Sample Trip"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.tap()

    let actionsButton = app.buttons["Trip actions"]
    XCTAssertTrue(actionsButton.waitForExistence(timeout: 3))
    actionsButton.tap()
    app.buttons["Edit"].tap()

    // The People section is at the bottom of the Form. Swipe to bring it
    // into the accessibility hierarchy.
    XCTAssertTrue(app.navigationBars["Edit Trip"].waitForExistence(timeout: 3))
    for _ in 0..<5 {
      app.swipeUp()
    }

    // Long-press the Person row to surface the destructive context menu.
    let personRow = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "Alex")
    ).firstMatch
    XCTAssertTrue(personRow.waitForExistence(timeout: 3))
    personRow.press(forDuration: 1.0)

    let deleteAction = app.buttons["Delete person from app…"]
    XCTAssertTrue(deleteAction.waitForExistence(timeout: 3))
    deleteAction.tap()

    // The blocker alert appears (NOT the destructive confirmation dialog,
    // which is reached only when there are no references).
    let blockerTitle = app.alerts["Can't delete this person"]
    XCTAssertTrue(
      blockerTitle.waitForExistence(timeout: 3),
      "Blocker alert should appear because Alex still owns a MasterPackingItem"
    )

    // The alert message must mention the master packing item.
    let messagePredicate = NSPredicate(
      format: "label CONTAINS %@", "Master packing items"
    )
    let messageElement = blockerTitle.staticTexts.matching(messagePredicate).firstMatch
    XCTAssertTrue(
      messageElement.exists,
      "Blocker alert must list 'Master packing items:' so the user sees the master-list reference"
    )
  }
}
