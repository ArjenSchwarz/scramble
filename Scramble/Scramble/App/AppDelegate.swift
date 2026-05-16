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

  /// Holds the SharingService + notification router. Stored as a
  /// `static` so SwiftUI can reach in from the `App` body without
  /// fighting the AppDelegateAdaptor lifecycle (which constructs the
  /// delegate on UIKit's terms).
  @MainActor
  struct Environment {
    let sharingService: SharingService
    let notificationRouter: RemoteNotificationRouter
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
  /// Falls back to `.public` (treated as "unhandled") when the
  /// notification is malformed.
  @MainActor
  static func databaseScope(from userInfo: [AnyHashable: Any]) -> CKDatabase.Scope {
    guard
      let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
    else { return .public }
    return notification.databaseScope
  }
}
