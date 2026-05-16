import SwiftUI

/// Phase 5 — SwiftUI environment carrier for the
/// `RulesLastEvaluatedTracker`. Production wires this to a single tracker
/// shared with `RulesEngineTriggerOrchestrator`; UI tests inject a fresh
/// tracker (or read the production one) to drive the participant-side
/// "Rules last evaluated" subline.
///
/// `nil` is the default for previews and unit-test branches that don't
/// stand up the sync engine; consumers should treat `nil` as "no data —
/// suppress the subline".
private struct RulesLastEvaluatedTrackerKey: EnvironmentKey {
  @MainActor
  static var defaultValue: RulesLastEvaluatedTracker? { nil }
}

extension EnvironmentValues {
  var rulesLastEvaluatedTracker: RulesLastEvaluatedTracker? {
    get { self[RulesLastEvaluatedTrackerKey.self] }
    set { self[RulesLastEvaluatedTrackerKey.self] = newValue }
  }
}
