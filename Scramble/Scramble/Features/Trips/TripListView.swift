import SwiftData
import SwiftUI

@MainActor struct TripListView: View {
  @Query(sort: \Trip.startDate, order: .forward) private var allTrips: [Trip]
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  @State private var showCreateEditor = false
  @State private var previousExpanded = false

  private var calendar: Calendar { Calendar.current }
  private var today: Date { calendar.startOfDay(for: .now) }

  private var activeTrips: [Trip] {
    allTrips
      .filter { calendar.startOfDay(for: $0.endDate) >= today }
      .sorted { $0.startDate < $1.startDate }
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

        newTripButton(accent: variant.accent)
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
      Text("Trip editor placeholder")
        .padding()
    }
  }

  private func newTripButton(accent: Color) -> some View {
    Button {
      showCreateEditor = true
    } label: {
      HStack(spacing: 8) {
        Image(systemName: "plus")
        Text("New Trip")
      }
      .font(.headline)
      .foregroundStyle(accent)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(
            accent.opacity(0.6),
            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
          )
      )
    }
    .buttonStyle(.borderless)
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
  }
}

private struct TripRow: View {
  let trip: Trip

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(trip.name.isEmpty ? "Untitled trip" : trip.name)
        .font(.headline)

      Text(formatDateRange(start: trip.startDate, end: trip.endDate))
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
    }
    .padding(.vertical, 2)
  }
}

private func formatDateRange(start: Date, end: Date) -> String {
  let style = Date.FormatStyle.dateTime.day().month(.abbreviated).year(.defaultDigits)
  return "\(start.formatted(style)) – \(end.formatted(style))"
}
