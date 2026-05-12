import Foundation

/// Display labels reused across master-list editor + list surfaces. Mirrors
/// `TripDetailView.label(for:)` so the same name appears in both places.
nonisolated enum MasterListLabels {
  static func phase(_ phase: Phase) -> String {
    switch phase {
    case .weeksBefore: "Weeks before"
    case .dayBefore: "Day before"
    case .departureDay: "Departure day"
    case .duringTrip: "During trip"
    case .dayBeforeReturn: "Day before return"
    case .returnDay: "Return day"
    case .afterTrip: "After trip"
    }
  }
}
