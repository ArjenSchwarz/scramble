import Foundation
import Testing

@testable import Scramble

/// Phase 6 — `NotificationPlanner` table-driven coverage (Reqs 1.2, 1.4,
/// 1.5, 2.1, 2.2). The planner is a pure function: trips + tasks + now +
/// calendar + cap → `[ActivationPlan]`. The reconciler diffs its output
/// against `pendingNotificationRequests`.
///
/// `Calendar(identifier: .gregorian)` is pinned with a UTC timezone for
/// determinism. Dates are constructed via `DateComponents` so DST and
/// timezone behaviour does not bleed into the test inputs.
@Suite("NotificationPlanner", .serialized)
@MainActor
struct NotificationPlannerTests {

  // MARK: - Eligibility

  @Test(
    """
    A trip with start in 30 days and end in 40 days produces 5 plans \
    — dayBefore, departureDay, duringTrip, dayBeforeReturn, returnDay \
    (excludes weeksBefore and afterTrip).
    """
  )
  func standardTripProducesFivePlans() throws {
    let now = Self.date(year: 2026, month: 6, day: 1)
    let start = Self.date(year: 2026, month: 7, day: 1)
    let end = Self.date(year: 2026, month: 7, day: 10)
    let trip = Trip(name: "T", startDate: start, endDate: end)

    let plans = NotificationPlanner.plan(
      trips: [trip], tripTasksByTripID: [:],
      now: now, calendar: Self.calendar, cap: 60
    )

    let phases = Set(plans.map(\.phase))
    #expect(phases.contains(.dayBefore))
    #expect(phases.contains(.departureDay))
    // duringTrip is included when its range is non-empty (here: 9 days
    // between departureDay and dayBeforeReturn).
    #expect(phases.contains(.duringTrip))
    #expect(phases.contains(.dayBeforeReturn))
    // returnDay is also a 1-day phase that activates on `endDate`.
    #expect(phases.contains(.returnDay))
    #expect(!phases.contains(.weeksBefore))
    #expect(!phases.contains(.afterTrip))
    #expect(plans.count == 5)
  }

  @Test(
    "A 1-day trip (start == end) skips duringTrip because PhaseDateMapping.isCompressed is true")
  func oneDayTripSkipsCompressedDuringTrip() throws {
    let now = Self.date(year: 2026, month: 6, day: 1)
    let day = Self.date(year: 2026, month: 7, day: 1)
    let trip = Trip(name: "T", startDate: day, endDate: day)

    let plans = NotificationPlanner.plan(
      trips: [trip], tripTasksByTripID: [:],
      now: now, calendar: Self.calendar, cap: 60
    )
    let phases = Set(plans.map(\.phase))
    #expect(!phases.contains(.duringTrip))
  }

  // MARK: - Past-day skip (Req 1.5 / C2)

  @Test("A phase whose activation date is today is skipped")
  func phaseActivatingTodayIsSkipped() throws {
    let now = Self.date(year: 2026, month: 7, day: 1)  // departureDay
    let start = Self.date(year: 2026, month: 7, day: 1)
    let end = Self.date(year: 2026, month: 7, day: 5)
    let trip = Trip(name: "T", startDate: start, endDate: end)

    let plans = NotificationPlanner.plan(
      trips: [trip], tripTasksByTripID: [:],
      now: now, calendar: Self.calendar, cap: 60
    )
    let phases = Set(plans.map(\.phase))
    // dayBefore activation was yesterday — skipped.
    #expect(!phases.contains(.dayBefore))
    // departureDay activation is today — skipped.
    #expect(!phases.contains(.departureDay))
    // duringTrip starts day after departure — eligible.
    #expect(phases.contains(.duringTrip))
  }

  @Test("A trip entirely in the past produces zero plans")
  func pastTripProducesNoPlans() throws {
    let now = Self.date(year: 2026, month: 8, day: 1)
    let start = Self.date(year: 2026, month: 7, day: 1)
    let end = Self.date(year: 2026, month: 7, day: 10)
    let trip = Trip(name: "T", startDate: start, endDate: end)

    let plans = NotificationPlanner.plan(
      trips: [trip], tripTasksByTripID: [:],
      now: now, calendar: Self.calendar, cap: 60
    )
    #expect(plans.isEmpty)
  }

