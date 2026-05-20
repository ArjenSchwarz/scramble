import Foundation

/// One scheduled notification's input data — what to fire, when, and what
/// to render. The `body` and `title` are captured at plan time so the
/// reconciler can no-op when an existing pending request already matches.
nonisolated struct ActivationPlan: Equatable, Sendable {
  let tripID: UUID
  let phase: Phase
  /// Calendar components for `UNCalendarNotificationTrigger`. Includes
  /// year, month, day, hour, minute so daylight-saving and time-zone
  /// changes resolve through the system calendar (Decision 7).
  let fireDateComponents: DateComponents
  let outstandingTaskCount: Int
  /// Pre-rendered banner body string. Captured at plan time so the
  /// reconciler can compare against `request.content.body`.
  let body: String
  /// Banner title — always the trip name.
  let title: String
}

/// Phase 6 — pure mapping from the set of trips on the device (plus their
/// `TripTask` rows) to the set of activation notifications that should be
/// scheduled. The reconciler diffs this plan against the device's pending
/// `UNNotificationRequest`s.
///
/// The function is `@MainActor` because `Trip` and `TripTask` are SwiftData
/// `@Model` types whose property accessors are MainActor-isolated. Logic
/// itself is synchronous and side-effect-free.
@MainActor
enum NotificationPlanner {

  /// Time-of-day for activation notifications (Decision 4).
  private static let fireHour = 9
  private static let fireMinute = 0

  /// Builds the per-`(tripID, phase)` plan list. Skips:
  /// - `weeksBefore` and `afterTrip` (open-ended; Req 1.4)
  /// - `duringTrip` when `PhaseDateMapping.isCompressed == true` (Req 1.4)
  /// - phases whose activation date ≤ `now`'s calendar day (Req 1.5 / C2)
  ///
  /// Sorts by fire date ascending; ties broken by `Trip.startDate` then
  /// `Trip.id` (Req 2.2). Truncates to `cap` plans (Req 2.1).
  static func plan(
    trips: [Trip],
    tripTasksByTripID: [UUID: [TripTask]],
    now: Date,
    calendar: Calendar,
    cap: Int = 60
  ) -> [ActivationPlan] {
    let today = calendar.startOfDay(for: now)
    var candidates: [ActivationPlan] = []

    for trip in trips {
      for phase in Self.eligiblePhases {
        guard let range = PhaseDateMapping.dateRange(phase, for: trip, calendar: calendar)
        else { continue }
        if PhaseDateMapping.isCompressed(phase, for: trip, calendar: calendar) { continue }

        let activationDay = calendar.startOfDay(for: range.lowerBound)
        // Req 1.5 / C2 — strict greater-than today.
        guard activationDay > today else { continue }

        let outstanding = Self.outstandingCount(
          for: phase, tasks: tripTasksByTripID[trip.id] ?? []
        )
        let comps = Self.fireDateComponents(for: activationDay, calendar: calendar)
        candidates.append(
          ActivationPlan(
            tripID: trip.id,
            phase: phase,
            fireDateComponents: comps,
            outstandingTaskCount: outstanding,
            body: body(tripName: trip.name, phase: phase, outstandingTasks: outstanding),
            title: trip.name
          )
        )
      }
    }

    // Build a stable ordering: fire date ascending, then Trip.startDate
    // ascending, then Trip.id ascending. `Trip.startDate` is looked up
    // via a tripID → startDate dictionary so the comparator stays
    // O(log n) overall and does not re-walk the `trips` array per call.
    let startByID: [UUID: Date] = trips.reduce(into: [:]) { partial, trip in
      partial[trip.id] = trip.startDate
    }
    let sorted = candidates.sorted { lhs, rhs in
      let lhsDate = calendar.date(from: lhs.fireDateComponents) ?? .distantPast
      let rhsDate = calendar.date(from: rhs.fireDateComponents) ?? .distantPast
      if lhsDate != rhsDate { return lhsDate < rhsDate }
      let lhsStart = startByID[lhs.tripID] ?? .distantPast
      let rhsStart = startByID[rhs.tripID] ?? .distantPast
      if lhsStart != rhsStart { return lhsStart < rhsStart }
      return lhs.tripID.uuidString < rhs.tripID.uuidString
    }

    return Array(sorted.prefix(cap))
  }

  /// Pre-renders the notification body string. Exposed for the reconciler
  /// so it can detect "pending body matches plan body" no-ops without
  /// re-running `plan`.
  static func body(tripName: String, phase: Phase, outstandingTasks: Int) -> String {
    if outstandingTasks > 0 {
      let noun = outstandingTasks == 1 ? "task" : "tasks"
      return "\(outstandingTasks) outstanding \(noun) for '\(phase.displayName)'"
    }
    return "'\(phase.displayName)' has started"
  }

  // MARK: - Private helpers

  /// Five phases that can produce activation notifications: the four 1-day
  /// phases plus `duringTrip` (skipped via `isCompressed` when its range
  /// is empty).
  private static let eligiblePhases: [Phase] = [
    .dayBefore, .departureDay, .duringTrip, .dayBeforeReturn, .returnDay,
  ]

  /// Mirrors the matching-or-pinned predicate used by `TaskListHelpers.counts`
  /// so that tasks the rules engine has flagged as `currentlyMatchesRules == false`
  /// (and which are not pinned) — i.e. visible-but-inactive — do not inflate the
  /// outstanding count shown in the activation notification body.
  private static func outstandingCount(for phase: Phase, tasks: [TripTask]) -> Int {
    tasks.reduce(0) { partial, task in
      guard task.phase == phase,
        !task.isCompleted,
        !task.userDeletedOnThisTrip,
        task.currentlyMatchesRules || task.pinnedByUser
      else { return partial }
      return partial + 1
    }
  }

  private static func fireDateComponents(
    for activationDay: Date, calendar: Calendar
  ) -> DateComponents {
    var comps = calendar.dateComponents(
      [.year, .month, .day], from: activationDay
    )
    comps.hour = fireHour
    comps.minute = fireMinute
    return comps
  }
}
