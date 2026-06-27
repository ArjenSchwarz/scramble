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
  let onOpenPackingSheet: (Person, PackingMode) -> Void
  @AccessibilityFocusState.Binding var packingSummaryFocus: UUID?

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
    let phaseTasks = (trip.tasks ?? []).filter { $0.phase == phase && !$0.userDeletedOnThisTrip }
    let counts = TaskListHelpers.counts(phaseTasks)
    let compressed = PhaseDateMapping.isCompressed(phase, for: trip, calendar: calendar)
    let packingMode = phase.packingMode
    let colour = variant.phaseColour(for: phase)
    let packingSubline = packingMode.map { PackingListHelpers.phaseSubline(trip, mode: $0) }

    PhaseRow(
      phase: phase,
      state: state,
      counts: counts,
      isExpanded: expandedPhase == phase,
      isCompressed: compressed,
      phaseColour: colour,
      packingSubline: packingSubline,
      onToggle: { toggle(phase: phase, counts: counts, proxy: proxy) },
      content: {
        VStack(alignment: .leading, spacing: 12) {
          TaskListSection(
            trip: trip,
            phase: phase,
            phaseColour: colour,
            openDisclosureTaskID: $openDisclosureTaskID,
            onAdd: { onAddTaskInPhase(phase) },
            onEdit: onEditTask
          )

          if let mode = packingMode {
            PackingSummarySection(
              trip: trip,
              mode: mode,
              onOpenSheet: onOpenPackingSheet,
              focusOnDismiss: $packingSummaryFocus
            )
          }
        }
      }
    )
  }

  // MARK: - Expansion toggle

  private func toggle(
    phase: Phase,
    counts: PhaseCounts,
    proxy: ScrollViewProxy
  ) {
    // Defensive: the tap gesture is only attached when the row is expandable
    // (PhaseRow gates on the same predicate), but derive from the single
    // source of truth rather than threading a precomputed flag through.
    guard counts.total > 0 || phase.packingMode != nil else { return }
    #if canImport(UIKit)
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    #endif
    // Phase 6 Req 7.1 / 7.4 — shared duration; Reduce Motion users
    // still get an animation but the content transition cross-fades
    // via the inert-modifier pattern (the content's own opacity
    // animates inside this same block).
    withAnimation(.scrambleStandard) {
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
