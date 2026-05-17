import CloudKit
import Foundation
import UIKit

/// Phase 5 — splits an inbound `CKNotification` between the private and
/// shared `CKSyncEngine` instances managed by `TripSyncEngine`
/// (design § "Push notification routing"). Owned by `AppDelegate`
/// but lives standalone so the policy is exercisable in isolation.
@MainActor
final class RemoteNotificationRouter {
  let fetcher: RemoteNotificationFetcher

  init(fetcher: RemoteNotificationFetcher) {
    self.fetcher = fetcher
  }

  /// Route a notification's `databaseScope` to the matching engine.
  /// Returns the `UIBackgroundFetchResult` to hand back to UIKit's
  /// `fetchCompletionHandler`.
  func route(
    databaseScope: CKDatabase.Scope
  ) async -> UIBackgroundFetchResult {
    switch databaseScope {
    case .private, .shared:
      do {
        try await fetcher.fetchChanges(scope: databaseScope)
        return .newData
      } catch {
        return .failed
      }
    case .public:
      return .noData
    @unknown default:
      return .noData
    }
  }
}

/// Phase 5 — test seam for the engine-fetch operation invoked by
/// `RemoteNotificationRouter`. Production wires this to
/// `TripSyncEngine.{private,shared}Engine.fetchChanges()`; tests use a
/// recording fake.
@MainActor
protocol RemoteNotificationFetcher: AnyObject {
  func fetchChanges(scope: CKDatabase.Scope) async throws
}

/// Production fetcher that drives the right `CKSyncEngine` instance.
@MainActor
final class TripSyncEngineNotificationFetcher: RemoteNotificationFetcher {
  let syncEngine: TripSyncEngine

  init(syncEngine: TripSyncEngine) {
    self.syncEngine = syncEngine
  }

  func fetchChanges(scope: CKDatabase.Scope) async throws {
    let engine: CKSyncEngine?
    switch scope {
    case .private: engine = syncEngine.privateEngine
    case .shared: engine = syncEngine.sharedEngine
    default: return
    }
    // The engine is `nil` only when `TripSyncEngine.start()` hasn't run
    // (pre-MigrationGate launch path). Surfacing this as an error keeps
    // `RemoteNotificationRouter.route` from reporting `.newData` for a
    // fetch that never happened — UIKit would then mark the notification
    // handled and never re-deliver it.
    guard let engine else { throw NotificationFetcherError.engineUnavailable }
    try await engine.fetchChanges()
  }
}

enum NotificationFetcherError: Error {
  case engineUnavailable
}
