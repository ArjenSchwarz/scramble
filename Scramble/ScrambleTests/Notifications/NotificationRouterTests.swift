import Foundation
import Testing
import UserNotifications

@testable import Scramble

/// Phase 6 — `NotificationRouter` coverage (Reqs 1.3, 5.1, 5.2, 5.6).
@Suite("NotificationRouter")
@MainActor
struct NotificationRouterTests {

  // MARK: - consumeRoute is atomic read + clear

  @Test("consumeRoute returns the route then clears pendingRoute")
  func consumeIsAtomic() {
    let router = NotificationRouter()
    let route = ActivationRoute(tripID: UUID(), phase: .dayBefore)
    router.enqueue(route)
    #expect(router.pendingRoute == route)
    let consumed = router.consumeRoute()
    #expect(consumed == route)
    #expect(router.pendingRoute == nil)
    // Second consume returns nil.
    #expect(router.consumeRoute() == nil)
  }

  // MARK: - 1-slot queue (last tap wins)

  @Test("enqueue overwrites a prior unconsumed route")
  func lastWriteWins() {
    let router = NotificationRouter()
    let first = ActivationRoute(tripID: UUID(), phase: .dayBefore)
    let second = ActivationRoute(tripID: UUID(), phase: .returnDay)
    router.enqueue(first)
    router.enqueue(second)
    #expect(router.pendingRoute == second)
  }

  // MARK: - userInfo extraction

  @Test("route(from userInfo:) returns the embedded (tripID, phase)")
  func userInfoExtraction() {
    let tripID = UUID()
    let userInfo: [AnyHashable: Any] = [
      NotificationRouter.userInfoTripIDKey: tripID.uuidString,
      NotificationRouter.userInfoPhaseKey: Phase.dayBeforeReturn.rawValue,
    ]
    let route = NotificationRouter.route(from: userInfo)
    #expect(route?.tripID == tripID)
    #expect(route?.phase == .dayBeforeReturn)
  }

  struct MalformedPayload: Sendable {
    let label: String
    let tripID: String?
    let phase: String?
  }

  @Test(
    "route(from userInfo:) returns nil for malformed payloads",
    arguments: [
      MalformedPayload(label: "empty", tripID: nil, phase: nil),
      MalformedPayload(label: "bad-uuid", tripID: "not-a-uuid", phase: "dayBefore"),
      MalformedPayload(label: "bad-phase", tripID: UUID().uuidString, phase: "notAPhase"),
      MalformedPayload(label: "missing-phase", tripID: UUID().uuidString, phase: nil),
      MalformedPayload(label: "missing-trip", tripID: nil, phase: "dayBefore"),
    ]
  )
  func userInfoMalformed(payload: MalformedPayload) {
    var userInfo: [AnyHashable: Any] = [:]
    if let trip = payload.tripID {
      userInfo[NotificationRouter.userInfoTripIDKey] = trip
    }
    if let phase = payload.phase {
      userInfo[NotificationRouter.userInfoPhaseKey] = phase
    }
    #expect(NotificationRouter.route(from: userInfo) == nil)
  }

  // MARK: - URL parsing (Req 5.6)

  @Test("scramble:// URL parses into the same ActivationRoute")
  func urlParsing() throws {
    let tripID = UUID()
    let url = try #require(URL(string: "scramble://trip/\(tripID.uuidString)?phase=dayBefore"))
    let route = NotificationRouter.route(from: url)
    #expect(route?.tripID == tripID)
    #expect(route?.phase == .dayBefore)
  }

  @Test(
    "Malformed scramble:// URLs return nil",
    arguments: [
      "scramble://trip/?phase=dayBefore",
      "scramble://trip/not-a-uuid?phase=dayBefore",
      "scramble://trip/\(UUID().uuidString)",
      "scramble://other/path?phase=dayBefore",
      "https://example.com/trip/\(UUID().uuidString)?phase=dayBefore",
      "scramble://trip/\(UUID().uuidString)?phase=notAPhase",
    ]
  )
  func urlMalformed(rawURL: String) throws {
    let url = try #require(URL(string: rawURL))
    #expect(NotificationRouter.route(from: url) == nil)
  }

  // MARK: - Foreground presentation (Req 1.3)

  // Note: invoking `userNotificationCenter(_:willPresent:)` requires a
  // `UNNotification` which has no public initializer, so this aspect is
  // verified by reading the delegate's implementation directly. The
  // expected options are documented on `NotificationRouter`.
}
