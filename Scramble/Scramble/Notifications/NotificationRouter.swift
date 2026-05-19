import Foundation
import UserNotifications

/// Phase 6 — the route a notification tap (or debug URL) asks the app to
/// navigate to (Req 5.1, 5.2).
struct ActivationRoute: Equatable, Sendable {
  let tripID: UUID
  let phase: Phase
}

/// Phase 6 — `UNUserNotificationCenterDelegate` implementation that
/// extracts the `(tripID, phase)` route from a notification tap's
/// `userInfo`, holds the single-slot pending route, and instructs iOS to
/// present the banner in the foreground (Req 1.3).
///
/// `pendingRoute` is the 1-slot queue from Req 5.2. A second tap before
/// the consumer has drained the slot overwrites the first — matching the
/// "last tap wins" expectation.
///
/// Two callers fill the slot:
/// 1. `userNotificationCenter(_:didReceive:)` — taps received at any
///    lifecycle stage. iOS buffers the cold-launch tap until the
///    delegate is installed.
/// 2. `enqueue(_:)` — used by `ScrambleApp`'s `onOpenURL` to drive the
///    debug `scramble://trip/<id>?phase=<raw>` path (Req 5.6) into the
///    same routing state machine.
@MainActor
@Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {

  /// userInfo keys carried in every activation notification.
  static let userInfoTripIDKey = "tripID"
  static let userInfoPhaseKey = "phase"

  private(set) var pendingRoute: ActivationRoute?

  /// Atomic read + clear. The routing consumer calls this exactly once
  /// per route at the start of `.navigating` so subsequent reads return
  /// `nil` even if the consumer is re-driven by a SwiftUI re-render.
  func consumeRoute() -> ActivationRoute? {
    let route = pendingRoute
    pendingRoute = nil
    return route
  }

  /// Public seam for the URL-based path (Req 5.6) and for tests.
  func enqueue(_ route: ActivationRoute) {
    pendingRoute = route
  }

  /// Parse a `scramble://trip/<UUID>?phase=<raw>` URL into an
  /// `ActivationRoute`. Returns `nil` for any URL that does not match
  /// the expected shape so the debug seam can fail-fast without
  /// touching navigation state.
  static func route(from url: URL) -> ActivationRoute? {
    guard url.scheme == "scramble" else { return nil }
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    guard let host = url.host, host == "trip" else { return nil }
    // Path is `/<UUID>` — strip the leading slash.
    let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard let tripID = UUID(uuidString: path) else { return nil }
    let phaseRaw =
      components?.queryItems?.first(where: { $0.name == "phase" })?.value ?? ""
    guard let phase = Phase(rawValue: phaseRaw) else { return nil }
    return ActivationRoute(tripID: tripID, phase: phase)
  }

  // MARK: - UNUserNotificationCenterDelegate

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let userInfo = response.notification.request.content.userInfo
    if let route = Self.route(from: userInfo) {
      pendingRoute = route
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }

  /// Extract a route from a notification's `userInfo` dictionary. Public
  /// so tests can exercise the parser independently of the delegate
  /// callback path.
  static func route(from userInfo: [AnyHashable: Any]) -> ActivationRoute? {
    guard
      let tripRaw = userInfo[userInfoTripIDKey] as? String,
      let phaseRaw = userInfo[userInfoPhaseKey] as? String,
      let tripID = UUID(uuidString: tripRaw),
      let phase = Phase(rawValue: phaseRaw)
    else { return nil }
    return ActivationRoute(tripID: tripID, phase: phase)
  }
}
