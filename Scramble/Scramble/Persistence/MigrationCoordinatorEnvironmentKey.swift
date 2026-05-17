import SwiftUI

/// Phase 5 — SwiftUI environment carrier for the
/// `ZoneMigrationCoordinator`. The Trip List's migration retry banner
/// reads this to hand a tap on a failed entry back to the coordinator's
/// `retry(tripID:)` entry point.
///
/// `nil` for previews and unit-test branches that don't stand up the
/// coordinator; the banner short-circuits when the value is unavailable.
private struct ZoneMigrationCoordinatorKey: EnvironmentKey {
  @MainActor
  static var defaultValue: ZoneMigrationCoordinator? { nil }
}

extension EnvironmentValues {
  var zoneMigrationCoordinator: ZoneMigrationCoordinator? {
    get { self[ZoneMigrationCoordinatorKey.self] }
    set { self[ZoneMigrationCoordinatorKey.self] = newValue }
  }
}
