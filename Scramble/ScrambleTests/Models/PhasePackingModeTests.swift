import Testing

@testable import Scramble

/// Pins the single source of truth for "which phase hosts which packing mode".
/// `AccordionTimeline` (summary block + sheet entry) and
/// `TripDetailView.autoExpandPhase` both derive their packing behaviour from
/// `Phase.packingMode`, so this mapping defines where the packing UI appears.
@Suite("Phase.packingMode")
struct PhasePackingModeTests {

  @Test("Pack mode lives on .dayBefore")
  func dayBeforeIsPack() {
    #expect(Phase.dayBefore.packingMode == .pack)
  }

  @Test("Repack mode lives on .dayBeforeReturn")
  func dayBeforeReturnIsRepack() {
    #expect(Phase.dayBeforeReturn.packingMode == .repack)
  }

  @Test("Exactly two phases are packing phases; the rest (incl. .departureDay) host none")
  func onlyTwoPackingPhases() {
    // Completeness invariant, not just the two positive mappings above: asserts
    // that NO other phase — including the former .departureDay packing phase —
    // hosts packing. Catches a future Phase case being wired to a packing mode
    // (or .departureDay regressing back) without a matching test update.
    let packingPhases = Set(Phase.allCases.filter { $0.packingMode != nil })
    #expect(packingPhases == [.dayBefore, .dayBeforeReturn])
  }
}
