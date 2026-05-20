import Foundation
import Testing
import UserNotifications

@testable import Scramble

/// Phase 6 — sanity coverage for the recording stub used by the service
/// tests. Ensures the stub's contract holds: records every call, lets
/// tests force auth flips, and accurately reflects pending state across
/// `add` / `remove` sequences.
@Suite("StubNotificationCenter")
@MainActor
struct StubNotificationCenterTests {

  @Test("requestAuthorization records the options and flips status to denied/authorized")
  func authFlowRecorded() async throws {
    let stub = StubNotificationCenter()
    stub.authorizationGrantResult = true
    let granted = try await stub.requestAuthorization(options: [.alert, .sound])
    #expect(granted)
    #expect(stub.snapshot.requestedAuthorization == [[.alert, .sound]])
    #expect(stub.stubbedAuthorizationStatus == .authorized)
  }

  @Test("denied grant flips status to .denied")
  func deniedGrant() async throws {
    let stub = StubNotificationCenter()
    stub.authorizationGrantResult = false
    let granted = try await stub.requestAuthorization(options: [.alert])
    #expect(!granted)
    #expect(stub.stubbedAuthorizationStatus == .denied)
  }

  @Test("add replaces a request with matching identifier (mirrors UN center semantics)")
  func addReplacesByIdentifier() async throws {
    let stub = StubNotificationCenter()
    let id = "scramble.activation.\(UUID().uuidString).\(Phase.dayBefore.rawValue)"
    let first = UNMutableNotificationContent()
    first.body = "first"
    try await stub.add(UNNotificationRequest(identifier: id, content: first, trigger: nil))
    let second = UNMutableNotificationContent()
    second.body = "second"
    try await stub.add(UNNotificationRequest(identifier: id, content: second, trigger: nil))
    let pending = await stub.pendingNotificationRequests()
    #expect(pending.count == 1)
    #expect(pending.first?.content.body == "second")
  }

  @Test("removePendingNotificationRequests drops the named identifiers")
  func removeDrops() async throws {
    let stub = StubNotificationCenter()
    let idA = "a"
    let idB = "b"
    try await stub.add(
      UNNotificationRequest(identifier: idA, content: UNMutableNotificationContent(), trigger: nil))
    try await stub.add(
      UNNotificationRequest(identifier: idB, content: UNMutableNotificationContent(), trigger: nil))
    stub.removePendingNotificationRequests(withIdentifiers: [idA])
    let pending = await stub.pendingNotificationRequests()
    #expect(pending.map(\.identifier) == [idB])
    #expect(stub.snapshot.removedPending == [[idA]])
  }

  @Test("nextAddError throws once then clears")
  func nextAddErrorTransient() async throws {
    let stub = StubNotificationCenter()
    struct DummyError: Error {}
    stub.nextAddError = DummyError()
    await #expect(throws: DummyError.self) {
      try await stub.add(
        UNNotificationRequest(
          identifier: "x", content: UNMutableNotificationContent(), trigger: nil))
    }
    try await stub.add(
      UNNotificationRequest(identifier: "x", content: UNMutableNotificationContent(), trigger: nil))
    #expect(stub.snapshot.added.count == 1)
  }
}
