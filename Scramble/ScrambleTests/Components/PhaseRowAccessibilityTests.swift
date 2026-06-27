import SwiftUI
import Testing

@testable import Scramble

/// Phase 6 Req 9.1 — `PhaseRow.accessibilityLabel` / `accessibilityHint`
/// wording coverage. Pure-string helpers so the test exercises them
/// without spinning up SwiftUI / a SwiftData container.
@Suite("PhaseRow accessibility")
struct PhaseRowAccessibilityTests {

  // MARK: - Label wording

  @Test("Label includes phase name, state word, and N of M tasks complete")
  func labelWithTaskCount() {
    let label = PhaseRow<EmptyView>.accessibilityLabel(
      phase: .departureDay,
      state: .current,
      counts: PhaseCounts(completed: 2, total: 5, inactive: 0),
      packingSubline: nil
    )
    #expect(label == "Departure day, current phase, 2 of 5 tasks complete")
  }

  @Test("Past state speaks as 'past'")
  func pastState() {
    let label = PhaseRow<EmptyView>.accessibilityLabel(
      phase: .dayBefore,
      state: .past,
      counts: PhaseCounts(completed: 3, total: 3, inactive: 0),
      packingSubline: nil
    )
    #expect(label == "Day before, past, 3 of 3 tasks complete")
  }

  @Test("Future state speaks as 'upcoming'")
  func futureState() {
    let label = PhaseRow<EmptyView>.accessibilityLabel(
      phase: .returnDay,
      state: .future,
      counts: PhaseCounts(completed: 0, total: 4, inactive: 0),
      packingSubline: nil
    )
    #expect(label == "Return day, upcoming, 0 of 4 tasks complete")
  }

  @Test("Zero-task phase omits the count clause")
  func zeroTasksOmitted() {
    let label = PhaseRow<EmptyView>.accessibilityLabel(
      phase: .duringTrip,
      state: .future,
      counts: PhaseCounts(completed: 0, total: 0, inactive: 0),
      packingSubline: nil
    )
    #expect(label == "During trip, upcoming")
  }

  @Test("Inactive count appended after task count")
  func inactiveAppended() {
    let label = PhaseRow<EmptyView>.accessibilityLabel(
      phase: .weeksBefore,
      state: .past,
      counts: PhaseCounts(completed: 2, total: 3, inactive: 1),
      packingSubline: nil
    )
    #expect(label == "Weeks before, past, 2 of 3 tasks complete, plus 1 inactive")
  }

  @Test("Packing subline (e.g. 'Alice 2 / 3 packed') appears at the tail")
  func packingSublineAppended() {
    let label = PhaseRow<EmptyView>.accessibilityLabel(
      phase: .dayBefore,
      state: .current,
      counts: PhaseCounts(completed: 0, total: 0, inactive: 0),
      packingSubline: "Alice 2 / 3 packed"
    )
    #expect(label == "Day before, current phase, Alice 2 / 3 packed")
  }

  // MARK: - Hint flips with expansion state

  @Test("Hint reflects the current expansion state")
  func hintFlipsWithExpansion() {
    #expect(
      PhaseRow<EmptyView>.accessibilityHint(expandable: true, isExpanded: false)
        == "double tap to expand"
    )
    #expect(
      PhaseRow<EmptyView>.accessibilityHint(expandable: true, isExpanded: true)
        == "double tap to collapse"
    )
  }

  @Test("Non-expandable spine markers expose an empty hint")
  func nonExpandableNoHint() {
    #expect(
      PhaseRow<EmptyView>.accessibilityHint(expandable: false, isExpanded: false) == "")
    #expect(
      PhaseRow<EmptyView>.accessibilityHint(expandable: false, isExpanded: true) == "")
  }
}
