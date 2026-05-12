import Foundation

nonisolated enum Phase: String, Codable, CaseIterable, Hashable, Sendable {
  case weeksBefore
  case dayBefore
  case departureDay
  case duringTrip
  case dayBeforeReturn
  case returnDay
  case afterTrip

  var displayName: String {
    switch self {
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

nonisolated enum ItemSource: String, Codable, CaseIterable, Hashable, Sendable {
  case rule
  case manual
}

nonisolated enum PackingState: String, Codable, CaseIterable, Hashable, Sendable {
  case unpacked
  case packed
  case repacked
  case excluded
}

nonisolated enum TripAttribute: String, Codable, CaseIterable, Hashable, Sendable {
  case duration
  case transport
  case scope
  case weather
  case purpose
}

/// Visual state of a `PhaseNode` on the Trip Detail timeline.
/// Computed from `(Trip, today, Phase)` via
/// `TripDetailView.state(for:today:start:end:calendar)`.
nonisolated enum PhaseNodeState: Hashable, Sendable {
  case past
  case current
  case future
}
