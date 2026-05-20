import CloudKit
import Foundation
import SwiftUI
import UIKit
import os

/// Phase 5 — UIKit bridge for share-acceptance and silent-push routing.
///
/// SwiftUI's scene modifiers do not cover share acceptance
/// (`userDidAcceptCloudKitShareWith`) or the
/// `didReceiveRemoteNotification` callback, so we hop through
/// `UIApplicationDelegateAdaptor`. The actual policy lives in:
///
/// - `SharingService.acceptShare` for the share-acceptance path
/// - `RemoteNotificationRouter` for the silent-push fan-out
///
/// Both are injected via `AppDelegate.environment` so tests can stand the
/// delegate up against fakes. Production wires the slots from
/// `ScrambleApp.init`.
final class AppDelegate: NSObject, UIApplicationDelegate {

  /// Holds the SharingService + notification routers. Stored as a
  /// `static` so SwiftUI can reach in from the `App` body without
  /// fighting the AppDelegateAdaptor lifecycle (which constructs the
  /// delegate on UIKit's terms).
  ///
  /// Two notification routers live here:
  /// - `notificationRouter` (Phase 5) — silent-push fan-out to the
  ///   sync engines via `RemoteNotificationRouter`.
  /// - `activationRouter` (Phase 6) — `UNUserNotificationCenterDelegate`
  ///   for the local activation notifications. Holds the 1-slot
  ///   `pendingRoute` that `RootView` drains.
  @MainActor
  struct Environment {
    let sharingService: SharingService
    let notificationRouter: RemoteNotificationRouter
    let activationRouter: NotificationRouter
    let notificationsService: NotificationsService
  }

  @MainActor
  static var environment: Environment?

  /// Share-acceptance entry point
  /// (Req [6.1](../../../specs/phase-5-cloudkit-sharing/requirements.md#6.1)).
  func application(
    _ application: UIApplication,
    userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
  ) {
    Task { @MainActor in
      guard let service = Self.environment?.sharingService else {
        modelLogger.error("[AppDelegate] share acceptance with no SharingService wired")
        return
      }
      do {
        _ = try await service.acceptShare(metadata)
      } catch {
        modelLogger.error(
          "[AppDelegate] acceptShare failed: \(error.localizedDescription, privacy: .public)"
        )
      }
    }
  }

  /// Silent-push entry point. Routes the notification to the matching
  /// engine via `RemoteNotificationRouter`
  /// (Req [9.1](../../../specs/phase-5-cloudkit-sharing/requirements.md#9.1),
  /// [9.3](../../../specs/phase-5-cloudkit-sharing/requirements.md#9.3)).
  func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    let scope = Self.databaseScope(from: userInfo)
    Task { @MainActor in
      guard let router = Self.environment?.notificationRouter else {
        completionHandler(.noData)
        return
      }
      let result = await router.route(databaseScope: scope)
      completionHandler(result)
    }
  }

  /// Parse the database scope out of a CloudKit silent-push payload.
  /// `databaseScope` lives on the concrete `CKNotification` subclasses
  /// (`CKDatabaseNotification`, `CKRecordZoneNotification`,
  /// `CKQueryNotification`) rather than the base class, so we walk the
  /// subclass hierarchy and return `.public` (treated as "unhandled")
  /// when the notification is missing or unrecognised.
  @MainActor
  static func databaseScope(from userInfo: [AnyHashable: Any]) -> CKDatabase.Scope {
    guard
      let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
    else { return .public }
    if let db = notification as? CKDatabaseNotification {
      return db.databaseScope
    }
    if let zone = notification as? CKRecordZoneNotification {
      return zone.databaseScope
    }
    if let query = notification as? CKQueryNotification {
      return query.databaseScope
    }
    return .public
  }
}