  // MARK: - Body text (Req 1.2)

  @Test("Body for outstandingTaskCount > 0 names the count and the phase display name")
  func bodyForOutstandingTasks() {
    let body = NotificationPlanner.body(
      phase: .departureDay, outstandingTasks: 3
    )
    #expect(body == "3 outstanding tasks for 'Departure day'")
  }

  @Test("Body for outstandingTaskCount == 0 uses 'has started' form and omits the count")
  func bodyForZeroOutstandingTasks() {
    let body = NotificationPlanner.body(
      phase: .dayBefore, outstandingTasks: 0
    )
    #expect(body == "'Day before' has started")
    #expect(!body.contains("0"))
  }

  // MARK: - 60-cap with deterministic tie-break (Req 2.1, 2.2)

  @Test(
    "Plan count is clamped to cap; dropped plans are the latest fire dates"
  )
  func capClampsToSoonestFireDates() throws {
    let now = Self.date(year: 2026, month: 6, day: 1)
    // 13 trips × 5 eligible phases = 65 plans; cap = 60. The five
    // latest-firing plans should be dropped.
    var trips: [Trip] = []
    for index in 0..<13 {
      let start = Self.date(year: 2026, month: 7, day: 1 + index)
      let end = Self.date(year: 2026, month: 7, day: 10 + index)
      trips.append(Trip(name: "T\(index)", startDate: start, endDate: end))
    }

    let plans = NotificationPlanner.plan(
      trips: trips, tripTasksByTripID: [:],
      now: now, calendar: Self.calendar, cap: 60
    )
    #expect(plans.count == 60)
    // Plans are sorted by fire date ascending.
    let fireDates = plans.compactMap { Self.calendar.date(from: $0.fireDateComponents) }
    #expect(fireDates == fireDates.sorted())
  }

  @Test("Ties on fire date are broken by trip startDate ascending then trip.id ascending")
  func tieBreakOrderingIsStable() throws {
    let now = Self.date(year: 2026, month: 6, day: 1)
    let start = Self.date(year: 2026, month: 7, day: 1)
    let end = Self.date(year: 2026, month: 7, day: 5)
    // Two trips with identical start/end. Use small UUIDs so we can
    // assert the ascending ordering deterministically.
    let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let highID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
    let lowTrip = Trip(id: lowID, name: "A", startDate: start, endDate: end)
    let highTrip = Trip(id: highID, name: "B", startDate: start, endDate: end)

    let plans = NotificationPlanner.plan(
      trips: [highTrip, lowTrip], tripTasksByTripID: [:],
      now: now, calendar: Self.calendar, cap: 60
    )
    // First plan by phase fire date is dayBefore. Its tie-break should
    // emit lowID before highID.
    let dayBeforePlans = plans.filter { $0.phase == .dayBefore }
    #expect(dayBeforePlans.count == 2)
    #expect(dayBeforePlans[0].tripID == lowID)
    #expect(dayBeforePlans[1].tripID == highID)
  }

  // MARK: - Outstanding task count threading

  @Test("Plan body includes outstanding-task count from tripTasksByTripID")
  func outstandingTaskCountFlowsToBody() throws {
    let now = Self.date(year: 2026, month: 6, day: 1)
    let start = Self.date(year: 2026, month: 7, day: 1)
    let end = Self.date(year: 2026, month: 7, day: 5)
    let trip = Trip(name: "Iceland", startDate: start, endDate: end)
    let completedTask = TripTask(
      trip: trip, name: "Pack socks", phase: .dayBefore, isCompleted: true
    )
    let pendingTask = TripTask(
      trip: trip, name: "Pack passport", phase: .dayBefore, isCompleted: false
    )
    let otherPhaseTask = TripTask(
      trip: trip, name: "Pack toothbrush", phase: .departureDay, isCompleted: false
    )

    let plans = NotificationPlanner.plan(
      trips: [trip],
      tripTasksByTripID: [trip.id: [completedTask, pendingTask, otherPhaseTask]],
      now: now, calendar: Self.calendar, cap: 60
    )
    let dayBeforePlan = try #require(plans.first { $0.phase == .dayBefore })
    #expect(dayBeforePlan.outstandingTaskCount == 1)
    #expect(dayBeforePlan.body == "1 outstanding task for 'Day before'")
  }

