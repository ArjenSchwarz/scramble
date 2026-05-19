import Foundation
import UserNotifications

/// Phase 6 — abstraction over `UNUserNotificationCenter` so the
/// notifications service can be unit-tested against a stub recording
/// every call rather than the real OS notification center.
///
/// Methods mirror the subset of `UNUserNotificationCenter` the service
/// uses. `authorizationStatus()` returns the bare enum instead of the
/// full `UNNotificationSettings` because `UNNotificationSettings` has no
/// public initializer — keeping the protocol minimal lets tests provide
/// a recording stub without resorting to keyed-archiver synthesis.
@MainActor
protocol NotificationCenterProtocol: AnyObject {
  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
  func authorizationStatus() async -> UNAuthorizationStatus
  func add(_ request: UNNotificationRequest) async throws
  func pendingNotificationRequests() async -> [UNNotificationRequest]
  func removePendingNotificationRequests(withIdentifiers: [String])
  func removeDeliveredNotifications(withIdentifiers: [String])
  func setDelegate(_ delegate: UNUserNotificationCenterDelegate?)
}

extension UNUserNotificationCenter: NotificationCenterProtocol {
  func authorizationStatus() async -> UNAuthorizationStatus {
    await self.notificationSettings().authorizationStatus
  }

  func setDelegate(_ delegate: UNUserNotificationCenterDelegate?) {
    self.delegate = delegate
  }
}
