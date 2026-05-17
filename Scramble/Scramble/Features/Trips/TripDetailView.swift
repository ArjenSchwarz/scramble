import SwiftData
import SwiftUI
import os

#if canImport(UIKit)
  import UIKit
#endif

@MainActor struct TripDetailView: View {
  let trip: Trip
  let today: Date

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @Environment(\.sharingService) private var sharingService
  @Environment(\.rulesLastEvaluatedTracker) private var rulesLastEvaluatedTracker

  @State private var showEditor = false
  @State private var editAttributeFocus: TripAttribute?
  @State private var showDeleteConfirmation = false
  @State private var showLeaveConfirmation = false
  @State private var toastMessage: String?
  @State private var expandedPhase: Phase?
  @State private var openDisclosureTaskID: UUID?
  @State private var pendingForm: TaskFormPresentation?
  @State private var packingSheetState: PackingSheetState?
  @State private var lastOpenedPackingPerson: Person?
  @AccessibilityFocusState private var packingSummaryFocus: UUID?

  private var calendar: Calendar { Calendar.current }

  /// `today` is captured at init time. If the app stays open across a date
  /// boundary the "current phase" calculation does not advance until the
  /// view re-initialises (typically on next navigation into the trip).
  /// Acceptable for Phase 3 — a scene-phase observer could refresh on
  /// foreground if midnight rollover becomes a visible issue in practice.
  init(trip: Trip, today: Date = .now) {
    self.trip = trip
    self.today = today
    _expandedPhase = State(
      initialValue: Self.autoExpandPhase(for: trip, today: today, calendar: .current)
    )
  }

