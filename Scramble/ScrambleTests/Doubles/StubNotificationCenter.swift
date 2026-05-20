import Foundation
import UserNotifications

@testable import Scramble

/// Phase 6 — recording stub for `NotificationCenterProtocol`. Used by
/// `NotificationsServiceTests` to exercise the service against
/// deterministic auth state and an explicit pending list.
@MainActor
final class StubNotificationCenter: NotificationCenterProtocol {

  // MARK: - Recorded calls

  struct Snapshot: Equatable {
    var requestedAuthorization: [UNAuthorizationOptions] = []
    var authReads: Int = 0
    var added: [UNNotificationRequest] = []
    var pendingListReads: Int = 0
    var removedPending: [[String]] = []
    var removedDelivered: [[String]] = []
    var setDelegateCalls: Int = 0
  }

  private(set) var snapshot = Snapshot()

  // MARK: - Stubs

  var stubbedAuthorizationStatus: UNAuthorizationStatus = .notDetermined
  var authorizationGrantResult: Bool = false
  var pending: [UNNotificationRequest] = []
  var weakDelegate: UNUserNotificationCenterDelegate?

  /// Force the next `add(_:)` to throw a specific error. Cleared
  /// after one call.
  var nextAddError: Error?

  // MARK: - NotificationCenterProtocol

  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
    snapshot.requestedAuthorization.append(options)
    if authorizationGrantResult {
      stubbedAuthorizationStatus = .authorized
    } else {
      stubbedAuthorizationStatus = .denied
    }
    return authorizationGrantResult
  }

  func authorizationStatus() async -> UNAuthorizationStatus {
    snapshot.authReads += 1
    return stubbedAuthorizationStatus
  }

  func add(_ request: UNNotificationRequest) async throws {
    if let error = nextAddError {
      nextAddError = nil
      throw error
    }
    snapshot.added.append(request)
    pending.removeAll { $0.identifier == request.identifier }
    pending.append(request)
  }

  func pendingNotificationRequests() async -> [UNNotificationRequest] {
    snapshot.pendingListReads += 1
    return pending
  }

  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
    snapshot.removedPending.append(identifiers)
    pending.removeAll { identifiers.contains($0.identifier) }
  }

  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
    snapshot.removedDelivered.append(identifiers)
  }

  func setDelegate(_ delegate: UNUserNotificationCenterDelegate?) {
    snapshot.setDelegateCalls += 1
    weakDelegate = delegate
  }
}
