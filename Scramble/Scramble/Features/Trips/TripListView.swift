import SwiftData
import SwiftUI
import os

@MainActor struct TripListView: View {
  @Query(sort: \Trip.startDate, order: .forward) private var allTrips: [Trip]
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.modelContext) private var modelContext

  @State private var showCreateEditor = false
  @State private var previousExpanded = false
  @State private var toastMessage: String?

  private var calendar: Calendar { Calendar.current }
  private var today: Date { calendar.startOfDay(for: .now) }

  // @Query already sorts by startDate ascending, so the Active filter doesn't
  // need a second sort. Previous is re-sorted by endDate descending per AC 5.2.
  private var activeTrips: [Trip] {
    allTrips.filter { calendar.startOfDay(for: $0.endDate) >= today }
  }

  private var previousTrips: [Trip] {
    allTrips
      .filter { calendar.startOfDay(for: $0.endDate) < today }
      .sorted { $0.endDate > $1.endDate }
  }

  var body: some View {
    let variant = theme.variant(for: colorScheme)

    List {
      Section("Active") {
        if activeTrips.isEmpty {
          Text("No active trips yet")
            .font(.subheadline)
            .foregroundStyle(variant.textSecondary)
            .listRowBackground(Color.clear)
        } else {
          ForEach(activeTrips) { trip in
            NavigationLink(value: trip) {
              TripRow(trip: trip)
            }
          }
        }

        DashedAddButton(title: "New Trip", accent: variant.accent) {
          showCreateEditor = true
        }
      }

      if !previousTrips.isEmpty {
        Section("Previous", isExpanded: $previousExpanded) {
          ForEach(previousTrips) { trip in
            NavigationLink(value: trip) {
              TripRow(trip: trip)
            }
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Trips")
    .sheet(isPresented: $showCreateEditor) {
      TripEditorView(mode: .create) { draft in
        let (newTrip, orphans) = TripPersistence.create(from: draft, in: modelContext)
        do {
          try modelContext.save()
        } catch {
          modelContext.rollback()
          return false
        }
        do {
          try RulesEngineRunner(context: modelContext).runForTrip(newTrip)
        } catch {
          modelLogger.error(
            "[RulesEngine.trip-edit-failed] tripID=\(newTrip.id, privacy: .public) error=\(String(describing: error), privacy: .public)"
          )
        }
        if !orphans.isEmpty {
          toastMessage = TripPersistence.orphanedParticipantMessage(count: orphans.count)
        }
        return true
      }
    }
    .transientToast(message: $toastMessage)
  }

}

private struct TripRow: View {
  let trip: Trip

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(trip.name.isEmpty ? "Untitled trip" : trip.name)
        .font(.headline)

      Text(formatTripDateRange(start: trip.startDate, end: trip.endDate))
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Text(
        LocalizedTripStatus(
          TripStatus.compute(
            startDate: trip.startDate,
            endDate: trip.endDate,
            today: .now,
            calendar: .current
          )
        ).text
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      let participants = trip.participants ?? []
      if !participants.isEmpty {
        HStack(spacing: -4) {
          ForEach(participants) { person in
            PersonAvatar(name: person.name, colorKey: person.colorKey, size: .compact)
          }
        }
        .padding(.top, 2)
      }
    }
    .padding(.vertical, 2)
  }
}
