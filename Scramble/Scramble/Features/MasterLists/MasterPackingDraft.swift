import Foundation

/// Value-type editor state for the master-packing create/edit screen.
nonisolated struct MasterPackingDraft: Equatable, Sendable {
  var name: String
  var personID: UUID?
  var conditions: ItemConditions

  nonisolated enum Field: Hashable, Sendable {
    case name
    case person
  }

  func validate() -> [Field: String] {
    var errors: [Field: String] = [:]
    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      errors[.name] = "Name is required"
    }
    if personID == nil {
      errors[.person] = "Choose a person"
    }
    return errors
  }
}

extension MasterPackingDraft {
  nonisolated static func newDraft(personID: UUID? = nil) -> MasterPackingDraft {
    MasterPackingDraft(name: "", personID: personID, conditions: .always)
  }

  @MainActor
  init(from master: MasterPackingItem) {
    self.name = master.name
    self.personID = master.person?.id
    self.conditions = master.conditions
  }
}
