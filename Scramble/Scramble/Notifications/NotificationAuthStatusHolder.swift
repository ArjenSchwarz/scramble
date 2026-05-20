import UserNotifications

/// Phase 6 — `@Observable` mirror of `NotificationsService.authStatus`
/// so SwiftUI views can subscribe and re-render reactively when the
/// status flips.
///
/// `NotificationsService` itself cannot be `@Observable` because marking
/// it `@Observable` while it owns a SwiftData `ModelContext`-returning
/// closure crashes SwiftUI's AttributeGraph layout-descriptor traversal
/// under Swift Testing's parameter machinery (Decision 15). The holder
/// is a tiny one-property class with no SwiftData touchpoints, so the
/// macro is safe on it.
///
/// The service writes to `authStatus` from `didSet` on its own
/// `private(set) var authStatus`; views read `authStatusHolder.authStatus`
/// via `@Environment(\.notificationAuthStatus)`.
@MainActor
@Observable
final class NotificationAuthStatusHolder {
  var authStatus: UNAuthorizationStatus = .notDetermined
}
