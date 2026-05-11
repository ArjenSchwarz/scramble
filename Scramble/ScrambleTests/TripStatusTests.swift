import Foundation
import Testing
@testable import Scramble

@Suite("TripStatus")
struct TripStatusTests {

    private static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 12,
        minute: Int = 0,
        calendar: Calendar = TripStatusTests.utc
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    // MARK: - upcoming

    @Test("upcoming: five days before start")
    func upcomingFiveDays() {
        let start = Self.date(2026, 6, 10)
        let end = Self.date(2026, 6, 20)
        let today = Self.date(2026, 6, 5)
        let status = TripStatus.compute(startDate: start, endDate: end, today: today, calendar: Self.utc)
        #expect(status == .upcoming(daysAway: 5))
    }

    @Test("upcoming: one day before start")
    func upcomingOneDay() {
        let start = Self.date(2026, 6, 10)
        let end = Self.date(2026, 6, 20)
        let today = Self.date(2026, 6, 9)
        let status = TripStatus.compute(startDate: start, endDate: end, today: today, calendar: Self.utc)
        #expect(status == .upcoming(daysAway: 1))
    }

    // MARK: - inProgress

    @Test("inProgress: today = start (long trip)")
    func inProgressTodayEqualsStart() {
        let start = Self.date(2026, 6, 10)
        let end = Self.date(2026, 6, 20) // 11 days inclusive
        let today = Self.date(2026, 6, 10)
        let status = TripStatus.compute(startDate: start, endDate: end, today: today, calendar: Self.utc)
        #expect(status == .inProgress(currentDay: 1, totalDays: 11))
    }

    @Test("inProgress: mid-trip")
    func inProgressMid() {
        let start = Self.date(2026, 6, 10)
        let end = Self.date(2026, 6, 20)
        let today = Self.date(2026, 6, 15)
        let status = TripStatus.compute(startDate: start, endDate: end, today: today, calendar: Self.utc)
        #expect(status == .inProgress(currentDay: 6, totalDays: 11))
    }

    @Test("inProgress: just outside the returningSoon window")
    func inProgressJustOutsideThreshold() {
        // daysUntilEnd = 3 → inProgress
        let start = Self.date(2026, 6, 10)
        let end = Self.date(2026, 6, 20)
        let today = Self.date(2026, 6, 17)
        let status = TripStatus.compute(startDate: start, endDate: end, today: today, calendar: Self.utc)
        #expect(status == .inProgress(currentDay: 8, totalDays: 11))
    }

    // MARK: - returningSoon (within 2 days of end)

    @Test("returningSoon: two days from end")
    func returningSoonTwo() {
        let start = Self.date(2026, 6, 10)
        let end = Self.date(2026, 6, 20)
        let today = Self.date(2026, 6, 18)
        let status = TripStatus.compute(startDate: start, endDate: end, today: today, calendar: Self.utc)
        #expect(status == .returningSoon(daysUntilEnd: 2))
    }

    @Test("returningSoon: one day from end")
    func returningSoonOne() {
        let start = Self.date(2026, 6, 10)
        let end = Self.date(2026, 6, 20)
        let today = Self.date(2026, 6, 19)
        let status = TripStatus.compute(startDate: start, endDate: end, today: today, calendar: Self.utc)
        #expect(status == .returningSoon(daysUntilEnd: 1))
    }

    @Test("returningSoon: today = end")
    func returningSoonZero() {
        let start = Self.date(2026, 6, 10)
        let end = Self.date(2026, 6, 20)
        let today = Self.date(2026, 6, 20)
        let status = TripStatus.compute(startDate: start, endDate: end, today: today, calendar: Self.utc)
        #expect(status == .returningSoon(daysUntilEnd: 0))
    }

    @Test("returningSoon: short trip — whole trip is within threshold")
    func returningSoonOneDayTrip() {
        let start = Self.date(2026, 6, 10)
        let end = Self.date(2026, 6, 10)
        let today = Self.date(2026, 6, 10)
        let status = TripStatus.compute(startDate: start, endDate: end, today: today, calendar: Self.utc)
        #expect(status == .returningSoon(daysUntilEnd: 0))
    }

    // MARK: - completed

    @Test("completed: one day after end")
    func completedOneDay() {
        let start = Self.date(2026, 6, 10)
        let end = Self.date(2026, 6, 20)
        let today = Self.date(2026, 6, 21)
        let status = TripStatus.compute(startDate: start, endDate: end, today: today, calendar: Self.utc)
        #expect(status == .completed(daysSinceEnd: 1))
    }

    @Test("completed: three days after end")
    func completedThreeDays() {
        let start = Self.date(2026, 6, 10)
        let end = Self.date(2026, 6, 20)
        let today = Self.date(2026, 6, 23)
        let status = TripStatus.compute(startDate: start, endDate: end, today: today, calendar: Self.utc)
        #expect(status == .completed(daysSinceEnd: 3))
    }

    // MARK: - day-granularity (midnight + time-of-day)

    @Test("today late in day equals start late in day → still day 1")
    func midnightBoundaryStart() {
        let start = Self.date(2026, 6, 10, hour: 23, minute: 30)
        let end = Self.date(2026, 6, 20, hour: 8)
        let today = Self.date(2026, 6, 10, hour: 0, minute: 30)
        let status = TripStatus.compute(startDate: start, endDate: end, today: today, calendar: Self.utc)
        #expect(status == .inProgress(currentDay: 1, totalDays: 11))
    }

    @Test("today next-day at 00:01 after start at 23:59 → day 2")
    func midnightBoundaryRollover() {
        let start = Self.date(2026, 6, 10, hour: 23, minute: 59)
        let end = Self.date(2026, 6, 20, hour: 8)
        let today = Self.date(2026, 6, 11, hour: 0, minute: 1)
        let status = TripStatus.compute(startDate: start, endDate: end, today: today, calendar: Self.utc)
        #expect(status == .inProgress(currentDay: 2, totalDays: 11))
    }

    // MARK: - time-zone determinism

    @Test("calendar timezone is honoured (Tokyo)")
    func timezoneShiftTokyo() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        // Same wall-clock dates in Tokyo, computed via Tokyo calendar
        let start = Self.date(2026, 6, 10, calendar: tokyo)
        let end = Self.date(2026, 6, 20, calendar: tokyo)
        let today = Self.date(2026, 6, 10, calendar: tokyo)
        let status = TripStatus.compute(startDate: start, endDate: end, today: today, calendar: tokyo)
        #expect(status == .inProgress(currentDay: 1, totalDays: 11))
    }
}
