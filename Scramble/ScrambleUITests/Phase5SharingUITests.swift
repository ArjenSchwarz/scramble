import XCTest

/// Phase 5 — UI coverage for the Trip Detail Share affordance and
/// Participants section
/// (Reqs [5.1](../../specs/phase-5-cloudkit-sharing/requirements.md#5.1),
/// [7.1](../../specs/phase-5-cloudkit-sharing/requirements.md#7.1),
/// [7.2](../../specs/phase-5-cloudkit-sharing/requirements.md#7.2),
/// [7.4](../../specs/phase-5-cloudkit-sharing/requirements.md#7.4),
/// [7.7](../../specs/phase-5-cloudkit-sharing/requirements.md#7.7)).
///
/// Fixtures wire `UITestSharingService` so the share-affordance visibility
/// and the participants list are deterministic without hitting CloudKit.
final class Phase5SharingUITests: XCTestCase {

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

  // MARK: - Share affordance visibility (Req 5.1)

  @MainActor
  func testShareButtonVisibleForOwner() {
    let app = launchedApp(fixture: "phase5-shared-trip-owner")
    openTrip(named: "Shared Trip", in: app)
    let shareButton = app.buttons["tripDetail.shareButton"]
    XCTAssertTrue(
      shareButton.waitForExistence(timeout: 3),
      "Owner of a shared trip should see the Share toolbar button"
    )
  }

  @MainActor
  func testShareButtonHiddenForParticipant() {
    let app = launchedApp(fixture: "phase5-shared-trip-participant")
    openTrip(named: "Their Trip", in: app)
    // The trip actions menu still renders; assert specifically that the
    // share affordance does not.
    XCTAssertTrue(
      app.buttons["Trip actions"].waitForExistence(timeout: 3),
      "Trip actions menu should be present so we can prove the screen rendered"
    )
    XCTAssertFalse(
      app.buttons["tripDetail.shareButton"].exists,
      "Participant on a shared trip should NOT see the Share toolbar button"
    )
  }

  // MARK: - Participants section (Reqs 7.1, 7.2)

  @MainActor
  func testParticipantsSectionDistinguishesPendingFromAccepted() {
    let app = launchedApp(fixture: "phase5-shared-trip-owner")
    openTrip(named: "Shared Trip", in: app)

    let heading = app.descendants(matching: .any)
      .matching(identifier: "tripDetail.participantsSection.heading")
      .firstMatch
    XCTAssertTrue(
      heading.waitForExistence(timeout: 5),
      "Participants section heading should render below the trip header"
    )

    // The acceptance state strings render as their own Text elements with
    // stable identifiers. Existence proves the pending vs accepted
    // distinction made it into the layout; we don't tie the assertion to
    // the rolled-up label string because Buttons combine descendants.
    let acceptedState = app.descendants(matching: .any)
      .matching(identifier: "tripDetail.participantsSection.state.Bob")
      .firstMatch
    XCTAssertTrue(
      acceptedState.waitForExistence(timeout: 3),
      "Accepted participant row should render its acceptance state element"
    )

    let pendingState = app.descendants(matching: .any)
      .matching(identifier: "tripDetail.participantsSection.state.alice@example.com")
      .firstMatch
    XCTAssertTrue(
      pendingState.waitForExistence(timeout: 3),
      "Pending invitee row should render its acceptance state element"
    )

    // And the actual strings are visible somewhere in the section so the
    // user can read pending vs accepted.
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Accepted'"))
        .firstMatch.exists,
      "Accepted state text should be visible"
    )
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Pending invitation'"))
        .firstMatch.exists,
      "Pending invitation state text should be visible"
    )
  }

  @MainActor
  func testParticipantsSectionDisplayNameFallbackChain() {
    let app = launchedApp(fixture: "phase5-shared-trip-owner")
    openTrip(named: "Shared Trip", in: app)
    // Fixture seeds three participants: "You" (display name), "Bob"
    // (display name), "alice@example.com" (email fallback). All three
    // should render with their resolved fallback string.
    XCTAssertTrue(
      app.staticTexts["tripDetail.participantsSection.row.You"]
        .waitForExistence(timeout: 3),
      "Display-name fallback should resolve the current user as 'You'"
    )
    XCTAssertTrue(
      app.staticTexts["tripDetail.participantsSection.row.Bob"].exists,
      "Display-name fallback should resolve 'Bob'"
    )
    XCTAssertTrue(
      app.staticTexts[
        "tripDetail.participantsSection.row.alice@example.com"
      ].exists,
      "Display-name fallback should drop down to email when no display name"
    )
  }

  // MARK: - Participants section read-only for participants (Req 7.4)

  @MainActor
  func testParticipantsSectionIsReadOnlyForParticipants() {
    let app = launchedApp(fixture: "phase5-shared-trip-participant")
    openTrip(named: "Their Trip", in: app)

    let heading = app.descendants(matching: .any)
      .matching(identifier: "tripDetail.participantsSection.heading")
      .firstMatch
    XCTAssertTrue(
      heading.waitForExistence(timeout: 5),
      "Participants section should still render for participants"
    )
    // No tap-to-manage buttons exist on the participant side — only
    // owners get the manage-participants affordance.
    XCTAssertFalse(
      app.buttons["tripDetail.participantsSection.tap.Charlie"].exists,
      "Participant view should not expose tap-to-manage affordances"
    )
  }

  // MARK: - Owner-side tap opens manage sheet (Req 7.3)

  @MainActor
  func testOwnerSideTapPresentsManageParticipantsAffordance() {
    let app = launchedApp(fixture: "phase5-shared-trip-owner")
    openTrip(named: "Shared Trip", in: app)
    // First confirm the section rendered (participants resolve async),
    // then look for the tap target by accessibility label since the
    // Button rolls its descendants into a single element.
    let heading = app.descendants(matching: .any)
      .matching(identifier: "tripDetail.participantsSection.heading")
      .firstMatch
    XCTAssertTrue(
      heading.waitForExistence(timeout: 5),
      "Participants section should render so the tap target is reachable"
    )
    let tapTarget = app.buttons["Manage Bob"]
    XCTAssertTrue(
      tapTarget.exists,
      "Owner-side participant rows should expose a Manage <name> button"
    )
  }

  // MARK: - Helpers

  @MainActor
  private func openTrip(named name: String, in app: XCUIApplication) {
    let row = app.staticTexts[name]
    XCTAssertTrue(row.waitForExistence(timeout: 3), "Trip '\(name)' should appear in list")
    row.tap()
  }
}
