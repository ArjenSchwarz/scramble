import Foundation

/// Value-type editor state for the trip create/edit screen.
///
/// `validate()` compares dates at calendar-day granularity per Decision 3: a draft whose
/// `startDate` and `endDate` fall on the same day (regardless of time-of-day) is valid.
nonisolated struct TripDraft: Equatable, Sendable {
  var name: String
  var startDate: Date
  var endDate: Date
  var attributes: TripAttributes
  var participantIDs: [UUID]
  /// ISO 3166-1 alpha-2, uppercase or `nil`. Phase 6 — Decision 5.
  var countryCode: String?

  nonisolated enum Field: Hashable, Sendable {
    case name
    case dateRange
    case countryCode
  }

  func validate(calendar: Calendar = .current) -> [Field: String] {
    var errors: [Field: String] = [:]

    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      errors[.name] = "Name is required"
    }

    let startDay = calendar.startOfDay(for: startDate)
    let endDay = calendar.startOfDay(for: endDate)
    if endDay < startDay {
      errors[.dateRange] = "End date must be on or after start date"
    }

    return errors
  }
}

extension TripDraft {
  /// An empty draft used by the editor in `.create` mode. `startDate` and `endDate`
  /// default to today so the date pickers open at a sensible value.
  nonisolated static func newDraft(today: Date = .now, calendar: Calendar = .current) -> TripDraft {
    let day = calendar.startOfDay(for: today)
    return TripDraft(
      name: "",
      startDate: day,
      endDate: day,
      attributes: TripAttributes(),
      participantIDs: [],
      countryCode: nil
    )
  }

  /// Normalises a user-entered country code. Returns `nil` if the
  /// stripped string is empty (the editor treats this as "clear"), or
  /// the uppercased two-letter code if the input is exactly two ASCII
  /// letters. Any other input is rejected by returning `.invalid`.
  nonisolated enum CountryCodeNormalisation: Equatable {
    case clear
    case set(String)
    case invalid
  }

  nonisolated static func normaliseCountryCode(_ raw: String) -> CountryCodeNormalisation {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return .clear }
    guard trimmed.count == 2,
      trimmed.allSatisfy({ $0.isASCII && $0.isLetter })
    else {
      return .invalid
    }
    return .set(trimmed.uppercased())
  }

  /// Snapshot the current state of `trip` into a draft used by the editor in `.edit` mode.
  /// Phase 5.1: participant IDs come from `trip.participantSnapshots` so the
  /// read stays inside `tripsLocal` and avoids the V2-era cross-container
  /// `Trip.participants → Person` traversal forbidden by constraint C3.
  @MainActor
  init(from trip: Trip) {
    self.name = trip.name
    self.startDate = trip.startDate
    self.endDate = trip.endDate
    self.attributes = trip.attributes
    self.participantIDs = (trip.participantSnapshots ?? [])
      .filter(\.isRosterMember)
      .map(\.personID)
    self.countryCode = trip.countryCode
  }
}
