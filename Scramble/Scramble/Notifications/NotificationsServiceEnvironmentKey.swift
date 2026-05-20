import SwiftUI

/// Phase 6 — environment key exposing the app-wide `NotificationsService`
/// to trip-domain views (TripListView for the auth-gate call,
/// TripDetailView for the "Open Settings" affordance).
///
/// The default fallback is `nil`: previews and tests that don't wire a
/// service receive `nil` and the calling view must guard accordingly.
private struct NotificationsServiceKey: EnvironmentKey {
  static let defaultValue: NotificationsService? = nil
}

private struct ActivationRouterKey: EnvironmentKey {
  static let defaultValue: NotificationRouter? = nil
}

private struct NotificationAuthStatusKey: EnvironmentKey {
  static let defaultValue: NotificationAuthStatusHolder? = nil
}

extension EnvironmentValues {
  var notificationsService: NotificationsService? {
    get { self[NotificationsServiceKey.self] }
    set { self[NotificationsServiceKey.self] = newValue }
  }

  var activationRouter: NotificationRouter? {
    get { self[ActivationRouterKey.self] }
    set { self[ActivationRouterKey.self] = newValue }
  }

  /// `@Observable` mirror of `NotificationsService.authStatus`. Views
  /// reading this re-render when the status flips; reading
  /// `notificationsService?.authStatus` directly does NOT subscribe to
  /// changes (Decision 15).
  var notificationAuthStatus: NotificationAuthStatusHolder? {
    get { self[NotificationAuthStatusKey.self] }
    set { self[NotificationAuthStatusKey.self] = newValue }
  }
}
