#if DEBUG
  import Foundation
  import SwiftData

  /// Pre-seeds the in-memory `ModelContainer` with a known fixture before the
  /// SwiftUI view tree first renders. Triggered by the launch argument
  /// `-seed-fixture <name>` set on `XCUIApplication.launchArguments` by UI tests.
  ///
  /// Only compiled in DEBUG builds; production binaries cannot be seeded.
  @MainActor
  enum UITestSeed {
    static let launchArgKey = "-seed-fixture"

    enum Fixture: String {
      case oneQualifyingTrip = "one-qualifying-trip"
      case oneNonQualifyingTrip = "one-non-qualifying-trip"
      case twoQualifyingTrips = "two-qualifying-trips"
      case singleEditableTrip = "single-editable-trip"
    }

    static func applyIfRequested(
      to container: ModelContainer,
      arguments: [String] = ProcessInfo.processInfo.arguments,
      today: Date = .now,
      calendar: Calendar = .current
    ) {
      guard let fixture = parseFixture(from: arguments) else { return }
      seed(fixture: fixture, in: container.mainContext, today: today, calendar: calendar)
    }

    static func parseFixture(from arguments: [String]) -> Fixture? {
      guard let idx = arguments.firstIndex(of: launchArgKey) else { return nil }
      let next = arguments.index(after: idx)
      guard next < arguments.endIndex else { return nil }
      return Fixture(rawValue: arguments[next])
    }

    static func seed(
      fixture: Fixture,
      in context: ModelContext,
      today: Date,
      calendar: Calendar
    ) {
      let day = calendar.startOfDay(for: today)
      switch fixture {
      case .oneQualifyingTrip:
        context.insert(
          Trip(
            name: "Active Trip",
            startDate: day,
            endDate: calendar.date(byAdding: .day, value: 5, to: day) ?? day
          )
        )
      case .oneNonQualifyingTrip:
        let start = calendar.date(byAdding: .day, value: 30, to: day) ?? day
        let end = calendar.date(byAdding: .day, value: 35, to: day) ?? day
        context.insert(Trip(name: "Future Trip", startDate: start, endDate: end))
      case .twoQualifyingTrips:
        context.insert(
          Trip(
            name: "Trip A",
            startDate: day,
            endDate: calendar.date(byAdding: .day, value: 5, to: day) ?? day
          )
        )
        context.insert(
          Trip(
            name: "Trip B",
            startDate: calendar.date(byAdding: .day, value: 1, to: day) ?? day,
            endDate: calendar.date(byAdding: .day, value: 10, to: day) ?? day
          )
        )
      case .singleEditableTrip:
        // Far-future start so this trip never auto-opens (start > today + 2 days),
        // letting the CRUD tests start from the Trip List and tap into detail
        // explicitly.
        let start = calendar.date(byAdding: .day, value: 30, to: day) ?? day
        let end = calendar.date(byAdding: .day, value: 35, to: day) ?? day
        context.insert(Trip(name: "Sample Trip", startDate: start, endDate: end))
      }
      try? context.save()
    }
  }
#endif
