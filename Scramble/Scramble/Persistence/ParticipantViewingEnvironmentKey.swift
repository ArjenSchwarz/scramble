import SwiftUI

/// Phase 5 — flags whether the current Trip Detail surface is being
/// rendered for a participant on a shared trip. Drives the WhyDisclosure
/// hide behaviour
/// (Req [3.3](../../specs/phase-5-cloudkit-sharing/requirements.md#3.3))
/// and the "Rules last evaluated" subline
/// (Req [8.8](../../specs/phase-5-cloudkit-sharing/requirements.md#8.8)).
///
/// Set by `TripDetailView`; consumed by `TaskRow`, `PackingItemRow`, and
/// the WhyResolver. `false` for owner-viewed trips and for non-shared
/// trips (default).
private struct IsParticipantViewingSharedTripKey: EnvironmentKey {
  static let defaultValue: Bool = false
}

extension EnvironmentValues {
  var isParticipantViewingSharedTrip: Bool {
    get { self[IsParticipantViewingSharedTripKey.self] }
    set { self[IsParticipantViewingSharedTripKey.self] = newValue }
  }
}
