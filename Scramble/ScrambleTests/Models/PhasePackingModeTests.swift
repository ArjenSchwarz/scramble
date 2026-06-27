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

  @Test("Departure day is no longer a packing phase")
  func departureDayHostsNoPacking() {
    #expect(Phase.departureDay.packingMode == nil)
  }

  @Test("Exactly two phases are packing phases; the rest host none")
  func onlyTwoPackingPhases() {
    let packingPhases = Set(Phase.allCases.filter { $0.packingMode != nil })
    #expect(packingPhases == [.dayBefore, .dayBeforeReturn])
  }
}
