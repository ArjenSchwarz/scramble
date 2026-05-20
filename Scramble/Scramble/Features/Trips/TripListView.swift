import SwiftData
import SwiftUI
import os

@MainActor struct TripListView: View {
  @Query(sort: \Trip.startDate, order: .forward) private var allTrips: [Trip]
  @Query(
    filter: #Predicate<MigrationJournalEntry> {
      $0.stateRaw == "stageBInProgress"
    }
  )
  private var inProgressJournals: [MigrationJournalEntry]
  @Query(
    filter: #Predicate<MigrationJournalEntry> {
      $0.stateRaw == "failed"
    }
  )
  private var failedJournals: [MigrationJournalEntry]
  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.modelContext) private var modelContext
  @Environment(\.globalsContainer) private var globalsContainer
  @Environment(\.localWriteHook) private var hook
  @Environment(\.notificationsService) private var notificationsService
  @Environment(\.zoneMigrationCoordinator) private var zoneMigrationCoordinator

  @State private var showCreateEditor = false
  @State private var previousExpanded = false
  @State private var toastMessage: String?

  private var syncingTripIDs: Set<UUID> {
    Set(inProgressJournals.map(\.tripID))
  }

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
      if !failedJournals.isEmpty {
        Section {
          MigrationRetryBanner { tripID in
            do {
              try zoneMigrationCoordinator?.retry(tripID: tripID)
            } catch {
              toastMessage = "Retry failed — try again later."
            }
          }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
      }

      Section("Active") {
        if activeTrips.isEmpty {
          Text("No active trips yet")
            .font(.subheadline)
            .foregroundStyle(variant.textSecondary)
            .listRowBackground(Color.clear)
        } else {
          ForEach(activeTrips) { trip in
            NavigationLink(value: trip) {
              TripRow(trip: trip, isSyncing: syncingTripIDs.contains(trip.id))
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
              TripRow(trip: trip, isSyncing: syncingTripIDs.contains(trip.id))
            }
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Trips")
    .sheet(isPresented: $showCreateEditor) {
      TripEditorView(mode: .create) { draft in
        let (newTrip, orphans) = TripPersistence.create(
          from: draft, in: modelContext, globals: globalsContainer.mainContext
        )
        do {
          try hook.commit(modelContext)
        } catch {
          modelContext.rollback()
          return false
        }
        do {
          try RulesEngineRunner(
            context: modelContext,
            mastersContext: globalsContainer.mainContext,
            hook: hook
          ).runForTrip(newTrip)
        } catch {
          modelLogger.error(
            "[RulesEngine.trip-edit-failed] tripID=\(newTrip.id, privacy: .public) error=\(String(describing: error), privacy: .public)"
          )
        }
        if !orphans.isEmpty {
          toastMessage = TripPersistence.orphanedParticipantMessage(count: orphans.count)
        }
        // Phase 6 Req 3.1 — ask for notification authorization on
        // first save of a trip whose dates produce at least one
        // eligible phase. The auth helper short-circuits when
        // status != .notDetermined or the trip yields zero plans.
        if let service = notificationsService {
          Task {
            await service.requestAuthorizationIfNeeded(forTrip: newTrip)
          }
        }
        return true
      }
    }
    .transientToast(message: $toastMessage)
  }

}

private struct TripRow: View {
  let trip: Trip
  let isSyncing: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Text(trip.name.isEmpty ? "Untitled trip" : trip.name)
          .font(.headline)
        if isSyncing {
          Text("Syncing…")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.blue))
            .accessibilityIdentifier("tripRow.syncingBadge")
        }
      }

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

      let snapshots = trip.participantSnapshots ?? []
      if !snapshots.isEmpty {
        HStack(spacing: -4) {
          ForEach(snapshots) { snapshot in
            PersonAvatar(
              name: snapshot.name, colorKey: snapshot.colourID, size: .compact
            )
          }
        }
        .padding(.top, 2)
      }
    }
    .padding(.vertical, 2)
  }
}
