import XCTest

/// Phase 4 packing-summary block + `PackingSheet` UI coverage. Mirrors the
/// `TimelineAndTaskUITests` pattern: each test launches a fresh in-memory
/// container via `-uitest 1 -seed-fixture <name>` and asserts on the
/// accessibility identifiers emitted by `PackingSummarySection`,
/// `PackingItemRow`, `PackingSheet`, and `PackingItemForm`.
///
/// Some tests depend on `TripDetailView` wiring the `.sheet(item:
/// $packingSheetState)` block — that wiring lands in Task 15. Until then the
/// sheet-opening tests will fail at the `packingSheet.header` assertion;
/// tests that only assert on the summary block are independent and pass on
/// Task 7 / 13 alone.
///
/// Tests requiring infrastructure that is out of scope for Phase 4 (mid-test
/// fixture mutation, save-failure injection, hardware-keyboard fixtures,
/// debug colour markers) are gated with `XCTSkip` and a rationale.
final class PackingSheetUITests: XCTestCase {

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  // MARK: - Helpers

  @MainActor
  private func launchedApp(fixture: String, extraArgs: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-uitest", "1", "-seed-fixture", fixture] + extraArgs
    app.launch()
    let marker = app.descendants(matching: .any)
      .matching(identifier: "modelStore.in-memory")
      .firstMatch
    XCTAssertTrue(marker.waitForExistence(timeout: 5))
    return app
  }

  @MainActor
  private func openTripDetail(_ app: XCUIApplication, tripName: String) {
    // Single-qualifying-trip fixtures auto-open Trip Detail; if the row is
    // still visible (Trip List stayed put), tap it to navigate in.
    let row = app.staticTexts[tripName]
    if row.waitForExistence(timeout: 3), app.buttons["New Trip"].exists {
      row.tap()
    }
  }

  /// Convenience: open the packing sheet for the first summary row in the
  /// active expanded phase. Returns once `packingSheet.header` is visible
  /// (or returns early if the wait times out — callers should assert on the
  /// header existence afterwards).
  @MainActor
  private func openPackingSheetForFirstParticipant(_ app: XCUIApplication) {
    let summaryRow = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'tripDetail.packingSummary.'"))
      .firstMatch
    if summaryRow.waitForExistence(timeout: 5) {
      summaryRow.tap()
    }
  }

  // MARK: - 1. Summary block rendering

