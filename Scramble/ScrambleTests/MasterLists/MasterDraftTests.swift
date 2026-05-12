import Foundation
import Testing

@testable import Scramble

@Suite("MasterTaskDraft.validate")
struct MasterTaskDraftTests {

  private static func draft(
    name: String = "Pack passports",
    phase: Phase = .weeksBefore,
    conditions: ItemConditions = .always
  ) -> MasterTaskDraft {
    MasterTaskDraft(name: name, phase: phase, conditions: conditions)
  }

  @Test("Valid name → empty error map")
  func valid() {
    let errors = Self.draft().validate()
    #expect(errors.isEmpty)
  }

  @Test("Empty name → .name error")
  func emptyName() {
    let errors = Self.draft(name: "").validate()
    #expect(Set(errors.keys) == [.name])
  }

  @Test("Whitespace-only name → .name error")
  func whitespaceName() {
    let errors = Self.draft(name: "   \n\t ").validate()
    #expect(Set(errors.keys) == [.name])
  }
}

@Suite("MasterPackingDraft.validate")
struct MasterPackingDraftTests {

  private static func draft(
    name: String = "Rain jacket",
    personID: UUID? = UUID(),
    conditions: ItemConditions = .always
  ) -> MasterPackingDraft {
    MasterPackingDraft(name: name, personID: personID, conditions: conditions)
  }

  @Test("Valid name + person → empty error map")
  func valid() {
    let errors = Self.draft().validate()
    #expect(errors.isEmpty)
  }

  @Test("Empty name → .name error only")
  func emptyName() {
    let errors = Self.draft(name: "").validate()
    #expect(Set(errors.keys) == [.name])
  }

  @Test("Nil person → .person error only")
  func nilPerson() {
    let errors = Self.draft(personID: nil).validate()
    #expect(Set(errors.keys) == [.person])
  }

  @Test("Empty name AND nil person → both errors")
  func bothInvalid() {
    let errors = Self.draft(name: "", personID: nil).validate()
    #expect(Set(errors.keys) == [.name, .person])
  }
}
