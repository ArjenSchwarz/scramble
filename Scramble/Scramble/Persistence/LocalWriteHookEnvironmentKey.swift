import CloudKit
import SwiftUI
import os

/// Phase 5.1 — environment carrier for the shared `LocalWriteHook` that
/// gates every `tripsLocal` save. Trip-domain SwiftUI surfaces resolve the
/// hook via `@Environment(\.localWriteHook)` and call `hook.commit(_:)`
/// instead of `modelContext.save()` so dirty-marking and the per-commit
/// single-save invariant are honoured.
///
/// The default value is a hook whose notifier fails loudly outside test /
/// UI-test / preview surroundings. Tests and previews that read the
/// environment without injecting one still save locally and discard sync
/// signals silently; production injects the real hook (notifier =
/// `TripSyncEngine`) from `ScrambleApp.rootContent()`.
///
/// A `fatalError` default is not used because SwiftUI's environment
/// propagation reads the current value of the keypath before overwriting
/// it via `.environment(\.localWriteHook, _:)`; the fatal stub trips
/// before the injection can complete. See decision_log.md Decision 6.
private struct LocalWriteHookKey: EnvironmentKey {
  @MainActor
  static var defaultValue: LocalWriteHook {
    LocalWriteHook(notifier: FallbackPendingChangeNotifier.shared)
  }
}

extension EnvironmentValues {
  var localWriteHook: LocalWriteHook {
    get { self[LocalWriteHookKey.self] }
    set { self[LocalWriteHookKey.self] = newValue }
  }
}

/// Fallback notifier used by the env-key default. In test / UI-test /
/// preview surroundings it discards calls silently. In production it
/// emits a `fault`-level log and (in DEBUG builds) trips an
/// `assertionFailure` so a misconfigured production view path is
/// detectable at the first commit rather than the first missed sync.
///
/// This pairs with the contract test in Req [2.5]: that test catches
/// direct `modelContext.save()` call sites; this fault catches the
/// inverse failure — a `hook.commit(modelContext)` whose env-resolved
/// hook is the default because injection didn't propagate. Together they
/// close the silent-failure mode Phase 5.1 exists to eliminate.
@MainActor
private final class FallbackPendingChangeNotifier: PendingChangeNotifier {
  static let shared = FallbackPendingChangeNotifier()

  func notifyPendingChanges(
    savedRecordIDs: [CKRecord.ID],
    deletedRecordIDs: [CKRecord.ID],
    in zoneID: CKRecordZone.ID
  ) {
    let probe = EnvironmentProbe.production
    if probe.isTest || probe.isUITestHost || probe.isPreview {
      return  // Tests and previews legitimately exercise the default.
    }
    modelLogger.fault(
      """
      [LocalWriteHook.fallback-notifier] reached in production — \
      \\.localWriteHook was not injected on the path that called commit. \
      Records will not sync. zone=\(zoneID.zoneName, privacy: .public) \
      saved=\(savedRecordIDs.count) deleted=\(deletedRecordIDs.count)
      """
    )
    assertionFailure(
      "LocalWriteHook fallback notifier reached in production; \\.localWriteHook was not injected."
    )
  }
}
