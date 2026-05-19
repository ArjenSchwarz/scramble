import SwiftData
import SwiftUI

/// Phase 5.1 — environment carrier for the `globals` `ModelContainer`. The
/// dual-container split places `Person`, master lists, and the migration
/// journal in `globals` and the trip-domain entities in `tripsLocal`. Trip
/// subtrees bind `.modelContainer(tripsLocal)` and reach for `globals` via
/// this environment key when they need a cross-container lookup or to
/// re-root a child view to globals (see `TripEditorPeoplePicker`).
private struct GlobalsContainerKey: EnvironmentKey {
  @MainActor
  static var defaultValue: ModelContainer {
    ModelStore.containers.globals
  }
}

extension EnvironmentValues {
  var globalsContainer: ModelContainer {
    get { self[GlobalsContainerKey.self] }
    set { self[GlobalsContainerKey.self] = newValue }
  }
}
