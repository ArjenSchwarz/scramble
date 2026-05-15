import SwiftUI
import Testing

@testable import Scramble

@Suite("WhyDisclosure.Style appearance mapping")
struct WhyDisclosureStyleTests {

  // MARK: - .tasks(phaseColour:)

  @Test("tasks variant uses phase colour as tint")
  func tasksTintIsPhaseColour() {
    let phase = Color.red
    let appearance = WhyDisclosure.Style.tasks(phaseColour: phase).resolvedAppearance
    #expect(appearance.tint == phase)
  }

  @Test("tasks variant uses 8% background opacity")
  func tasksBackgroundOpacity() {
    let appearance = WhyDisclosure.Style.tasks(phaseColour: .blue).resolvedAppearance
    #expect(appearance.backgroundOpacity == 0.08)
  }

  @Test("tasks variant uses 20% border opacity")
  func tasksBorderOpacity() {
    let appearance = WhyDisclosure.Style.tasks(phaseColour: .blue).resolvedAppearance
    #expect(appearance.borderOpacity == 0.20)
  }

  // MARK: - .packing(personColour:)

  @Test("packing variant uses person colour as tint")
  func packingTintIsPersonColour() {
    let person = Color.green
    let appearance = WhyDisclosure.Style.packing(personColour: person).resolvedAppearance
    #expect(appearance.tint == person)
  }

  @Test("packing variant uses 6% background opacity")
  func packingBackgroundOpacity() {
    let appearance = WhyDisclosure.Style.packing(personColour: .green).resolvedAppearance
    #expect(appearance.backgroundOpacity == 0.06)
  }

  @Test("packing variant has no border")
  func packingBorderIsNil() {
    let appearance = WhyDisclosure.Style.packing(personColour: .green).resolvedAppearance
    #expect(appearance.borderOpacity == nil)
  }
}
