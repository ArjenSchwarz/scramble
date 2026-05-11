import SwiftData
import SwiftUI

@MainActor struct TripDetailView: View {
  let trip: Trip

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss

  @State private var showEditor = false
  @State private var editAttributeFocus: TripAttribute?
  @State private var showDeleteConfirmation = false
  @State private var toastMessage: String?

  private var calendar: Calendar { Calendar.current }

  var body: some View {
    let variant = theme.variant(for: colorScheme)

    VStack(spacing: 0) {
      header(variant: variant)
        .background(variant.surface)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          chipRow(variant: variant)
          phaseSpine(variant: variant)
        }
        .padding(.vertical, 16)
      }
    }
    .background(variant.surface.opacity(0.3))
    .toolbar(.hidden, for: .tabBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
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
        modelContext.delete(trip)
        do {
          try modelContext.save()
          dismiss()
        } catch {
          modelContext.rollback()
          toastMessage = "Delete failed — try again."
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This will permanently remove the trip and all its data.")
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
        if !orphans.isEmpty {
          toastMessage = TripPersistence.orphanedParticipantMessage(count: orphans.count)
        }
        return true
      }
    }
    .transientToast(message: $toastMessage)
  }

  private func header(variant: ThemeVariant) -> some View {
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

      if !trip.participants.isEmpty {
        HStack(spacing: -6) {
          ForEach(trip.participants) { person in
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

  private func phaseSpine(variant: ThemeVariant) -> some View {
    VStack(spacing: 0) {
      ForEach(Array(Phase.allCases.enumerated()), id: \.element) { index, phase in
        HStack(alignment: .top, spacing: 16) {
          VStack(spacing: 0) {
            PhaseNodeMarker(
              state: Self.state(
                for: phase,
                today: .now,
                start: trip.startDate,
                end: trip.endDate,
                calendar: calendar
              ),
              phaseColor: variant.phaseColours[index],
              diameter: 22
            )
            if index < Phase.allCases.count - 1 {
              Rectangle()
                .fill(variant.surfaceBorder)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
            }
          }
          .frame(width: 24)

          Text(Self.label(for: phase))
            .font(.headline)
            .foregroundStyle(variant.textPrimary)
            .padding(.top, 1)
            .padding(.bottom, 24)

          Spacer(minLength: 0)
        }
        .frame(minHeight: 56)
      }
    }
    .padding(.horizontal)
  }

  static func label(for phase: Phase) -> String {
    switch phase {
    case .weeksBefore: "Weeks before"
    case .dayBefore: "Day before"
    case .departureDay: "Departure day"
    case .duringTrip: "During trip"
    case .dayBeforeReturn: "Day before return"
    case .returnDay: "Return day"
    case .afterTrip: "After trip"
    }
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
