import Foundation

/// Pure mapping from a `Phase` × `Trip` (`startDate`, `endDate`) to its calendar
/// extent.
///
/// Implements the canonical "Trip-date-to-phase-date mapping" table from
/// `specs/phase-3-timeline-tasks/requirements.md`. All functions normalise
/// trip dates to `startOfDay` before arithmetic, so DST transitions and
/// trailing time-of-day components do not skew durations.
///
/// `dateRange` returns `nil` for the open-ended phases (`.weeksBefore`,
/// `.afterTrip`). `durationDays` returns `nil` for those same phases.
/// `isCompressed` is true iff the phase is `.duringTrip` with zero duration,
/// which happens exactly when `endDate - startDate <= 1 day`.
///
/// `@MainActor` is required because the functions read `Trip.startDate` and
/// `Trip.endDate`, and `Trip` is a `@Model` class whose property accessors
/// are MainActor-isolated by SwiftData's default isolation. If a future
/// refactor changes the signatures to take `Date` parameters directly, the
/// annotation can drop and unit tests no longer need `@MainActor`.
@MainActor
enum PhaseDateMapping {

  static func dateRange(
    _ phase: Phase,
    for trip: Trip,
    calendar: Calendar
  ) -> ClosedRange<Date>? {
    let start = calendar.startOfDay(for: trip.startDate)
    let end = calendar.startOfDay(for: trip.endDate)

    switch phase {
    case .weeksBefore, .afterTrip:
      return nil
    case .dayBefore:
      let d = calendar.date(byAdding: .day, value: -1, to: start) ?? start
      return d...d
    case .departureDay:
      return start...start
    case .duringTrip:
      guard let lower = calendar.date(byAdding: .day, value: 1, to: start),
        let upper = calendar.date(byAdding: .day, value: -1, to: end),
        lower <= upper
      else { return nil }
      return lower...upper
    case .dayBeforeReturn:
      let d = calendar.date(byAdding: .day, value: -1, to: end) ?? end
      return d...d
    case .returnDay:
      return end...end
    }
  }

  /// Number of calendar days in the phase. `nil` for open-ended phases
  /// (`.weeksBefore`, `.afterTrip`). For `.duringTrip` returns
  /// `max(0, (E - S) - 1)`; for the four 1-day phases returns `1`.
  static func durationDays(
    _ phase: Phase,
    for trip: Trip,
    calendar: Calendar
  ) -> Int? {
    switch phase {
    case .weeksBefore, .afterTrip:
      return nil
    case .dayBefore, .departureDay, .dayBeforeReturn, .returnDay:
      return 1
    case .duringTrip:
      let start = calendar.startOfDay(for: trip.startDate)
      let end = calendar.startOfDay(for: trip.endDate)
      let comps = calendar.dateComponents([.day], from: start, to: end)
      let days = comps.day ?? 0
      return max(0, days - 1)
    }
  }

  static func isCompressed(
    _ phase: Phase,
    for trip: Trip,
    calendar: Calendar
  ) -> Bool {
    phase == .duringTrip && durationDays(phase, for: trip, calendar: calendar) == 0
  }
}
