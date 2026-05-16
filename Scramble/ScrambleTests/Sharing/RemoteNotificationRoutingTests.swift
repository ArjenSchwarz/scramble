import CloudKit
import Foundation
import Testing

@testable import Scramble

/// Phase 5 — remote-notification routing
/// (Req [9.1](../../../specs/phase-5-cloudkit-sharing/requirements.md#9.1),
/// [9.3](../../../specs/phase-5-cloudkit-sharing/requirements.md#9.3),
/// design § "Push notification routing").
///
/// `AppDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`
/// branches on the notification's `databaseScope` and calls
/// `fetchChanges()` on the matching `CKSyncEngine`. The routing logic
/// lives in `RemoteNotificationRouter` so the policy can be exercised
/// without standing up a `UIApplication`.
@Suite("RemoteNotificationRouting", .serialized)
@MainActor
struct RemoteNotificationRoutingTests {

  @Test("A .private database scope routes to the private engine fetch")
  func privateScopeRoutesToPrivateEngine() async throws {
    let fetcher = RecordingFetcher()
    let router = RemoteNotificationRouter(fetcher: fetcher)

    let result = await router.route(databaseScope: .private)

    #expect(fetcher.scopes == [.private])
    #expect(result == .newData)
  }

  @Test("A .shared database scope routes to the shared engine fetch")
  func sharedScopeRoutesToSharedEngine() async throws {
    let fetcher = RecordingFetcher()
    let router = RemoteNotificationRouter(fetcher: fetcher)

    let result = await router.route(databaseScope: .shared)

    #expect(fetcher.scopes == [.shared])
    #expect(result == .newData)
  }

  @Test("Unknown / unhandled scopes return .noData and do not fetch")
  func unhandledScopeReturnsNoData() async throws {
    let fetcher = RecordingFetcher()
    let router = RemoteNotificationRouter(fetcher: fetcher)

    let result = await router.route(databaseScope: .public)

    #expect(fetcher.scopes.isEmpty)
    #expect(result == .noData)
  }

  @Test("Fetcher throwing surfaces as .failed without crashing the routing path")
  func fetcherFailureSurfacesAsFailed() async throws {
    let fetcher = RecordingFetcher()
    fetcher.shouldThrow = true
    let router = RemoteNotificationRouter(fetcher: fetcher)

    let result = await router.route(databaseScope: .private)

    #expect(result == .failed)
  }
}

@MainActor
final class RecordingFetcher: RemoteNotificationFetcher {
  private(set) var scopes: [CKDatabase.Scope] = []
  var shouldThrow: Bool = false

  func fetchChanges(scope: CKDatabase.Scope) async throws {
    scopes.append(scope)
    if shouldThrow {
      throw FakeFetcherError.injected
    }
  }
}

enum FakeFetcherError: Error { case injected }