  var body: some View {
    let variant = theme.variant(for: colorScheme)
    let ownerIdentity = sharingService?.ownerIdentity(forTrip: trip.id)
    let isParticipantOnShared: Bool = {
      if case .otherUser = ownerIdentity { return true }
      return false
    }()
    // Phase 5: locally-created trips have no `TripZoneState` until
    // either Stage B or `createShare` inserts one, so a nil identity is
    // treated as ownership for the share/manage affordances (Req 5.1).
    // Participant trips always carry a `TripZoneState` with `.otherUser`,
    // so they are reliably excluded.
    let isOwnerOfShared = sharingService != nil && !isParticipantOnShared

    VStack(spacing: 0) {
      header(variant: variant, isParticipantOnShared: isParticipantOnShared)
        .background(variant.surface)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          chipRow(variant: variant)
          if let sharingService, isOwnerOfShared || isParticipantOnShared {
            ParticipantsSection(
              trip: trip,
              isOwner: isOwnerOfShared,
              sharingService: sharingService
            )
          }
          AccordionTimeline(
            trip: trip,
            today: today,
            expandedPhase: $expandedPhase,
            openDisclosureTaskID: $openDisclosureTaskID,
            onAddTaskInPhase: { phase in
              pendingForm = .add(phase: phase, trip: trip)
            },
            onEditTask: { task in
              pendingForm = .edit(task: task)
            },
            onOpenPackingSheet: { person, mode in
              lastOpenedPackingPerson = person
              packingSheetState = PackingSheetState(person: person, mode: mode)
            },
            packingSummaryFocus: $packingSummaryFocus
          )
        }
        .padding(.vertical, 16)
      }
    }
    .environment(\.isParticipantViewingSharedTrip, isParticipantOnShared)
    .background(variant.surface.opacity(0.3))
    .toolbar(.hidden, for: .tabBar)
    .toolbar {
      if isOwnerOfShared, let sharingService {
        ToolbarItem(placement: .topBarTrailing) {
          ShareToolbarButton(trip: trip, sharingService: sharingService)
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          if !isParticipantOnShared {
            Button {
              editAttributeFocus = nil
              showEditor = true
            } label: {
              Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive) {
              showDeleteConfirmation = true
            } label: {
              Label("Delete Trip", systemImage: "trash")
            }
          } else {
            Button(role: .destructive) {
              showLeaveConfirmation = true
            } label: {
              Label("Leave Share", systemImage: "person.crop.circle.badge.minus")
            }
            .accessibilityIdentifier("tripDetail.leaveShareButton")
          }
        } label: {
          Image(systemName: "ellipsis.circle")
            .accessibilityLabel("Trip actions")
        }
      }
    }
    .confirmationDialog(
      "Delete this trip?",
      isPresented: $showDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("Delete \(trip.name.isEmpty ? "trip" : trip.name)", role: .destructive) {
        deleteTrip()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This will permanently remove the trip and all its data.")
    }
    .confirmationDialog(
      "Leave this trip?",
      isPresented: $showLeaveConfirmation,
      titleVisibility: .visible
    ) {
      Button("Leave \(trip.name.isEmpty ? "trip" : trip.name)", role: .destructive) {
        leaveShare()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "The trip will be removed from your devices once CloudKit confirms. The owner keeps all data."
      )
    }
    .sheet(item: $pendingForm) { presentation in
      TaskForm(
        mode: presentation,
        onSave: { pendingForm = nil },
        onCancel: { pendingForm = nil }
      )
    }
    .sheet(item: $packingSheetState, onDismiss: handlePackingSheetDismiss) { state in
      PackingSheet(
        trip: trip,
        person: state.person,
        mode: state.mode,
        onDismiss: { packingSheetState = nil }
      )
    }
    .sheet(isPresented: $showEditor) {
      TripEditorView(mode: .edit(trip), focusAttribute: editAttributeFocus) { draft in
        let orphans = TripPersistence.apply(draft, to: trip, in: modelContext)
        do {
          try modelContext.save()
        } catch {
          modelContext.rollback()
          return false
        }
        do {
          try RulesEngineRunner(context: modelContext).runForTrip(trip)
        } catch {
          modelLogger.error(
            "[RulesEngine.trip-edit-failed] tripID=\(trip.id, privacy: .public) error=\(String(describing: error), privacy: .public)"
          )
        }
        if !orphans.isEmpty {
          toastMessage = TripPersistence.orphanedParticipantMessage(count: orphans.count)
        }
        return true
      }
    }
    .transientToast(message: $toastMessage)
    #if DEBUG
      .background { inspectionMarkers }
    #endif
  }

  /// Owner-side delete (Req 1.4). Removes the trip from the globals
  /// container and asks `SharingService` to tear down the trip's
  /// `TripZoneState` + queue the `CKRecordZone` deletion on the private
  /// engine.
  private func deleteTrip() {
    let tripID = trip.id
    modelContext.delete(trip)
    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
      toastMessage = "Delete failed — try again."
      return
    }
    if let sharingService {
      Task {
        do {
          try await sharingService.deleteOwnedTrip(forTrip: tripID)
        } catch {
          modelLogger.error(
            "[TripDetailView.delete-zone-failed] tripID=\(tripID, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
          )
        }
      }
    }
    dismiss()
  }

  /// Participant-side leave-share (Req 6.5). Asks `SharingService` to
  /// delete the shared zone; the trip disappears locally on the next
  /// zone-removed notification (or on next launch).
  private func leaveShare() {
    guard let sharingService else { return }
    let tripID = trip.id
    Task {
      do {
        try await sharingService.leaveShare(forTrip: tripID)
        dismiss()
      } catch {
        modelLogger.error(
          "[TripDetailView.leave-share-failed] tripID=\(tripID, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
        )
        toastMessage = "Leaving the share failed — try again."
      }
    }
  }

  private func handlePackingSheetDismiss() {
    guard let person = lastOpenedPackingPerson else { return }
    let participantIDs = (trip.participants ?? []).map(\.id)
    if participantIDs.contains(person.id) {
      packingSummaryFocus = person.id
    } else {
      packingSummaryFocus = nil
      #if canImport(UIKit)
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
      #endif
    }
    lastOpenedPackingPerson = nil
  }

  #if DEBUG
    /// Debug-only invisible markers that expose the trip's rule-driven items so
    /// `RulesEnginePopulationUITests` / `ColdLaunchSequencingUITests` can assert
    /// the engine populated the expected refs. No Phase 3 timeline UI consumes
    /// these records yet; without the marker view the tests have nothing to
    /// query. Format: `tripDetail.{packingItem|task}.{matching|unmatched}.{name}`.
    private var inspectionMarkers: some View {
      ZStack {
        ForEach(trip.packingItems ?? []) { item in
          Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier(Self.inspectionID(packingItem: item))
        }
        ForEach(trip.tasks ?? []) { task in
          Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier(Self.inspectionID(task: task))
        }
      }
    }

    static func inspectionID(packingItem item: TripPackingItem) -> String {
      let flag = item.currentlyMatchesRules ? "matching" : "unmatched"
      return "tripDetail.packingItem.\(flag).\(item.name)"
    }

    static func inspectionID(task: TripTask) -> String {
      let flag = task.currentlyMatchesRules ? "matching" : "unmatched"
      return "tripDetail.task.\(flag).\(task.name)"
    }
  #endif

  private func header(variant: ThemeVariant, isParticipantOnShared: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(trip.name.isEmpty ? "Untitled trip" : trip.name)
        .font(.title2.weight(.semibold))
        .foregroundStyle(variant.textPrimary)

      Text(formatTripDateRange(start: trip.startDate, end: trip.endDate))
        .font(.subheadline)
        .foregroundStyle(variant.textSecondary)

      Text(
        LocalizedTripStatus(
          TripStatus.compute(
            startDate: trip.startDate,
            endDate: trip.endDate,
            today: .now,
            calendar: calendar
          )
        ).text
      )
      .font(.caption)
      .foregroundStyle(variant.textSecondary)

      if let lastEvaluated = lastEvaluatedTime(when: isParticipantOnShared) {
        Text(rulesLastEvaluatedText(lastEvaluated))
          .font(.caption)
          .foregroundStyle(variant.textSecondary)
          .accessibilityIdentifier("tripDetail.rulesLastEvaluated")
      }

      let participants = trip.participants ?? []
      if !participants.isEmpty {
        HStack(spacing: -6) {
          ForEach(participants) { person in
            PersonAvatar(name: person.name, colorKey: person.colorKey, size: .standard)
          }
        }
        .padding(.top, 4)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal)
    .padding(.vertical, 12)
  }

  /// Returns the last-evaluated timestamp to render in the participant
  /// subline, or `nil` when the line should be omitted (owner-viewed,
  /// no tracker available, or no event yet observed).
  private func lastEvaluatedTime(when isParticipantOnShared: Bool) -> Date? {
    guard isParticipantOnShared else { return nil }
    return rulesLastEvaluatedTracker?.time(forTrip: trip.id)
  }

  private static let rulesLastEvaluatedFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter
  }()

  private func rulesLastEvaluatedText(_ date: Date) -> String {
    let relative = Self.rulesLastEvaluatedFormatter.localizedString(for: date, relativeTo: .now)
    return "Rules last evaluated \(relative)"
  }

  private func chipRow(variant: ThemeVariant) -> some View {
    let attrs = trip.attributes
    let pairs: [(TripAttribute, String)] = TripAttribute.allCases.flatMap { attr in
      attrs.selected(attr).map { (attr, $0) }
    }

    return Group {
      if pairs.isEmpty {
        EmptyView()
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
              let (attr, value) = pair
              Button {
                editAttributeFocus = attr
                showEditor = true
              } label: {
                Text(value.attributeValueDisplay)
                  .font(.subheadline)
                  .padding(.horizontal, 12)
                  .padding(.vertical, 6)
                  .background(
                    Capsule().fill(variant.surface)
                  )
                  .overlay(
                    Capsule().strokeBorder(variant.surfaceBorder, lineWidth: 1)
                  )
                  .foregroundStyle(variant.textPrimary)
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal)
        }
      }
    }
  }

  /// Picks the phase that should auto-expand when Trip Detail appears.
  ///
  /// Implements Req 2.3 + 3.2: finds the `.current` phase via the existing
  /// `state(for:today:start:end:calendar)` helper, then gates expandability:
  /// - Compressed `duringTrip` is never auto-expanded.
  /// - Packing phases (`departureDay`, `dayBeforeReturn`) are always
  ///   expandable, even with no tasks (the Phase 4 packing summary will
  ///   live there).
  /// - Other phases are expandable only when at least one non-soft-deleted
  ///   task is attached.
  ///
  /// Returns `nil` when no phase is `.current` or when the current phase is
  /// non-expandable; `TripDetailView`'s init then opens with the accordion
  /// fully collapsed.
  static func autoExpandPhase(
    for trip: Trip,
    today: Date,
    calendar: Calendar
  ) -> Phase? {
    let current = Phase.allCases.first { phase in
      Self.state(
        for: phase,
        today: today,
        start: trip.startDate,
        end: trip.endDate,
        calendar: calendar
      ) == .current
    }
    guard let phase = current else { return nil }

    if PhaseDateMapping.isCompressed(phase, for: trip, calendar: calendar) {
      return nil
    }
    if phase == .departureDay || phase == .dayBeforeReturn {
      return phase
    }
    let hasVisibleTask = (trip.tasks ?? []).contains { task in
      task.phase == phase && !task.userDeletedOnThisTrip
    }
    return hasVisibleTask ? phase : nil
  }

  // swiftlint:disable:next cyclomatic_complexity
  static func state(
    for phase: Phase,
    today: Date,
    start: Date,
    end: Date,
    calendar: Calendar
  ) -> PhaseNodeState {
    let today = calendar.startOfDay(for: today)
    let start = calendar.startOfDay(for: start)
    let end = calendar.startOfDay(for: end)
    let dayBefore = calendar.date(byAdding: .day, value: -1, to: start) ?? start
    let dayBeforeReturn = calendar.date(byAdding: .day, value: -1, to: end) ?? end

    switch phase {
    case .weeksBefore:
      return today < dayBefore ? .current : .past
    case .dayBefore:
      if today < dayBefore { return .future }
      if today == dayBefore { return .current }
      return .past
    case .departureDay:
      if today < start { return .future }
      if today == start { return .current }
      return .past
    case .duringTrip:
      if today <= start { return .future }
      if today >= end { return .past }
      return .current
    case .dayBeforeReturn:
      if today < dayBeforeReturn { return .future }
      if today == dayBeforeReturn { return .current }
      return .past
    case .returnDay:
      if today < end { return .future }
      if today == end { return .current }
      return .past
    case .afterTrip:
      return today <= end ? .future : .current
    }
  }
}
