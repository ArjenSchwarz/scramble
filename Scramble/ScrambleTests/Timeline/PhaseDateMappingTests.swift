import Foundation
import Testing

@testable import Scramble

@Suite("PhaseDateMapping")
@MainActor
struct PhaseDateMappingTests {

  // MARK: - Helpers

  private static var calendar: Calendar { Calendar(identifier: .gregorian) }

  private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var comps = DateComponents()
    comps.year = y
    comps.month = m
    comps.day = d
    return calendar.date(from: comps)!
  }

  private static func trip(start: Date, end: Date) -> Trip {
    Trip(name: "T", startDate: start, endDate: end)
  }

  // MARK: - Multi-day trip (2026-06-01 ... 2026-06-07)

  @Test("Multi-day trip: weeksBefore is open-ended (durationDays == nil, dateRange == nil)")
  func multiDayWeeksBefore() {
    let t = Self.trip(start: Self.date(2026, 6, 1), end: Self.date(2026, 6, 7))
    #expect(PhaseDateMapping.dateRange(.weeksBefore, for: t, calendar: Self.calendar) == nil)
    #expect(PhaseDateMapping.durationDays(.weeksBefore, for: t, calendar: Self.calendar) == nil)
    #expect(PhaseDateMapping.isCompressed(.weeksBefore, for: t, calendar: Self.calendar) == false)
  }

  @Test("Multi-day trip: dayBefore is S-1 (1 day)")
  func multiDayDayBefore() {
    let t = Self.trip(start: Self.date(2026, 6, 1), end: Self.date(2026, 6, 7))
    let range = PhaseDateMapping.dateRange(.dayBefore, for: t, calendar: Self.calendar)
    #expect(range?.lowerBound == Self.date(2026, 5, 31))
    #expect(range?.upperBound == Self.date(2026, 5, 31))
    #expect(PhaseDateMapping.durationDays(.dayBefore, for: t, calendar: Self.calendar) == 1)
    #expect(PhaseDateMapping.isCompressed(.dayBefore, for: t, calendar: Self.calendar) == false)
  }

  @Test("Multi-day trip: departureDay is S (1 day)")
  func multiDayDepartureDay() {
    let t = Self.trip(start: Self.date(2026, 6, 1), end: Self.date(2026, 6, 7))
    let range = PhaseDateMapping.dateRange(.departureDay, for: t, calendar: Self.calendar)
    #expect(range?.lowerBound == Self.date(2026, 6, 1))
    #expect(range?.upperBound == Self.date(2026, 6, 1))
    #expect(PhaseDateMapping.durationDays(.departureDay, for: t, calendar: Self.calendar) == 1)
    #expect(PhaseDateMapping.isCompressed(.departureDay, for: t, calendar: Self.calendar) == false)
  }

  @Test("Multi-day trip: duringTrip is S+1 through E-1 (5 days for 6/1..6/7)")
  func multiDayDuringTrip() {
    let t = Self.trip(start: Self.date(2026, 6, 1), end: Self.date(2026, 6, 7))
    let range = PhaseDateMapping.dateRange(.duringTrip, for: t, calendar: Self.calendar)
    #expect(range?.lowerBound == Self.date(2026, 6, 2))
    #expect(range?.upperBound == Self.date(2026, 6, 6))
    #expect(PhaseDateMapping.durationDays(.duringTrip, for: t, calendar: Self.calendar) == 5)
    #expect(PhaseDateMapping.isCompressed(.duringTrip, for: t, calendar: Self.calendar) == false)
  }

  @Test("Multi-day trip: dayBeforeReturn is E-1 (1 day)")
  func multiDayDayBeforeReturn() {
    let t = Self.trip(start: Self.date(2026, 6, 1), end: Self.date(2026, 6, 7))
    let range = PhaseDateMapping.dateRange(.dayBeforeReturn, for: t, calendar: Self.calendar)
    #expect(range?.lowerBound == Self.date(2026, 6, 6))
    #expect(range?.upperBound == Self.date(2026, 6, 6))
    #expect(PhaseDateMapping.durationDays(.dayBeforeReturn, for: t, calendar: Self.calendar) == 1)
    #expect(
      PhaseDateMapping.isCompressed(.dayBeforeReturn, for: t, calendar: Self.calendar) == false)
  }

  @Test("Multi-day trip: returnDay is E (1 day)")
  func multiDayReturnDay() {
    let t = Self.trip(start: Self.date(2026, 6, 1), end: Self.date(2026, 6, 7))
    let range = PhaseDateMapping.dateRange(.returnDay, for: t, calendar: Self.calendar)
    #expect(range?.lowerBound == Self.date(2026, 6, 7))
    #expect(range?.upperBound == Self.date(2026, 6, 7))
    #expect(PhaseDateMapping.durationDays(.returnDay, for: t, calendar: Self.calendar) == 1)
    #expect(PhaseDateMapping.isCompressed(.returnDay, for: t, calendar: Self.calendar) == false)
  }

  @Test("Multi-day trip: afterTrip is open-ended")
  func multiDayAfterTrip() {
    let t = Self.trip(start: Self.date(2026, 6, 1), end: Self.date(2026, 6, 7))
    #expect(PhaseDateMapping.dateRange(.afterTrip, for: t, calendar: Self.calendar) == nil)
    #expect(PhaseDateMapping.durationDays(.afterTrip, for: t, calendar: Self.calendar) == nil)
    #expect(PhaseDateMapping.isCompressed(.afterTrip, for: t, calendar: Self.calendar) == false)
  }

  // MARK: - 1-day trip (start == end)

  @Test("1-day trip: duringTrip has zero duration and is compressed")
  func oneDayDuringTrip() {
    let t = Self.trip(start: Self.date(2026, 6, 1), end: Self.date(2026, 6, 1))
    #expect(PhaseDateMapping.durationDays(.duringTrip, for: t, calendar: Self.calendar) == 0)
    #expect(PhaseDateMapping.isCompressed(.duringTrip, for: t, calendar: Self.calendar) == true)
  }

  @Test(
    "1-day trip: dayBefore, departureDay, dayBeforeReturn, returnDay still 1 day each (uncompressed)"
  )
  func oneDaySingleDayPhases() {
    let t = Self.trip(start: Self.date(2026, 6, 1), end: Self.date(2026, 6, 1))
    #expect(PhaseDateMapping.durationDays(.dayBefore, for: t, calendar: Self.calendar) == 1)
    #expect(PhaseDateMapping.durationDays(.departureDay, for: t, calendar: Self.calendar) == 1)
    #expect(PhaseDateMapping.durationDays(.dayBeforeReturn, for: t, calendar: Self.calendar) == 1)
    #expect(PhaseDateMapping.durationDays(.returnDay, for: t, calendar: Self.calendar) == 1)
    #expect(PhaseDateMapping.isCompressed(.dayBefore, for: t, calendar: Self.calendar) == false)
    #expect(PhaseDateMapping.isCompressed(.departureDay, for: t, calendar: Self.calendar) == false)
    #expect(
      PhaseDateMapping.isCompressed(.dayBeforeReturn, for: t, calendar: Self.calendar) == false)
    #expect(PhaseDateMapping.isCompressed(.returnDay, for: t, calendar: Self.calendar) == false)
  }

  // MARK: - 2-day trip (E = S + 1)

  @Test("2-day trip: duringTrip is zero-duration and compressed")
  func twoDayDuringTrip() {
    let t = Self.trip(start: Self.date(2026, 6, 1), end: Self.date(2026, 6, 2))
    #expect(PhaseDateMapping.durationDays(.duringTrip, for: t, calendar: Self.calendar) == 0)
    #expect(PhaseDateMapping.isCompressed(.duringTrip, for: t, calendar: Self.calendar) == true)
  }

  @Test("2-day trip: every other phase is uncompressed and 1 day or open-ended")
  func twoDayOtherPhases() {
    let t = Self.trip(start: Self.date(2026, 6, 1), end: Self.date(2026, 6, 2))
    #expect(PhaseDateMapping.durationDays(.dayBefore, for: t, calendar: Self.calendar) == 1)
    #expect(PhaseDateMapping.durationDays(.departureDay, for: t, calendar: Self.calendar) == 1)
    #expect(PhaseDateMapping.durationDays(.dayBeforeReturn, for: t, calendar: Self.calendar) == 1)
    #expect(PhaseDateMapping.durationDays(.returnDay, for: t, calendar: Self.calendar) == 1)
    #expect(PhaseDateMapping.durationDays(.weeksBefore, for: t, calendar: Self.calendar) == nil)
    #expect(PhaseDateMapping.durationDays(.afterTrip, for: t, calendar: Self.calendar) == nil)
    for phase in Phase.allCases where phase != .duringTrip {
      #expect(
        PhaseDateMapping.isCompressed(phase, for: t, calendar: Self.calendar) == false,
        "Only duringTrip should be compressed; got isCompressed=true for \(phase)"
      )
    }
  }

  // MARK: - Property: only duringTrip can be compressed; iff duration == 0

  @Test("Property: isCompressed true iff phase == .duringTrip && durationDays == 0")
  func compressedIff() {
    // Cover trips of various lengths from 1-day through 10-day.
    let trips: [Trip] = (0...9).map { delta in
      Self.trip(
        start: Self.date(2026, 6, 1),
        end: Self.calendar.date(byAdding: .day, value: delta, to: Self.date(2026, 6, 1))!
      )
    }
    for t in trips {
      for phase in Phase.allCases {
        let dur = PhaseDateMapping.durationDays(phase, for: t, calendar: Self.calendar)
        let isCompressed = PhaseDateMapping.isCompressed(phase, for: t, calendar: Self.calendar)
        let expected = (phase == .duringTrip && dur == 0)
        #expect(
          isCompressed == expected,
          "phase=\(phase) start=\(t.startDate) end=\(t.endDate) dur=\(dur) expectedCompressed=\(expected) got=\(isCompressed)"
        )
      }
    }
  }
}