  @Test("User-deleted tasks are excluded from outstanding count")
  func userDeletedTasksExcluded() throws {
    let now = Self.date(year: 2026, month: 6, day: 1)
    let start = Self.date(year: 2026, month: 7, day: 1)
    let end = Self.date(year: 2026, month: 7, day: 5)
    let trip = Trip(name: "T", startDate: start, endDate: end)
    let deleted = TripTask(
      trip: trip, name: "x", phase: .dayBefore, isCompleted: false,
      userDeletedOnThisTrip: true
    )
    let live = TripTask(
      trip: trip, name: "y", phase: .dayBefore, isCompleted: false
    )

    let plans = NotificationPlanner.plan(
      trips: [trip], tripTasksByTripID: [trip.id: [deleted, live]],
      now: now, calendar: Self.calendar, cap: 60
    )
    let dayBeforePlan = try #require(plans.first { $0.phase == .dayBefore })
    #expect(dayBeforePlan.outstandingTaskCount == 1)
  }

  // MARK: - Property: no plan fires on or before today

  struct DateScenario: Sendable {
    let label: String
    let nowYear: Int
    let nowMonth: Int
    let nowDay: Int
    let startYear: Int
    let startMonth: Int
    let startDay: Int
  }

  @Test(
    "Property — no plan has a fire date ≤ now's calendar day",
    arguments: [
      DateScenario(
        label: "now",
        nowYear: 2026, nowMonth: 6, nowDay: 1,
        startYear: 2026, startMonth: 7, startDay: 1),
      DateScenario(
        label: "just-before",
        nowYear: 2026, nowMonth: 7, nowDay: 1,
        startYear: 2026, startMonth: 7, startDay: 1),
      DateScenario(
        label: "during",
        nowYear: 2026, nowMonth: 7, nowDay: 3,
        startYear: 2026, startMonth: 7, startDay: 1),
      DateScenario(
        label: "far-future",
        nowYear: 2026, nowMonth: 1, nowDay: 1,
        startYear: 2027, startMonth: 1, startDay: 1),
      DateScenario(
        label: "very-far-future",
        nowYear: 2026, nowMonth: 6, nowDay: 1,
        startYear: 2027, startMonth: 6, startDay: 1),
    ] as [DateScenario])
  func noPlanFiresOnOrBeforeToday(scenario: DateScenario) throws {
    let now = Self.date(year: scenario.nowYear, month: scenario.nowMonth, day: scenario.nowDay)
    let start = Self.date(
      year: scenario.startYear, month: scenario.startMonth, day: scenario.startDay)
    let end = Self.calendar.date(byAdding: .day, value: 10, to: start) ?? start
    let trip = Trip(name: scenario.label, startDate: start, endDate: end)
    let todayStart = Self.calendar.startOfDay(for: now)

    let plans = NotificationPlanner.plan(
      trips: [trip], tripTasksByTripID: [:],
      now: now, calendar: Self.calendar, cap: 60
    )
    for plan in plans {
      let fire = try #require(Self.calendar.date(from: plan.fireDateComponents))
      let fireDayStart = Self.calendar.startOfDay(for: fire)
      #expect(fireDayStart > todayStart, "Plan \(plan.phase) fires \(fire) ≤ \(now)")
    }
  }

  // MARK: - Helpers

  /// UTC gregorian calendar for deterministic test arithmetic.
  static let calendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return cal
  }()

  static func date(year: Int, month: Int, day: Int) -> Date {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = 0
    comps.minute = 0
    comps.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar.date(from: comps) ?? Date.distantPast
  }
}
