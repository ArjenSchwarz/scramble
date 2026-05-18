import CloudKit
import Foundation
import Testing
import UIKit

@testable import Scramble

/// Phase 5.1 — `SignInResumeCoordinator` re-runs Stage B when iCloud
/// becomes available after launch. See design § "SignInResumeCoordinator
/// (new)" and Req 4.8.
@Suite("SignInResumeCoordinator", .serialized)
@MainActor
struct SignInResumeCoordinatorTests {

  @Test("start() immediately runs the resume action when iCloud is available")
  func startTriggersImmediateRunWhenAvailable() async throws {
    let counter = RunCounter()
    let coordinator = SignInResumeCoordinator(
      isCloudAvailable: { true },
      resume: { counter.bump() }
    )
    coordinator.start()
    await counter.waitForAtLeast(1)
    #expect(counter.value == 1, "Immediate re-check runs when available")
  }

  @Test("start() does NOT run the resume action when iCloud is unavailable")
  func startSkipsWhenUnavailable() async throws {
    let counter = RunCounter()
    let coordinator = SignInResumeCoordinator(
      isCloudAvailable: { false },
      resume: { counter.bump() }
    )
    coordinator.start()
    try? await Task.sleep(nanoseconds: 50_000_000)
    #expect(counter.value == 0, "Unavailable iCloud short-circuits the resume")
  }

  @Test("CKAccountChanged notification triggers a resume run")
  func ckAccountChangedTriggersResume() async throws {
    let counter = RunCounter()
    let coordinator = SignInResumeCoordinator(
      isCloudAvailable: { true },
      resume: { counter.bump() }
    )
    coordinator.start()
    await counter.waitForAtLeast(1)
    let baseline = counter.value

    NotificationCenter.default.post(name: .CKAccountChanged, object: nil)
    await counter.waitForAtLeast(baseline + 1)
    #expect(counter.value >= baseline + 1, "CKAccountChanged triggers a resume")
  }

  @Test("UIScene.didActivateNotification fallback also triggers a resume")
  func sceneActivationTriggersResume() async throws {
    let counter = RunCounter()
    let coordinator = SignInResumeCoordinator(
      isCloudAvailable: { true },
      resume: { counter.bump() }
    )
    coordinator.start()
    await counter.waitForAtLeast(1)
    let baseline = counter.value

    NotificationCenter.default.post(name: UIScene.didActivateNotification, object: nil)
    await counter.waitForAtLeast(baseline + 1)
    #expect(counter.value >= baseline + 1, "Scene-activation triggers a resume")
  }

  @Test("Storm-fire collapses to exactly one trailing replay")
  func stormCollapse() async throws {
    let counter = RunCounter()
    let coordinator = SignInResumeCoordinator(
      isCloudAvailable: { true },
      resume: {
        counter.bump()
        // Yield so the storm-fire below lands while this run is in
        // flight; pendingReplay collapses every subsequent trigger to a
        // single trailing replay.
        try? await Task.sleep(nanoseconds: 30_000_000)
      }
    )
    coordinator.start()
    await counter.waitForAtLeast(1)
    let baseline = counter.value

    // Fire the storm while the initial run's sleep is still pending.
    for _ in 0..<10 {
      coordinator.runResumeIfNeeded()
    }
    await counter.waitForStable(checks: 10, intervalNanos: 20_000_000)

    let delta = counter.value - baseline
    #expect(delta == 1, "Exactly one trailing replay (saw \(delta))")
  }

  // MARK: - Helpers

  @MainActor
  final class RunCounter {
    var value: Int = 0
    func bump() { value += 1 }

    func waitForAtLeast(_ target: Int) async {
      for _ in 0..<200 {
        if value >= target { return }
        try? await Task.sleep(nanoseconds: 10_000_000)
      }
    }

    func waitForStable(checks: Int, intervalNanos: UInt64) async {
      var lastValue = value
      var stableCount = 0
      while stableCount < checks {
        try? await Task.sleep(nanoseconds: intervalNanos)
        if value == lastValue {
          stableCount += 1
        } else {
          lastValue = value
          stableCount = 0
        }
      }
    }
  }
}
