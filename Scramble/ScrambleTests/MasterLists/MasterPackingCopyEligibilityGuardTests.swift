import Testing

@testable import Scramble

/// PR-review Fix B — drives `MasterPackingList.isCopyEligible(trimmedName:hasOwner:peopleCount:)`,
/// the pure source-eligibility decision for the per-row copy affordance (Req 1.3
/// / Decision 6). Eligible requires: at least two people exist, the source has an
/// owner, and its trimmed name is non-empty. Pure function — no container needed.
@Suite("MasterPackingList.isCopyEligible")
struct MasterPackingCopyEligibilityGuardTests {

  @Test("Fewer than two people → not eligible")
  func tooFewPeople() {
    #expect(
      MasterPackingList.isCopyEligible(trimmedName: "Socks", hasOwner: true, peopleCount: 1)
        == false
    )
    #expect(
      MasterPackingList.isCopyEligible(trimmedName: "Socks", hasOwner: true, peopleCount: 0)
        == false
    )
  }

  @Test("No owner → not eligible")
  func noOwner() {
    #expect(
      MasterPackingList.isCopyEligible(trimmedName: "Socks", hasOwner: false, peopleCount: 2)
        == false
    )
  }

  @Test("Empty / whitespace-only trimmed name → not eligible")
  func emptyName() {
    #expect(
      MasterPackingList.isCopyEligible(trimmedName: "", hasOwner: true, peopleCount: 2)
        == false
    )
  }

  @Test("All conditions satisfied → eligible")
  func allSatisfied() {
    #expect(
      MasterPackingList.isCopyEligible(trimmedName: "Socks", hasOwner: true, peopleCount: 2)
    )
  }
}
