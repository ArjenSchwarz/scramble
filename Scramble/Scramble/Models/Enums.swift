import Foundation

nonisolated enum Phase: String, Codable, CaseIterable, Hashable, Sendable {
    case weeksBefore
    case dayBefore
    case departureDay
    case duringTrip
    case dayBeforeReturn
    case returnDay
    case afterTrip
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
