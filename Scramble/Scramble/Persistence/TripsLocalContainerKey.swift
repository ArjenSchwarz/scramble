import SwiftData
import SwiftUI

/// Phase 5 — environment carrier for the `tripsLocal` `ModelContainer`
/// (Decision 13). The globals container continues to flow through SwiftUI's
/// built-in `.modelContainer(_:)` modifier; tripsLocal is a sibling
/// container so views that need to read trip-zone data go through this
/// environment key instead of `@Environment(\.modelContext)`. Only views
/// that interact with the trip-sync engine should reach for it; the
/// majority of SwiftData call sites continue to use the default context.
private struct TripsLocalContainerKey: EnvironmentKey {
  @MainActor
  static var defaultValue: ModelContainer {
    ModelStore.containers.tripsLocal
  }
}

extension EnvironmentValues {
  var tripsLocalContainer: ModelContainer {
    get { self[TripsLocalContainerKey.self] }
    set { self[TripsLocalContainerKey.self] = newValue }
  }
}
