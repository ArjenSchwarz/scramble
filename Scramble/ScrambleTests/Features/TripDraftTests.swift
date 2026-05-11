import Foundation
import Testing

@testable import Scramble

@Suite("TripDraft.validate")
struct TripDraftTests {

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

  private static func draft(
    name: String = "Iceland",
    start: Date = day(2026, 6, 10),
    end: Date = day(2026, 6, 20)
  ) -> TripDraft {
    TripDraft(
      name: name,
      startDate: start,
      endDate: end,
      attributes: TripAttributes(),
      participantIDs: []
    )
  }

  @Test("Valid draft → empty error map")
  func valid() {
    let errors = Self.draft().validate(calendar: Self.utc)
    #expect(errors.isEmpty)
  }

  @Test("Start == end on the same calendar day is valid")
  func sameDay() {
    let d = Self.day(2026, 6, 10)
    let errors = Self.draft(start: d, end: d).validate(calendar: Self.utc)
    #expect(errors.isEmpty)
  }

  @Test("Empty name → .name error only")
  func emptyName() {
    let errors = Self.draft(name: "").validate(calendar: Self.utc)
    #expect(Set(errors.keys) == [.name])
  }

  @Test("Whitespace-only name → .name error")
  func whitespaceName() {
    let errors = Self.draft(name: "   \n\t ").validate(calendar: Self.utc)
    #expect(Set(errors.keys) == [.name])
  }

  @Test("End before start → .dateRange error only")
  func endBeforeStart() {
    let errors = Self.draft(
      start: Self.day(2026, 6, 20),
      end: Self.day(2026, 6, 10)
    ).validate(calendar: Self.utc)
    #expect(Set(errors.keys) == [.dateRange])
  }

  @Test("Empty name AND end before start → both errors")
  func bothInvalid() {
    let errors = Self.draft(
      name: "",
      start: Self.day(2026, 6, 20),
      end: Self.day(2026, 6, 10)
    ).validate(calendar: Self.utc)
    #expect(Set(errors.keys) == [.name, .dateRange])
  }

  @Test("End-of-day timestamp on start, start-of-day on end (same calendar day) is valid")
  func sameDayDifferentTimes() {
    let startDay = Self.day(2026, 6, 10)
    let start = Self.utc.date(byAdding: .hour, value: 23, to: startDay)!
    let end = Self.utc.date(byAdding: .hour, value: 1, to: startDay)!
    let errors = Self.draft(start: start, end: end).validate(calendar: Self.utc)
    #expect(errors.isEmpty)
  }
}
