import Foundation
import SwiftData
import Testing

@testable import Scramble

@Suite("singleQualifyingTrip")
@MainActor
struct TripsTabPredicateTests {

  private static let utc: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
  }()

  private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var c = DateComponents()
    c.year = year
    c.month = month
    c.day = day
    return utc.date(from: c)!
  }

  private static func trip(
    name: String = "Trip",
    start: Date,
    end: Date
  ) -> Trip {
    Trip(name: name, startDate: start, endDate: end)
  }

  private static let today = day(2026, 6, 10)
  private static let plusTwo = day(2026, 6, 12)  // today + 2
  private static let plusThree = day(2026, 6, 13)  // today + 3
  private static let minusOne = day(2026, 6, 9)  // today - 1

  // MARK: - empty / single qualifying / non-qualifying

  @Test("empty trips → nil")
  func emptyReturnsNil() {
    let result = singleQualifyingTrip(in: [], today: Self.today, calendar: Self.utc)
    #expect(result == nil)
  }

  @Test("one qualifying trip → that trip")
  func oneQualifyingReturnsTrip() {
    let t = Self.trip(start: Self.today, end: Self.plusThree)
    let result = singleQualifyingTrip(in: [t], today: Self.today, calendar: Self.utc)
    #expect(result === t)
  }

  @Test("one non-qualifying (start > today+2d) → nil")
  func startTooFarReturnsNil() {
    let t = Self.trip(start: Self.plusThree, end: Self.day(2026, 6, 20))
    let result = singleQualifyingTrip(in: [t], today: Self.today, calendar: Self.utc)
    #expect(result == nil)
  }

  @Test("one non-qualifying (end < today) → nil")
  func endInPastReturnsNil() {
    let t = Self.trip(start: Self.day(2026, 6, 1), end: Self.minusOne)
    let result = singleQualifyingTrip(in: [t], today: Self.today, calendar: Self.utc)
    #expect(result == nil)
  }

  // MARK: - multiple qualifying

  @Test("two qualifying → nil")
  func twoQualifyingReturnsNil() {
    let a = Self.trip(name: "A", start: Self.today, end: Self.day(2026, 6, 15))
    let b = Self.trip(name: "B", start: Self.plusTwo, end: Self.day(2026, 6, 20))
    let result = singleQualifyingTrip(in: [a, b], today: Self.today, calendar: Self.utc)
    #expect(result == nil)
  }

  // MARK: - edge cases

  @Test("start == today + 2 (boundary, qualifies)")
  func startEqualsBoundary() {
    let t = Self.trip(start: Self.plusTwo, end: Self.day(2026, 6, 20))
    let result = singleQualifyingTrip(in: [t], today: Self.today, calendar: Self.utc)
    #expect(result === t)
  }

  @Test("end == today (boundary, qualifies)")
  func endEqualsToday() {
    let t = Self.trip(start: Self.day(2026, 6, 1), end: Self.today)
    let result = singleQualifyingTrip(in: [t], today: Self.today, calendar: Self.utc)
    #expect(result === t)
  }

  @Test("start == today (qualifies)")
  func startEqualsToday() {
    let t = Self.trip(start: Self.today, end: Self.day(2026, 6, 20))
    let result = singleQualifyingTrip(in: [t], today: Self.today, calendar: Self.utc)
    #expect(result === t)
  }

  @Test("time-of-day on today doesn't change calendar-day comparison")
  func todayLateInDayBoundary() {
    let lateToday = Self.utc.date(byAdding: .hour, value: 23, to: Self.today)!
    let t = Self.trip(start: Self.plusTwo, end: Self.day(2026, 6, 20))
    let result = singleQualifyingTrip(in: [t], today: lateToday, calendar: Self.utc)
    #expect(result === t)
  }

  @Test("among one qualifying + one in past → the qualifying trip")
  func mixedReturnsTheQualifyingOne() {
    let past = Self.trip(name: "Past", start: Self.day(2026, 5, 1), end: Self.minusOne)
    let now = Self.trip(name: "Now", start: Self.today, end: Self.day(2026, 6, 15))
    let result = singleQualifyingTrip(in: [past, now], today: Self.today, calendar: Self.utc)
    #expect(result === now)
  }

  @Test("among one qualifying + one too-far-future → the qualifying trip")
  func mixedFutureReturnsTheQualifyingOne() {
    let future = Self.trip(name: "Far", start: Self.plusThree, end: Self.day(2026, 6, 25))
    let now = Self.trip(name: "Now", start: Self.today, end: Self.day(2026, 6, 15))
    let result = singleQualifyingTrip(in: [now, future], today: Self.today, calendar: Self.utc)
    #expect(result === now)
  }
}
