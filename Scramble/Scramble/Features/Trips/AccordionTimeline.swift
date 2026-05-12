import SwiftData
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

/// The vertical accordion that replaces `TripDetailView.phaseSpine`. Owns the
/// `ScrollViewReader` so a single expansion mutation both updates
/// `expandedPhase` and scrolls the new header into view inside the same
/// `withAnimation` block (Req 2.4).
///
/// Single-site mutation of `expandedPhase` per design: `PhaseRow.onToggle`
/// calls back here, and this view emits the medium-impact haptic
/// (Req 2.7), clears any open disclosure (Req 8.3), and performs the
/// `proxy.scrollTo(...)`.
struct AccordionTimeline: View {
  let trip: Trip
  let today: Date
  @Binding var expandedPhase: Phase?
  @Binding var openDisclosureTaskID: UUID?
  let onAddTaskInPhase: (Phase) -> Void
  let onEditTask: (TripTask) -> Void

  @Environment(\.theme) private var theme
  @Environment(\.colorScheme) private var colorScheme

  private var calendar: Calendar { .current }

  var body: some View {
    let variant = theme.variant(for: colorScheme)

    ScrollViewReader { proxy in
      VStack(spacing: 0) {
        ForEach(Phase.allCases, id: \.self) { phase in
          row(for: phase, variant: variant, proxy: proxy)
            .id(phase)
        }
      }
      #if DEBUG
        .overlay(alignment: .topLeading) { debugExpansionMarker }
      #endif
    }
    .task {
      expandedPhase = TripDetailView.autoExpandPhase(
        for: trip,
        today: today,
        calendar: calendar
      )
    }
  }

  // MARK: - PhaseRow factory

  @ViewBuilder
  private func row(
    for phase: Phase,
    variant: ThemeVariant,
    proxy: ScrollViewProxy
  ) -> some View {
    let state = TripDetailView.state(
      for: phase,
      today: today,
      start: trip.startDate,
      end: trip.endDate,
      calendar: calendar
    )
    let phaseTasks = trip.tasks.filter { $0.phase == phase && !$0.userDeletedOnThisTrip }
    let counts = TaskListHelpers.counts(phaseTasks)
    let compressed = PhaseDateMapping.isCompressed(phase, for: trip, calendar: calendar)
    let packing = phase == .departureDay || phase == .dayBeforeReturn
    let colour = variant.phaseColour(for: phase)

    PhaseRow(
      phase: phase,
      state: state,
      counts: counts,
      isExpanded: expandedPhase == phase,
      isCompressed: compressed,
      isPackingPhase: packing,
      phaseColour: colour,
      onToggle: { toggle(phase: phase, counts: counts, packing: packing, proxy: proxy) },
      content: {
        TaskListSection(
          trip: trip,
          phase: phase,
          phaseColour: colour,
          openDisclosureTaskID: $openDisclosureTaskID,
          onAdd: { onAddTaskInPhase(phase) },
          onEdit: onEditTask
        )
      }
    )
  }

  // MARK: - Expansion toggle

  private func toggle(
    phase: Phase,
    counts: PhaseCounts,
    packing: Bool,
    proxy: ScrollViewProxy
  ) {
    let expandable = counts.total > 0 || packing
    guard expandable else { return }
    #if canImport(UIKit)
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    #endif
    withAnimation(.easeInOut(duration: 0.25)) {
      expandedPhase = (expandedPhase == phase) ? nil : phase
      openDisclosureTaskID = nil
      if expandedPhase == phase {
        proxy.scrollTo(phase, anchor: .top)
      }
    }
  }

  // MARK: - Debug marker

  #if DEBUG
    /// Surfaces the currently expanded phase rawValue via an accessibility
    /// label so UI tests can poll it. The view itself is a 1×1 transparent
    /// element so it doesn't visually intrude.
    private var debugExpansionMarker: some View {
      Color.clear
        .frame(width: 1, height: 1)
        .accessibilityElement()
        .accessibilityIdentifier("tripDetail.accordion.expanded")
        .accessibilityLabel(expandedPhase?.rawValue ?? "")
    }
  #endif
}
