import SwiftData
import SwiftUI

@MainActor struct TripsTab: View {
  @Query(sort: \Trip.startDate, order: .forward) private var trips: [Trip]

  /// Phase 6 — externalised so `RootView` can push to the same stack
  /// when consuming an `ActivationRoute` from a notification tap.
  @Binding var path: NavigationPath

  // NOTE: @State is intentional — NOT @SceneStorage. State restoration would
  // persist `didAttemptAutoOpen` across kill-then-relaunch and re-suppress the
  // auto-open behaviour mandated by requirement 5.6. See design.md
  // "Trip List + auto-open".
  @State private var didAttemptAutoOpen = false

  init(path: Binding<NavigationPath> = .constant(NavigationPath())) {
    self._path = path
  }

  var body: some View {
    NavigationStack(path: $path) {
      TripListView()
        .navigationDestination(for: Trip.self) { trip in
          TripDetailView(trip: trip)
            .toolbar(.hidden, for: .tabBar)
        }
    }
    .task(id: "trips-tab-mount") {
      guard !didAttemptAutoOpen else { return }
      didAttemptAutoOpen = true
      if let target = singleQualifyingTrip(
        in: trips,
        today: .now,
        calendar: .current
      ) {
        path.append(target)
      }
    }
  }
}

/// Returns the single `Trip` that qualifies for auto-open on cold launch, if
/// exactly one exists. A trip qualifies when:
///   - its start date is on or before `today + 2 calendar days`, AND
///   - its end date is on or after `today` (calendar-day granularity).
/// Zero or two-or-more qualifying trips return `nil` (per requirement 5.6).
@MainActor func singleQualifyingTrip(
  in trips: [Trip],
  today: Date,
  calendar: Calendar
) -> Trip? {
  let todayDay = calendar.startOfDay(for: today)
  guard let cutoff = calendar.date(byAdding: .day, value: 2, to: todayDay) else {
    return nil
  }
  let qualifying = trips.filter { trip in
    let start = calendar.startOfDay(for: trip.startDate)
    let end = calendar.startOfDay(for: trip.endDate)
    return start <= cutoff && end >= todayDay
  }
  return qualifying.count == 1 ? qualifying.first : nil
}
