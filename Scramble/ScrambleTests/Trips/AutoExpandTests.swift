import Foundation
import SwiftData
import Testing

@testable import Scramble

@Suite("TripDetailView.autoExpandPhase", .serialized)
@MainActor
struct AutoExpandTests {

  // MARK: - Helpers

  private static var calendar: Calendar { Calendar(identifier: .gregorian) }

  private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var comps = DateComponents()
    comps.year = y
    comps.month = m
    comps.day = d
    return calendar.date(from: comps)!
  }

  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema(versionedSchema: SchemaV3.self)
    let config = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [config])
  }

  // MARK: - Normal trip → returns .current phase

  @Test("Normal multi-day trip with a task in the current phase → returns .duringTrip")
  func returnsCurrentDuringTrip() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let start = Self.date(2026, 6, 1)
    let end = Self.date(2026, 6, 7)
    let today = Self.date(2026, 6, 4)  // strictly between start and end → .duringTrip is current
    let trip = Trip(name: "T", startDate: start, endDate: end)
    context.insert(trip)
    let task = TripTask(
      trip: trip, name: "Sightsee", phase: .duringTrip, source: .manual
    )
    context.insert(task)
    try context.save()

    let result = TripDetailView.autoExpandPhase(for: trip, today: today, calendar: Self.calendar)
    #expect(result == .duringTrip)
  }

  // MARK: - Current phase non-expandable (no tasks, not packing) → nil

  @Test("Current non-packing phase with no tasks → nil")
  func nonExpandableCurrentNoTasks() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let start = Self.date(2026, 6, 1)
    let end = Self.date(2026, 6, 7)
    let today = Self.date(2026, 6, 4)  // .duringTrip current
    let trip = Trip(name: "T", startDate: start, endDate: end)
    context.insert(trip)
    try context.save()
    // No tasks anywhere.

    let result = TripDetailView.autoExpandPhase(for: trip, today: today, calendar: Self.calendar)
    #expect(result == nil)
  }

  // MARK: - Packing phases are expandable even with no tasks

  @Test(
    "Day-before current, no tasks → returns .dayBefore (packing phases always expandable)")
  func packingPhaseExpandableWithoutTasks() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let start = Self.date(2026, 6, 1)
    let end = Self.date(2026, 6, 7)
    // start - 1 → .dayBefore is .current. Derived so it tracks `start`.
    let today = Self.calendar.date(byAdding: .day, value: -1, to: start)!
    let trip = Trip(name: "T", startDate: start, endDate: end)
    context.insert(trip)
    try context.save()

    let result = TripDetailView.autoExpandPhase(for: trip, today: today, calendar: Self.calendar)
    #expect(result == .dayBefore)
  }

  @Test(
    "Multi-day trip on E-1 returns nil when duringTrip (first current in iteration) has no tasks")
  func multipleCurrentPhasesIterationOrder() throws {
    // On a multi-day trip with today == E-1, both .duringTrip and
    // .dayBeforeReturn evaluate to .current. The autoExpand helper picks
    // the first current phase in Phase.allCases iteration order, which is
    // .duringTrip. Since it's a non-packing phase with no tasks, the helper
    // returns nil (not .dayBeforeReturn) — exposing the first-wins rule.
    let container = try Self.makeContainer()
    let context = container.mainContext

    let start = Self.date(2026, 6, 1)
    let end = Self.date(2026, 6, 7)
    let today = Self.date(2026, 6, 6)  // E-1
    let trip = Trip(name: "T", startDate: start, endDate: end)
    context.insert(trip)
    try context.save()

    let result = TripDetailView.autoExpandPhase(for: trip, today: today, calendar: Self.calendar)
    #expect(result == nil)
  }

  @Test("Adding a task to .duringTrip on the same E-1 date causes autoExpand to return .duringTrip")
  func multipleCurrentPhasesWithTaskInDuringTrip() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let start = Self.date(2026, 6, 1)
    let end = Self.date(2026, 6, 7)
    let today = Self.date(2026, 6, 6)
    let trip = Trip(name: "T", startDate: start, endDate: end)
    context.insert(trip)
    let task = TripTask(
      trip: trip, name: "Last-minute reservation", phase: .duringTrip, source: .manual)
    context.insert(task)
    try context.save()

    let result = TripDetailView.autoExpandPhase(for: trip, today: today, calendar: Self.calendar)
    #expect(result == .duringTrip)
  }

  // MARK: - Compressed duringTrip never selected

  @Test("1-day trip on the day before → returns .dayBefore (packing phase expandable)")
  func compressedDuringTripFallsThroughToPacking() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let day = Self.date(2026, 6, 1)
    let trip = Trip(name: "T", startDate: day, endDate: day)  // 1-day trip → duringTrip compressed
    context.insert(trip)
    try context.save()

    let dayBefore = Self.calendar.date(byAdding: .day, value: -1, to: day)!
    let result = TripDetailView.autoExpandPhase(
      for: trip, today: dayBefore, calendar: Self.calendar)
    // On a 1-day trip with today == start - 1:
    // - dayBefore: today == start - 1 → .current  (packing, expandable)
    // - duringTrip is compressed and never .current.
    #expect(result == .dayBefore)
  }

  @Test("1-day trip on departure day (today == start) → nil (no departure-day pack surface)")
  func oneDayTripDepartureDayReturnsNil() throws {
    let container = try Self.makeContainer()
    let context = container.mainContext

    let day = Self.date(2026, 6, 1)
    let trip = Trip(name: "T", startDate: day, endDate: day)  // 1-day trip
    context.insert(trip)
    try context.save()

    // today == start on a 1-day trip: departureDay is the only .current phase
    // (dayBefore and dayBeforeReturn are both in the past; duringTrip is
    // compressed → never current). departureDay no longer hosts packing and
    // has no tasks, so autoExpand returns nil — packing happened the day
    // before, and there is no departure-day pack surface.
    let result = TripDetailView.autoExpandPhase(for: trip, today: day, calendar: Self.calendar)
    #expect(result == nil)
  }

  @Test("2-day trip on departure day → nil: departureDay shadows the dayBeforeReturn repack phase")
  func twoDayTripDepartureDayShadowsRepack() throws {
    // Defensive: simulate a 2-day trip where duringTrip is compressed
    // (duration 0). For any plausible today on a 2-day trip, duringTrip
    // is never .current per state(...). This test verifies the guard
    // does not erroneously return .duringTrip for a 2-day trip with
    // tasks in duringTrip even if today is "between" the days.
    let container = try Self.makeContainer()
    let context = container.mainContext

    let start = Self.date(2026, 6, 1)
    let end = Self.date(2026, 6, 2)
    let trip = Trip(name: "T", startDate: start, endDate: end)
    context.insert(trip)
    // Add an orphan task on duringTrip — should not influence autoExpand because
    // duringTrip is never current on a 2-day trip.
    let task = TripTask(trip: trip, name: "Sightsee", phase: .duringTrip, source: .manual)
    context.insert(task)
    try context.save()

    // today == start on a 2-day trip: departureDay & dayBeforeReturn are BOTH
    // .current. The primary mechanism here is the first-current-wins scan: it
    // hits departureDay first — now a non-packing phase with no tasks — and
    // returns nil, SHADOWING the dayBeforeReturn repack phase. That shadow is
    // the accepted edge in Decision 11 (tracked for follow-up). Secondarily,
    // the orphan duringTrip task is never returned (duringTrip is never current
    // on a 2-day trip).
    let result = TripDetailView.autoExpandPhase(for: trip, today: start, calendar: Self.calendar)
    #expect(result == nil)
  }
}