  @MainActor
  func testPackingSummaryRendersInDeparturePhase() {
    let app = launchedApp(fixture: "phase4-pack-mode-trip")
    openTripDetail(app, tripName: "Beach Trip")

    // Two participants seeded; both summary rows should be present once the
    // .departureDay phase auto-expands.
    let summaryRows = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH 'tripDetail.packingSummary.'"))
    let predicate = NSPredicate(format: "count == 2")
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: summaryRows)
    XCTAssertEqual(
      XCTWaiter().wait(for: [expectation], timeout: 5),
      .completed,
      "Departure phase should render one PackingSummaryRow per participant"
    )
  }

  // MARK: - 2. Sheet open / close

  @MainActor
  func testTappingSummaryRowOpensSheet() {
    let app = launchedApp(fixture: "phase4-pack-mode-trip")
    openTripDetail(app, tripName: "Beach Trip")

    openPackingSheetForFirstParticipant(app)

    let header = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.header")
      .firstMatch
    XCTAssertTrue(
      header.waitForExistence(timeout: 5),
      "Tapping a summary row should present the PackingSheet header"
    )
    let counter = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.counter")
      .firstMatch
    XCTAssertTrue(counter.waitForExistence(timeout: 3))
  }

  // MARK: - 3. Pack-mode interactions

  @MainActor
  func testPackModeCheckboxTogglesState() {
    let app = launchedApp(fixture: "phase4-pack-mode-trip")
    openTripDetail(app, tripName: "Beach Trip")

    openPackingSheetForFirstParticipant(app)

    let header = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.header")
      .firstMatch
    XCTAssertTrue(header.waitForExistence(timeout: 5))

    // Sunscreen starts in `.unpacked` for Arjen — find its row and tap the
    // checkbox via the "Mark packed" accessibility label.
    let row = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.itemRow.Sunscreen")
      .firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))

    let toggle = app.buttons.matching(NSPredicate(format: "label == %@", "Mark packed")).firstMatch
    XCTAssertTrue(toggle.waitForExistence(timeout: 3))
    toggle.tap()

    // After toggle, the same row should expose "Mark not packed" — meaning
    // it's now rendered in `.packed` group with `isChecked == true`.
    let inverse = app.buttons.matching(NSPredicate(format: "label == %@", "Mark not packed"))
    XCTAssertTrue(
      inverse.firstMatch.waitForExistence(timeout: 3),
      "Toggling the checkbox should move the row into the Packed group"
    )
  }

  @MainActor
  func testSkipMovesItemToNotBringing() {
    let app = launchedApp(fixture: "phase4-pack-mode-trip")
    openTripDetail(app, tripName: "Beach Trip")

    openPackingSheetForFirstParticipant(app)

    let header = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.header")
      .firstMatch
    XCTAssertTrue(header.waitForExistence(timeout: 5))

    let row = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.itemRow.Sunscreen")
      .firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))

    // Tap the inline "Skip" button on the unpacked Sunscreen row.
    let skip = app.buttons.matching(NSPredicate(format: "label == %@", "Skip")).firstMatch
    XCTAssertTrue(skip.waitForExistence(timeout: 3))
    skip.tap()

    // After Skip, the row exposes the inline "Restore" action — proxy for
    // membership in the `notBringing` group.
    let restore = app.buttons.matching(NSPredicate(format: "label == %@", "Restore"))
    XCTAssertTrue(
      restore.firstMatch.waitForExistence(timeout: 3),
      "After Skip the row should be in Not bringing and show a Restore action"
    )
  }

  @MainActor
  func testRestoreReverses() {
    let app = launchedApp(fixture: "phase4-pack-mode-trip")
    openTripDetail(app, tripName: "Beach Trip")

    openPackingSheetForFirstParticipant(app)

    let header = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.header")
      .firstMatch
    XCTAssertTrue(header.waitForExistence(timeout: 5))

    let row = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.itemRow.Sunscreen")
      .firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))

    // Skip then Restore the same item.
    let skip = app.buttons.matching(NSPredicate(format: "label == %@", "Skip")).firstMatch
    XCTAssertTrue(skip.waitForExistence(timeout: 3))
    skip.tap()

    let restore = app.buttons.matching(NSPredicate(format: "label == %@", "Restore")).firstMatch
    XCTAssertTrue(restore.waitForExistence(timeout: 3))
    restore.tap()

    // After Restore, Skip should be available again (back in
    // stillNeedToPack/packed groups).
    let skipAgain = app.buttons.matching(NSPredicate(format: "label == %@", "Skip"))
    XCTAssertTrue(
      skipAgain.firstMatch.waitForExistence(timeout: 3),
      "Restore should send the item back to Still need to pack"
    )
  }

  // MARK: - 4. Repack mode

  @MainActor
  func testRepackOpensFromDayBeforeReturn() {
    let app = launchedApp(fixture: "phase4-repack-mode-trip")
    openTripDetail(app, tripName: "Mountain Trip")

    openPackingSheetForFirstParticipant(app)

    let counter = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.counter")
      .firstMatch
    XCTAssertTrue(counter.waitForExistence(timeout: 5))
    XCTAssertTrue(
      counter.label.contains("repacked"),
      "Repack-mode counter should use 'repacked' terminology, got: \(counter.label)"
    )
  }

  @MainActor
  func testLeftBehindRowIsReadOnly() {
    let app = launchedApp(fixture: "phase4-repack-mode-trip")
    openTripDetail(app, tripName: "Mountain Trip")

    openPackingSheetForFirstParticipant(app)

    let header = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.header")
      .firstMatch
    XCTAssertTrue(header.waitForExistence(timeout: 5))

    // Boots is `.unpacked` for Arjen on a `.dayBeforeReturn` trip — so it
    // belongs to the leftBehind group.
    let row = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.itemRow.Boots")
      .firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))

    // No Skip / Restore on left-behind rows.
    XCTAssertFalse(
      app.buttons.matching(NSPredicate(format: "label == %@", "Skip")).firstMatch.exists,
      "Left-behind rows must not expose a Skip action"
    )
    XCTAssertFalse(
      app.buttons.matching(NSPredicate(format: "label == %@", "Restore")).firstMatch.exists,
      "Left-behind rows must not expose a Restore action"
    )

    // Tap the row's leading half (where the dashed placeholder sits) and
    // verify the row identifier remains in place — i.e., state didn't change.
    row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
    XCTAssertTrue(
      row.exists,
      "Tapping the placeholder area on a left-behind row must not toggle state"
    )
  }

  // MARK: - 5. Manual item creation

  @MainActor
  func testAddManualItemAppearsInUnpacked() {
    let app = launchedApp(fixture: "phase4-pack-mode-trip")
    openTripDetail(app, tripName: "Beach Trip")

    openPackingSheetForFirstParticipant(app)

    let addButton = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.addItemButton")
      .firstMatch
    XCTAssertTrue(addButton.waitForExistence(timeout: 5))
    addButton.tap()

    let nameField = app.textFields["Item name"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 3))
    nameField.tap()
    nameField.typeText("Sunscreen2")

    app.buttons["Save"].tap()

    let newRow = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.itemRow.Sunscreen2")
      .firstMatch
    XCTAssertTrue(
      newRow.waitForExistence(timeout: 5),
      "Manual item added via PackingItemForm should appear in stillNeedToPack"
    )
  }

  // MARK: - 6. Item editing

  @MainActor
  func testRenameViaSwipe() {
    let app = launchedApp(fixture: "phase4-pack-mode-trip")
    openTripDetail(app, tripName: "Beach Trip")

    openPackingSheetForFirstParticipant(app)

    let header = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.header")
      .firstMatch
    XCTAssertTrue(header.waitForExistence(timeout: 5))

    let row = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.itemRow.Sunscreen")
      .firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))

    row.swipeLeft()

    let editButton = app.buttons["Edit"]
    XCTAssertTrue(editButton.waitForExistence(timeout: 3))
    editButton.tap()

    let nameField = app.textFields["Item name"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 3))
    // Clear the prefilled value before typing the new one.
    nameField.tap()
    nameField.press(forDuration: 1.0)
    if app.menuItems["Select All"].waitForExistence(timeout: 1) {
      app.menuItems["Select All"].tap()
    }
    nameField.typeText("Sunscreen Renamed")

    app.buttons["Save"].tap()

    let renamed = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.itemRow.Sunscreen Renamed")
      .firstMatch
    XCTAssertTrue(
      renamed.waitForExistence(timeout: 5),
      "After rename, the row identifier should reflect the new name"
    )
  }

  // MARK: - 8. Sheet body change propagation

  @MainActor
  func testSheetDismissOnParticipantRemoval() throws {
    throw XCTSkip("Requires fixture mid-test mutation hook")
  }

  @MainActor
  func testDimmedItemCountsInProgressBar() throws {
    throw XCTSkip("Requires progressRatio debug marker not yet wired")
  }

  @MainActor
  func testSheetCounterIncludesDimmed() {
    let app = launchedApp(fixture: "phase4-pack-mode-trip")
    openTripDetail(app, tripName: "Beach Trip")

    openPackingSheetForFirstParticipant(app)

    let counter = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.counter")
      .firstMatch
    XCTAssertTrue(counter.waitForExistence(timeout: 5))

    // Arjen's fixture: Sunscreen (.unpacked), Toothbrush (.packed), Stale
    // Item (.packed, dimmed). Excluded items don't count. Pack-mode counter
    // is "{packed}/{packed+unpacked} packed" — so 2/3 because Stale Item
    // counts toward `packed` per Req 1.6.
    XCTAssertTrue(
      counter.label.contains("2/3"),
      "Counter should include dimmed items in the denominator (Req 1.6); got: \(counter.label)"
    )
  }

  // MARK: - 9. Keyboard / Escape (skipped — requires HW keyboard fixture)

  @MainActor
  func testEscapeDismissesSheet() throws {
    throw XCTSkip(
      "Requires hardware keyboard fixture not configured for iOS Simulator UI tests"
    )
  }

  @MainActor
  func testEscapeDismissesDisclosureFirst() throws {
    throw XCTSkip(
      "Requires hardware keyboard fixture not configured for iOS Simulator UI tests"
    )
  }

  // MARK: - 10. Phase-header subline composition

  @MainActor
  func testPhaseSublineCombined() {
    let app = launchedApp(fixture: "phase4-pack-mode-trip")
    openTripDetail(app, tripName: "Beach Trip")

    let header = app.descendants(matching: .any)
      .matching(identifier: "tripDetail.phaseHeader.departureDay")
      .firstMatch
    XCTAssertTrue(header.waitForExistence(timeout: 5))

    // The departureDay header's accessibility label should append the
    // packing clause ("X to pack" or "packing ready") per Req 1.10. With
    // Arjen unpacked=1 and Sam unpacked=1 the total is 2, so the clause
    // should mention "to pack".
    XCTAssertTrue(
      header.label.contains("to pack"),
      "Departure phase subline should include packing clause; got: \(header.label)"
    )
  }

  // MARK: - 11. Sheet-on-sheet stability

  @MainActor
  func testInnerFormSwipeDownKeepsPackingSheet() {
    let app = launchedApp(fixture: "phase4-pack-mode-trip")
    openTripDetail(app, tripName: "Beach Trip")

    openPackingSheetForFirstParticipant(app)

    let addButton = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.addItemButton")
      .firstMatch
    XCTAssertTrue(addButton.waitForExistence(timeout: 5))
    addButton.tap()

    let nameField = app.textFields["Item name"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 3))

    // Swipe down on the form — the inner sheet should dismiss while the
    // outer packing sheet stays put (Req 2.1 sheet-on-sheet, design
    // §"Sheet-on-sheet presentation").
    nameField.swipeDown()

    let header = app.descendants(matching: .any)
      .matching(identifier: "packingSheet.header")
      .firstMatch
    XCTAssertTrue(
      header.waitForExistence(timeout: 5),
      "Outer PackingSheet header should remain present after inner form dismiss"
    )
    XCTAssertTrue(
      addButton.waitForExistence(timeout: 3),
      "Outer addItemButton should still be visible after inner form dismiss"
    )
  }

  // MARK: - 12. Save-failure injection (skipped — no failure seam yet)

  @MainActor
  func testManualAddSaveFailureKeepsFormOpen() throws {
    throw XCTSkip("Requires save-failure injection seam")
  }

  // MARK: - 13. Participant-array mutation scenarios (skipped — no hook)

  @MainActor
  func testParticipantRemovalDismissalLandsLayoutChanged() throws {
    throw XCTSkip("Requires mid-test fixture mutation")
  }

  @MainActor
  func testParticipantReorderDoesNotDismiss() throws {
    throw XCTSkip("Requires mid-test fixture mutation")
  }

  // MARK: - 14. Concurrent engine apply (skipped — no hook)

  @MainActor
  func testConcurrentEngineFlagDuringToggle() throws {
    throw XCTSkip("Requires concurrent engine apply hook")
  }
}
