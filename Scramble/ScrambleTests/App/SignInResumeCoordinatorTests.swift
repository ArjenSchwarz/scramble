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
    let gate = ResumeGate()
    let counter = RunCounter()
    let coordinator = SignInResumeCoordinator(
      isCloudAvailable: { true },
      resume: {
        counter.bump()
        // Block the in-flight run until the test releases the gate.
        // Deterministic: every storm trigger is guaranteed to land
        // while inFlight is non-nil, so pendingReplay collapses them
        // to a single trailing replay regardless of scheduling jitter.
        await gate.wait()
      }
    )
    coordinator.start()
    await counter.waitForAtLeast(1)
    let baseline = counter.value

    // Fire the storm while the initial run is parked on the gate.
    for _ in 0..<10 {
      coordinator.runResumeIfNeeded()
    }
    // Release the gate; the in-flight run completes, then the trailing
    // replay runs once, then the gate has to release that too.
    gate.release()
    await counter.waitForAtLeast(baseline + 1)
    gate.release()
    await counter.waitForStable(checks: 10, intervalNanos: 10_000_000)

    let delta = counter.value - baseline
    #expect(delta == 1, "Exactly one trailing replay (saw \(delta))")
  }

  // MARK: - Helpers

  /// Single-shot gate that the `resume` closure can `await` on. The
  /// test calls `release()` once per in-flight run so the storm-collapse
  /// path is sequenced deterministically (no scheduling-jitter races).
  @MainActor
  final class ResumeGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var pendingReleases: Int = 0

    func wait() async {
      if pendingReleases > 0 {
        pendingReleases -= 1
        return
      }
      await withCheckedContinuation { continuation = $0 }
    }

    func release() {
      if let continuation {
        self.continuation = nil
        continuation.resume()
      } else {
        pendingReleases += 1
      }
    }
  }

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
