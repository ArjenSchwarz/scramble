import SwiftUI

/// Phase 5 — SwiftUI environment carrier for the active `SharingService`.
///
/// Production wires this to `CloudKitSharingService`; SwiftUI previews
/// and tests can inject `FakeSharingService` (or any other
/// `SharingService`) by overriding `\.sharingService`.
///
/// `nil` means the app is running without a sharing seam (e.g., the
/// preview branch of `EnvironmentProbe`), in which case affordances that
/// depend on sharing should be hidden.
private struct SharingServiceKey: EnvironmentKey {
  @MainActor
  static var defaultValue: (any SharingService)? { nil }
}

extension EnvironmentValues {
  var sharingService: (any SharingService)? {
    get { self[SharingServiceKey.self] }
    set { self[SharingServiceKey.self] = newValue }
  }
}
