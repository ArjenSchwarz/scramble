import Foundation

nonisolated enum TripStatus: Equatable, Sendable {
    case upcoming(daysAway: Int)
    case inProgress(currentDay: Int, totalDays: Int)
    case returningSoon(daysUntilEnd: Int)
    case completed(daysSinceEnd: Int)

    /// Threshold for `.returningSoon` in days. When `today` is within this many
    /// calendar days of `endDate` (inclusive), the status flips from
    /// `.inProgress` to `.returningSoon`.
    static let returningSoonThresholdDays = 2

    static func compute(
        startDate: Date,
        endDate: Date,
        today: Date,
        calendar: Calendar
    ) -> TripStatus {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let todayDay = calendar.startOfDay(for: today)

        if todayDay < start {
            let days = calendar.dateComponents([.day], from: todayDay, to: start).day ?? 0
            return .upcoming(daysAway: days)
        }

        if todayDay > end {
            let days = calendar.dateComponents([.day], from: end, to: todayDay).day ?? 0
            return .completed(daysSinceEnd: days)
        }

        let daysUntilEnd = calendar.dateComponents([.day], from: todayDay, to: end).day ?? 0
        if daysUntilEnd <= returningSoonThresholdDays {
            return .returningSoon(daysUntilEnd: daysUntilEnd)
        }

        let totalDays = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        let currentDay = (calendar.dateComponents([.day], from: start, to: todayDay).day ?? 0) + 1
        return .inProgress(currentDay: currentDay, totalDays: totalDays)
    }
}

nonisolated struct LocalizedTripStatus: Equatable, Sendable {
    let text: String

    init(_ status: TripStatus) {
        switch status {
        case .upcoming(let daysAway):
            text = daysAway == 1 ? "In 1 day" : "In \(daysAway) days"
        case .inProgress(let currentDay, let totalDays):
            text = "Day \(currentDay) of \(totalDays)"
        case .returningSoon(let daysUntilEnd):
            switch daysUntilEnd {
            case 0: text = "Returning today"
            case 1: text = "Returning tomorrow"
            default: text = "Returning in \(daysUntilEnd) days"
            }
        case .completed(let daysSinceEnd):
            text = daysSinceEnd == 1 ? "1 day ago" : "\(daysSinceEnd) days ago"
        }
    }
}
